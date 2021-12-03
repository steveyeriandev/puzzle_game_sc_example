pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';

contract Jigsaw1 is ERC721Enumerable, Ownable {
    using MerkleProof for bytes32[];
    using Strings for uint256;
    using ECDSA for bytes32;

    /// @notice Total Private Sale
    uint256 public constant jigsawPresale = 96;
    /// @notice Total Fiat Sale
    uint256 public constant jigsawFiat = 500;
    /// @notice Total Supply
    uint256 public constant jigsawTotal = 4096;
    /// @notice Token Price
    uint256 public constant price = 0.2 ether;
    /// @notice allow users to mint up to 5 per wallet
    uint256 public constant MAX_MINTED_NUMBER = 5;
    /// @notice Token has been minted to the address
    mapping(address => uint256) public hasMinted;
    /// @notice Address can mint the private sale
    mapping(address => bool) public privateSaleEntries;

    /// @notice Token Base URI
    string private _tokenBaseURI;

    /// @notice Community Pool - 20% of the mint fee
    uint256 public constant communityRatio = 2000;
    /// @notice Community Merkle Root
    bytes32 public communityRoot;
    /// @notice Community Reward Claimed
    mapping(address => bool) public isClaimedCommunity;

    /// @notice Charity Pool - 20% of the mint fee
    uint256 public constant charityRatio = 2000;

    /// @notice Charity, Vote amount, Pool address, Reward ratio
    struct CharityInfo {
        bytes32 charity;
        uint256 vote;
        address payable pool;
        uint256 ratio;
    }

    /// @notice Charity vote infos
    CharityInfo[] public charityInfos;

    /// @notice Bored Puzzles - 60% of the mint fee
    uint256 public constant boredRatio = 6000;
    /// @notice Bored Puzzles Address
    address payable public boredAddress;

    /// @notice Count of Public Saled Tokens
    uint256 public publicCounter;
    /// @notice Count of Fiat Saled Tokens
    uint256 public fiatCounter;
    /// @notice Count of Private Saled Tokens
    uint256 public privateCounter;
    /// @notice Start timestamp for the Private Sale
    uint256 public privateSaleBegin = 2**256 - 1;
    /// @notice Start timestamp for the Fiat Sale
    uint256 public fiatSaleBegin = 2**256 - 1;
    /// @notice Start timestamp for the Public Sale
    uint256 public publicSaleBegin = 2**256 - 1;

    /// @notice Game period
    uint256 public constant period = 5 days;
    /// @notice Game Started At
    uint256 public startedAt;
    /// @notice Game Ended At
    uint256 public endedAt;

    /// @notice Editable for Token Base URI
    bool public editable;

    /// @notice Total Fee
    uint256 public totalFee;
    /// @notice Estimated Gas for Mint
    uint256 public estimatedGasForMint = 20000;

    /// @notice Events
    event StartGame(uint256 indexed at);
    event EndGame(uint256 indexed at);
    event UploadedCommunityRoot();
    event ClaimedCommunity(address indexed account, uint256 amount);
    event ClaimedCharity(
        bytes32 indexed charity,
        address indexed pool,
        uint256 amount
    );

    modifier onlyEditable() {
        require(editable, 'METADATA_FUNCTIONS_LOCKED');
        _;
    }

    constructor() ERC721('Bored Puzzles Jigsaw1', 'BPJ1') {
        _tokenBaseURI = '';
    }

    function safeTransferETH(address payable _to, uint256 _amount)
        internal
        returns (bool success)
    {
        if (_amount > address(this).balance) {
            (success, ) = _to.call{value: address(this).balance}('');
        } else {
            (success, ) = _to.call{value: _amount}('');
        }
    }

    ///--------------------------------------------------------
    /// Public Sale
    /// Fiat Sale
    /// Private Sale
    ///--------------------------------------------------------

    /**
     * @notice Mint on Public Sale
     */
    function mint() external payable {
        require(
            block.timestamp >= publicSaleBegin || fiatCounter >= jigsawFiat,
            'ER: Public sale is not started'
        );
        require(totalSupply() < jigsawTotal, 'ER: The sale is sold out');
        require( hasMinted[msg.sender] < MAX_MINTED_NUMBER, 'ER: You have already minted');

        // Calculate Mint Fee with Gas Substraction
        uint256 mintFee = price - tx.gasprice * estimatedGasForMint;
        require(mintFee <= msg.value, 'ER: Not enough ETH');

        /// @notice Return any ETH to be refunded
        uint256 refund = msg.value - mintFee;
        if (refund > 0) {
            require(
                safeTransferETH(payable(msg.sender), refund),
                'ER: Return any ETH to be refunded'
            );
        }

        publicCounter++;
        totalFee += mintFee;
        hasMinted[msg.sender]++;
        _safeMint(msg.sender, totalSupply() + 1);
    }

    /**
     * @notice Admin can mint to the users for Fiat Sale
     * @param _to Users wallet addresses
     */
    function safeMint(address[] memory _to) external payable onlyOwner {
        require(
            block.timestamp >= fiatSaleBegin || privateCounter >= jigsawPresale,
            'ER: Fiat sale is not started'
        );
        require(
            block.timestamp < publicSaleBegin,
            'ER: Fiat sale is currently closed'
        );

        uint256 length = _to.length;

        for (uint256 i = 0; i < length; i++) {
            address to = _to[i];
            if (hasMinted[to]<MAX_MINTED_NUMBER) {
                require(
                    totalSupply() < jigsawTotal,
                    'ER: The sale is sold out'
                );
                require(
                    fiatCounter < jigsawFiat,
                    'ER: Not enough Jigsaws left for the fiat sale'
                );

                fiatCounter++;
                hasMinted[to]++;
                _safeMint(to, totalSupply() + 1);
            }
        }

        totalFee += msg.value;
    }

    /**
     * @notice Mint on Private Sale
     */
    function privateMint() external payable {
        require(
            block.timestamp >= privateSaleBegin,
            'ER: Private sale is not started'
        );
        require(
            block.timestamp < fiatSaleBegin,
            'ER: Private sale is currently closed'
        );
        require(
            privateSaleEntries[msg.sender],
            'ER: You are not qualified for the presale'
        );
        require(totalSupply() < jigsawTotal, 'ER: The sale is sold out');
        require(
            privateCounter < jigsawPresale,
            'ER: Not enough Jigsaws left for the presale'
        );
        require(hasMinted[msg.sender]<MAX_MINTED_NUMBER, 'ER: You have already minted');

        // Calculate Mint Fee with Gas Substraction
        uint256 mintFee = price - tx.gasprice * estimatedGasForMint;
        require(mintFee <= msg.value, 'ER: Not enough ETH');

        /// @notice Return any ETH to be refunded
        uint256 refund = msg.value - mintFee;
        if (refund > 0) {
            require(
                safeTransferETH(payable(msg.sender), refund),
                'ER: Return any ETH to be refunded'
            );
        }

        privateCounter++;
        totalFee += mintFee;
        hasMinted[msg.sender]++;
        _safeMint(msg.sender, totalSupply() + 1);
    }

    ///--------------------------------------------------------
    /// Insert private buyers
    /// Remove private buyers
    ///--------------------------------------------------------

    /**
     * @notice Admin can insert the addresses to mint the presale
     * @param privateEntries Addresses for the presale
     */
    function insertPrivateSalers(address[] calldata privateEntries)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < privateEntries.length; i++) {
            require(privateEntries[i] != address(0), 'ER: Null Address');
            require(
                !privateSaleEntries[privateEntries[i]],
                'ER: Duplicate Entry'
            );

            privateSaleEntries[privateEntries[i]] = true;
        }
    }

    /**
     * @notice Admin can stop the addresses to not mint the presale
     * @param privateEntries Addresses for the non-presale
     */
    function removePrivateSalers(address[] calldata privateEntries)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < privateEntries.length; i++) {
            require(privateEntries[i] != address(0), 'ER: Null Address');

            privateSaleEntries[privateEntries[i]] = false;
        }
    }

    ///--------------------------------------------------------
    /// Sales Begin Timestamp
    /// Start Game
    /// End Game
    ///--------------------------------------------------------

    /**
     * @notice Admin can set the privateSaleBegin, fiatSaleBegin, publicSaleBegin timestamp
     * @param _privateSaleBegin Timestamp to begin the private sale
     * @param _fiatSaleBegin Timestamp to begin the fiat sale
     * @param _publicSaleBegin Timestamp to begin the public sale
     */
    function setSalesBegin(
        uint256 _privateSaleBegin,
        uint256 _fiatSaleBegin,
        uint256 _publicSaleBegin
    ) external onlyOwner {
        require(
            _privateSaleBegin < _fiatSaleBegin &&
                _fiatSaleBegin < _publicSaleBegin,
            'ER: Invalid timestamp for sales'
        );

        privateSaleBegin = _privateSaleBegin;
        fiatSaleBegin = _fiatSaleBegin;
        publicSaleBegin = _publicSaleBegin;
    }

    /**
     * @notice Admin can start the game
     * @param _boredAddress Bored Puzzles address
     */
    function startGame(address payable _boredAddress) external onlyOwner {
        require(
            _boredAddress != address(0),
            'ER: Invalid Bored Puzzle address'
        );
        require(startedAt == 0, 'ER: Game is already began');

        startedAt = block.timestamp;
        boredAddress = _boredAddress;

        uint256 amount = (totalFee * boredRatio) / 1e4;
        require(
            safeTransferETH(boredAddress, amount),
            'ER: ETH transfer to Bored Puzzles failed'
        );

        emit StartGame(startedAt);
    }

    /**
     * @notice Admin can end the game
     */
    function endGame() external onlyOwner {
        require(startedAt > 0, 'ER: Game is not started yet');

        endedAt = block.timestamp;

        emit EndGame(endedAt);
    }

    ///--------------------------------------------------------
    /// Upload Coummunity Merkle Root
    /// Claim the Community Reward
    /// Upload Charity Vote Result
    ///--------------------------------------------------------

    /**
     * @notice Admin can upload the Community root
     * @param _communityRoot Community Distribution Merkle Root
     */
    function uploadCommunityRoot(bytes32 _communityRoot) external onlyOwner {
        require(endedAt > 0, 'ER: Game is not ended yet');
        require(
            communityRoot == bytes32(0),
            'ER: Community Root is already set'
        );

        communityRoot = _communityRoot;

        emit UploadedCommunityRoot();
    }

    /**
     @notice Claim the community reward
     @param _account Receiver address
     @param _percent Reward percent
     @param _proof Merkle proof data
     */
    function claimCommunity(
        address _account,
        uint256 _percent,
        bytes32[] memory _proof
    ) external {
        require(endedAt > 0, 'ER: Game is not ended yet');
        require(!isClaimedCommunity[_account], 'ER: Community claimed already');
        bytes32 node = keccak256(abi.encodePacked(_account, _percent));
        require(
            _proof.verify(communityRoot, node),
            'ER: Community claim wrong proof'
        );

        uint256 delayPeriod;
        if ((endedAt - startedAt) > period) {
            delayPeriod = (endedAt - startedAt) - period;
        }
        uint256 delaySeconds = delayPeriod % 1 days;
        uint256 delayDays = delayPeriod / 1 days;

        uint256 communityAmount = (totalFee *
            communityRatio *
            (period - 1 days)**delayDays *
            (1 days - delaySeconds)) / ((period**delayDays) * 1 days * 1e4);
        uint256 amount = (communityAmount * _percent) / 1e4;

        isClaimedCommunity[_account] = true;
        if (safeTransferETH(payable(msg.sender), amount)) {
            emit ClaimedCommunity(msg.sender, amount);
        }
    }

    /**
     * @notice Admin can upload the Charity vote result
     * @param _charityInfos Charity vote result
     */
    function uploadCharityInfos(CharityInfo[] memory _charityInfos)
        external
        onlyOwner
    {
        require(endedAt > 0, 'ER: Game is not ended yet');
        require(_charityInfos.length > 0, 'ER: Invalid Charity Info');
        require(charityInfos.length == 0, 'Er: Charity Info is already set');

        uint256 delayPeriod;
        if ((endedAt - startedAt) > period) {
            delayPeriod = (endedAt - startedAt) - period;
        }
        uint256 delaySeconds = delayPeriod % 1 days;
        uint256 delayDays = delayPeriod / 1 days;

        uint256 communityAmount = (totalFee *
            communityRatio *
            (period - 1 days)**delayDays *
            (1 days - delaySeconds)) / ((period**delayDays) * 1 days * 1e4);
        uint256 charityAmount = (totalFee * (communityRatio + charityRatio)) /
            1e4 -
            communityAmount;

        uint256 maxVote;
        uint256 count;
        uint256 length = _charityInfos.length;

        for (uint256 i = 0; i < length; i++) {
            uint256 vote = _charityInfos[i].vote;
            if (maxVote == vote) {
                count++;
            } else if (maxVote < vote) {
                maxVote = vote;
                count = 1;
            }
        }

        for (uint256 i = 0; i < length; i++) {
            CharityInfo memory info = _charityInfos[i];
            if (info.vote == maxVote) {
                info.ratio = 1e4 / count;

                uint256 amount = charityAmount / count;
                if (safeTransferETH(info.pool, amount)) {
                    emit ClaimedCharity(info.charity, info.pool, amount);
                }
            } else {
                info.ratio = 0;
            }
            charityInfos.push(info);
        }
    }

    ///--------------------------------------------------------
    /// Token Editable
    /// Token BaseURI
    /// Token Mint Gas
    ///--------------------------------------------------------

    /**
     * @notice Admin can enable/disable the editable
     * @param _editable Can Edit
     */
    function setEditable(bool _editable) external onlyOwner {
        editable = _editable;
    }

    /**
     * @notice Admin can set the Token Base URI but it should be editable
     * @param _URI Token Base URI
     */
    function setBaseURI(string calldata _URI) external onlyOwner onlyEditable {
        _tokenBaseURI = _URI;
    }

    /**
     * @notice Admin can update the estimated Gas for Mint
     * @param _estimatedGasForMint Can Edit
     */
    function setEstmatedGasForMint(uint256 _estimatedGasForMint)
        external
        onlyOwner
    {
        estimatedGasForMint = _estimatedGasForMint;
    }

    ///--------------------------------------------------------
    /// View functions
    ///--------------------------------------------------------

    /**
     * @notice Each token's URI
     * @param tokenId Token ID
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        require(_exists(tokenId), 'Cannot query non-existent token');

        return string(abi.encodePacked(_tokenBaseURI, tokenId.toString()));
    }

    /**
     * @notice Get all token's owner addresses
     */
    function grabAllOwners() external view returns (address[] memory) {
        address[] memory owners = new address[](totalSupply());
        for (uint256 i = 0; i < totalSupply(); i++) {
            owners[i] = ownerOf(i + 1);
        }
        return owners;
    }
}
