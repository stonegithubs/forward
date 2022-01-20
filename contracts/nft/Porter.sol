// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./ERC721A.sol";
import "../interface/IForwardEtherRouter.sol";

contract Porter is ERC721A, Ownable {
    
    address private signer;
    address public immutable forward;
    IForwardEtherRouter public immutable router;
    uint256 public tokensReserved;
    uint256 public immutable maxMint;
    uint256 public immutable maxSupply;
    uint256 public immutable reserveAmount;
    uint256 public constant PRICE = 0.001 ether;
    uint256 public constant deliveryMin = 1 weeks;
    uint256 public constant deliveryMax = 30 days;
    bool public balanceWithdrawn;
    
    enum Status {
        Pending,
        PreSale,
        PublicSale,
        Finished
    }
    Status public status;
    string public baseURI;

    mapping(address => bool) public publicMinted;

    event Minted(address minter, uint256 amount);
    event StatusChanged(Status status);
    event SignerChanged(address signer);
    event ReservedToken(address minter, address recipient, uint256 amount);
    event BaseURIChanged(string newBaseURI);

    constructor(
        string memory _initBaseURI,
        address _signer,
        uint256 _maxBatchSize,
        uint256 _collectionSize,
        uint256 _reserveAmount,
        address _forward,
        address _router
    ) ERC721A("Test NFT Name", "TestSymbol", _maxBatchSize, _collectionSize) {
        baseURI = _initBaseURI;
        signer = _signer;
        maxMint = _maxBatchSize;
        maxSupply = _collectionSize;
        reserveAmount = _reserveAmount;
        forward = _forward;
        router = IForwardEtherRouter(_router);
    }

    function _verifySig(address _sender, string calldata _salt, bytes memory _sig)
        internal
        view
        returns (bool)
    {
        return ECDSA.recover(keccak256(abi.encode(_sender, address(this), _salt)), _sig) == signer;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function reserve(address recipient, uint256 amount) external onlyOwner {
        require(recipient != address(0), "XRC: zero address");
        require(amount > 0, "XRC: invalid amount");
        require(
            totalSupply() + amount <= collectionSize,
            "XRC: max supply exceeded"
        );
        require(
            tokensReserved + amount <= reserveAmount,
            "XRC: max reserve amount exceeded"
        );
        require(
            amount % maxBatchSize == 0,
            "XRC: can only mint a multiple of the maxBatchSize"
        );

        uint256 numChunks = amount / maxBatchSize;
        for (uint256 i = 0; i < numChunks; i++) {
            _safeMint(recipient, maxBatchSize);
        }
        tokensReserved += amount;
        emit ReservedToken(msg.sender, recipient, amount);
    }

    function presaleMint(
        uint256 amount,
        string calldata salt,
        bytes calldata sig
    ) external payable {
        require(status == Status.PreSale, "XRC: Presale is not active.");
        require(
            tx.origin == msg.sender,
            "XRC: contract is not allowed to mint."
        );
        require(_verifySig(msg.sender, salt, sig), "XRC: Invalid token.");
        require(
            numberMinted(msg.sender) + amount <= maxMint,
            "XRC: Max mint amount per wallet exceeded."
        );
        require(
            totalSupply() + amount + reserveAmount - tokensReserved <=
                collectionSize,
            "XRC: Max supply exceeded."
        );

        _safeMint(msg.sender, amount);
        _createForwardOrders(msg.sender, amount);
        refundIfOver(PRICE * amount);

        emit Minted(msg.sender, amount);
    }

    function mint() external payable {
        require(status == Status.PublicSale, "XRC: Public sale is not active.");
        require(
            tx.origin == msg.sender,
            "XRC: contract is not allowed to mint."
        );
        require(
            !publicMinted[msg.sender],
            "XRC: The wallet has already minted during public sale."
        );
        require(
            totalSupply() + 1 + reserveAmount - tokensReserved <=
                collectionSize,
            "XRC: Max supply exceeded."
        );

        _safeMint(msg.sender, 1);
        _createForwardOrders(msg.sender, 1);
        publicMinted[msg.sender] = true;
        refundIfOver(PRICE);

        emit Minted(msg.sender, 1);
    }

    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "XRC: Need to send more ETH.");
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }


    function _createForwardOrders(address sender, uint amount) internal {
        uint supply = totalSupply();
        uint[] memory tokenIds = new uint[](1);

        uint orderIndex = router.ordersLengh(forward);
        for (uint i = amount; i > 0; i--) {
            tokenIds[0] = supply - i;
            router.createOrder721For(
                forward, 
                sender, 
                tokenIds, 
                [1 minutes, _calcDeliveryStart(tokenIds[0]), 24 hours],  /** 0: orderValidTime till nobody can take it, 1: deliveryTime, 2: deliveryDuration(default: 24 hours) */
                [PRICE, PRICE, 0],  /** 0: deliveryPrice, 1: buyerMargin, 2: sellerMargin, Here, we don't charge user's margin if he decides to sell nft at delivery time */
                new address[](0),   /** order taker whitelist */
                false,  /** if sender is willing to deposit nft now  */
                true    /**  if sender is seller */
            );
            router.takeOrderFor{value: PRICE}(forward, owner(), orderIndex);
            orderIndex++;
        }
        
    }

    function _calcDeliveryStart(uint id) internal view returns (uint) {
        return block.timestamp + deliveryMin + (deliveryMax - deliveryMin) * (maxSupply - id) / maxSupply;
    }

    function withdraw() external onlyOwner {
        require(
            status == Status.Finished,
            "XRC: invalid status for withdrawn."
        );
        require(!balanceWithdrawn, "XRC: balance has already been withdrawn.");

        uint256 balance = address(this).balance;

        uint256 v1 = 3.5 * 10**18;
        uint256 v2 = 0.5 * 10**18;
        uint256 v3 = balance - v1 - v2;

        balanceWithdrawn = true;

        (bool success1, ) = payable(0xFcda4EE4E98F3d25CB2F4e3C164deAF277372f35)
            .call{value: v1}("");
        (bool success2, ) = payable(0xb811EC5250796966f1400C8e30E5e8A2bC44a068)
            .call{value: v2}("");
        (bool success3, ) = payable(0xe9EAA95B03f40F13C5609b54e40C155e6f77f648)
            .call{value: v3}("");

        require(success1, "Transfer 1 failed.");
        require(success2, "Transfer 2 failed.");
        require(success3, "Transfer 3 failed.");
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    function setStatus(Status _status) external onlyOwner {
        status = _status;
        emit StatusChanged(_status);
    }

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
        emit SignerChanged(signer);
    }

    function setOwnersExplicit(uint256 quantity)
        external
        onlyOwner
    {
        _setOwnersExplicit(quantity);
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function getOwnershipData(uint256 tokenId)
        external
        view
        returns (TokenOwnership memory)
    {
        return ownershipOf(tokenId);
    }
}