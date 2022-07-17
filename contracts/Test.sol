// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title A contract for ....
/// @notice NFT Minting
contract Test is ERC721, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    uint256 private _tokenId;
    
    // Team wallet
    address [] teamWalletList = [
       0x0CC494215f952b7cD96378D803a0D3a6CAb282b0,         // Wallet 1 address
       0x214Fe0B10F0b2C4ea182F25DDdA95130C250C3e1         // Wallet 2 address
    ];
    
    mapping (address => uint256) teamWalletPercent;
    
    // Minting Limitation
    uint256 public totalLimit = 1500;
    uint256[] public stageMintLimit = [75, 150, 225];
    
    /**
     * Stage flag
     * 0:   Alpha Test (Whitelist)
     * 1:   Beta Test (Whitelist)
     * 2:   Presale (Whitelist)
     * 3:   Public sale (Dutch Auction)
     */ 
    uint256 public stage;

    // Merkle Tree Root
    bytes32[] private merkleRoot;
    
    // Presale Mint Price
    uint256[] public presaleMintPrice = [0.1 ether, 0.15 ether, 0.25 ether];

    // Public Mint(Dutch auction) Price
    uint256 public auctionPriceBegin = 1 ether;
    uint256 public auctionPriceEnd = 0.4 ether;

    // Auction Time
    uint256 public auctionBeginTime;    // Epoch Time(second)
    uint256 public auctionTime;         // second


    // BaseURI
    string private baseURI;

    uint256 private transactionLimit = 10;

    constructor() ERC721("", "") {
        teamWalletPercent[teamWalletList[0]] = 70;         // Wallet 1 percent
        teamWalletPercent[teamWalletList[1]] = 30;         // Wallet 2 percent
    }

    event Mint (address indexed _from, 
                uint256 _stage, 
                uint256 _tokenId, 
                uint256 _mintPrice,    
                uint256 _mintCount);

    event Setting ( uint256 _stage,
                    uint256 _presaleMintPrice,
                    uint256 _auctionPriceBegin,
                    uint256 _auctionPriceEnd,
                    uint256 _auctionBeginTime,
                    uint256 _auctionTime,
                    uint256 _transactionLimit);

    /**
     * Override tokenURI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json"));
    }

    /**
     * Address -> leaf for MerkleTree
     */
    function _leaf(address account) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(account));
    }

    /**
     * Verify WhiteList using MerkleTree
     */
    function verifyWhitelist(bytes32 leaf, bytes32[] memory proof) private view returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash < proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == merkleRoot[stage];
    }

    /**
     * Presale with WhiteList
     * stage:       0: Alpha Tester
     *              1: Beta Tester
     *              2: Presale
     */
    function mintPresale(uint256 _mintCount, bytes32[] memory _proof) external payable nonReentrant returns (uint256) {
        
        require(msg.sender != address(0));
        require(stage >= 0 && stage < 3, "Presale is over");
        require(_mintCount > 0 && _mintCount <= transactionLimit, "Mint amount is over transaction limitation");
        require(_mintCount <= stageMintLimit[stage], "Total mint limiation for the current stage is over");
        require(msg.value == (presaleMintPrice[stage] * _mintCount), "Balance is not enough");
        require(verifyWhitelist(_leaf(msg.sender), _proof) == true, "Sender is not whitelisted");

        for (uint256 i = 0; i < _mintCount; i++) {
            _tokenId++;
            _safeMint(msg.sender, _tokenId);
        }

        stageMintLimit[stage] -= _mintCount;
        totalLimit -= _mintCount;

        emit Mint(msg.sender, 
                    stage, 
                    _tokenId,
                    presaleMintPrice[stage],
                    _mintCount);
        
        return _tokenId;
    }

    /**
     * Public Sale
     * stage:       3
     * auction type: dutch (auctionPriceBegin -> auctionPriceEnd)
     */
    function mintPublic(uint256 _mintCount) external payable nonReentrant returns (uint256) {
        
        require(msg.sender != address(0));
        require(stage == 4, "The current stage is not public sale");
        require(_mintCount > 0 && _mintCount <= transactionLimit, "Mint amount is over transaction limitation");
        require(_mintCount <= totalLimit, "Sold out");

        uint256 currentPrice = auctionPriceBegin - (auctionPriceBegin - auctionPriceEnd) * (block.timestamp - auctionBeginTime) / auctionTime;
        require(msg.value >= (currentPrice * _mintCount), "Balance is not enough");

        for (uint256 i = 0; i < _mintCount; i++) {
            _tokenId++;
            _safeMint(msg.sender, _tokenId);
        }

        totalLimit -= _mintCount;

        emit Mint(msg.sender, 
                    stage, 
                    _tokenId,
                    currentPrice,
                    _mintCount);
        
        return _tokenId;
    }

    function mintAdmin(uint256 _mintCount) external onlyOwner returns (uint256) {
        
        require(msg.sender != address(0));
        require(_mintCount <= totalLimit, "Sold out");

        for (uint256 i = 0; i < _mintCount; i++) {
            _tokenId++;
            _safeMint(msg.sender, _tokenId);
        }

        totalLimit -= _mintCount;

        emit Mint(msg.sender, 
                    stage, 
                    _tokenId,
                    0,
                    _mintCount);
        
        return _tokenId;
    }

    // Get Balance
    function getBalance() external view onlyOwner returns (uint256) {
        return address(this).balance;
    }
    
    // Withdraw
    function withdraw() external onlyOwner nonReentrant {
        require(address(this).balance != 0);
        
        uint256 balance = address(this).balance;

        for (uint256 i = 0; i < teamWalletList.length; i++) {
            (bool success, ) = teamWalletList[i].call{value: balance.div(100).mul(teamWalletPercent[teamWalletList[i]])}("");
            require(success, string(abi.encodePacked("Failed to send to ", teamWalletList[i])));
        }
    }

    /*
     * Get current auction price
     */
    function getCurrentAuctionPrice() external view returns (uint256) {
        uint256 currentAuctionPrice = auctionPriceBegin - (auctionPriceBegin - auctionPriceEnd) * (block.timestamp - auctionBeginTime) / auctionTime;
        return currentAuctionPrice;
    }

    /**
     * Get TokenList by sender
     */
    function getTokenList(address account) external view returns (uint256[] memory) {
        require(account != address(0));

        uint256 count = balanceOf(account);
        uint256[] memory tokenIdList = new uint256[](count);

        if (count == 0)
            return tokenIdList;

        uint256 cnt = 0;
        for (uint256 i = 1; i < (_tokenId + 1); i++) {

            if (_exists(i) && (ownerOf(i) == account)) {
                tokenIdList[cnt++] = i;
            }

            if (cnt == count)
                break;
        }

        return tokenIdList;
    }

    /**
     * Get Setting
     *  0 :     stage
     *  1 :     presaleMintPrice
     *  2 :     auctionPriceBegin
     *  3 :     auctionPriceEnd
     *  4 :     auctionBeginTime
     *  5 :     auctionTime
     *  6 :     transactionLimit
     */
    function getSetting() external view returns (uint256[] memory) {
        uint256[] memory setting = new uint256[](6);
        setting[0] = stage;
        setting[1] = (stage < 3) ? presaleMintPrice[stage] : 0;
        setting[2] = auctionPriceBegin;
        setting[3] = auctionPriceEnd;
        setting[4] = auctionBeginTime;
        setting[5] = auctionTime;
        setting[7] = transactionLimit;
        return setting;
    }

    /// Set Methods

    function setBaseURI(string memory _baseURI) external onlyOwner returns (string memory) {
        baseURI = _baseURI;
        return baseURI;
    }

    /**
     * Stage flag
     * 0:   Alpha Test (Whitelist)
     * 1:   Beta Test (Whitelist)
     * 2:   Presale (Whitelist)
     * 3:   Public sale (Dutch Auction)
     */ 
    function setStage(uint256 _stage) external onlyOwner returns (uint256) {
        require(_stage >= 0 && _stage < 4);
        stage = _stage;

        if(stage == 3)      // Public sale begins & set auction begin time
            auctionBeginTime = block.timestamp;

        emit Setting(stage, 
                    presaleMintPrice[stage], 
                    auctionPriceBegin, 
                    auctionPriceEnd,
                    auctionBeginTime, 
                    auctionTime, 
                    transactionLimit);
        return stage;
    }

    function setAuctionTime(uint256 _auctionTime) external onlyOwner returns (uint256) {
        auctionTime = _auctionTime;
        return auctionTime;
    }

    function setMerkleRoot(uint256 _stage, bytes32 _merkleRoot) external onlyOwner returns (bytes32[] memory) {
        merkleRoot[_stage] = _merkleRoot;
        return merkleRoot;
    }

    function setPresalePrice(uint256 _stage, uint256 _price) external returns (uint256[] memory) {
        require(_stage >= 0 && _stage < 3);
        presaleMintPrice[_stage] = _price;
        return presaleMintPrice;
    }

    function setAuctionPrice(uint256 _auctionPriceBegin, uint256 _auctionPriceEnd) external {
        auctionPriceBegin = _auctionPriceBegin;
        auctionPriceEnd = _auctionPriceEnd;
    }

    function setTotalLimit(uint256 _totalLimit) external onlyOwner returns (uint256) {
        totalLimit = _totalLimit;
        return totalLimit;
    }

    function setStageMintLimit(uint256 _stage, uint256 _limit) external returns (uint256[] memory) {
        require(_stage >= 0 && _stage < 3);
        stageMintLimit[_stage] = _limit;
        return stageMintLimit;
    }

    function setTransactionLimit(uint256 _transactionLimit) external onlyOwner returns (uint256) {
        transactionLimit = _transactionLimit;
        return transactionLimit;
    }
}