// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// ERC721
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./interface/IHedgehogFactory.sol";
import "./DummyWETH.sol";
import "./interface/IWETH.sol";
contract Forward721Upgradeable is OwnableUpgradeable, ERC721HolderUpgradeable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint;

    address public nftAddr;
    address public marginToken;
    uint public cfee;

    IWETH public weth; 

    enum OrderState { active, dead, fill, challenge, unsettle, settle }
    //TODO: change maker/taker to buyer/seller
    struct Order {
        address buyer;
        uint buyerMargin;
        address seller;
        uint sellerMargin;

        uint256[] tokenIds;
        uint validTill;
        uint deliveryPrice;
        uint deliveryTime;
        uint challengeTime;
        address[] takerWhiteList;
        OrderState state;


        bool sellerDelivery;
        bool buyerDelivery;
    }

    Order[] public orders;

    event CreateOrder(
        uint orderId,
        address maker,
        uint256[] tokenIds,
        uint validTill,
        uint deliveryPrice,
        uint deliveryTime,
        uint challengeTill,
        address[] takerWhiteList,
        bool isSeller
    );
    event TakeOrder(
        uint orderId,
        address taker,
        uint takerMargin
    );

    event Delivery(
        uint orderId,
        address sender
    );

    event Settle(
        uint orderId
    );

    constructor() {
        transferOwnership(address(0xdead));

    }

    function initialize(
        address _nftAddr,
        uint _poolType,
        address _marginToken
    ) public initializer {
        // init ownership
        __Ownable_init();

        
        // check conditions
        IHedgehogFactory factory = IHedgehogFactory(owner());
        require(_poolType == 721, "!721");
        require(factory.ifTokenSupported(marginToken), "margin token not supported");

        // check parameters
        nftAddr = _nftAddr;
        marginToken = _marginToken;

        weth = IWETH(DummyWETH.dummyWeth());
    }

    function createOrder(
        uint256[] memory tokenIds, 
        uint256 orderValidPeriod, 
        uint256 deliveryPrice, 
        uint256 deliveryTime,
        uint256 challengePeriod,
        address[] memory takerWhiteList,
        bool deposit,
        uint256 buyerMargin,
        uint256 sellerMargin,
        bool isSeller
    ) external payable {
        address maker = msg.sender;

        // check if maker wants to deposit tokenId nft directly
        if (deposit && isSeller) {
            _multiDeposit721(tokenIds);
        }

        // check if maker wants to deposit tokens directly 
        if (deposit && !isSeller) {
            (uint fee, uint base) = IHedgehogFactory(owner()).getOperationFee();
            uint256 p = deliveryPrice.mul(fee.add(base)).div(base);
            _pullToken(maker, p);
        } else {
            // take margin from maker normally
            _pullToken(maker, isSeller ? sellerMargin : buyerMargin);
        }


        // create order
        orders.push(
            Order({
                buyer: isSeller ? address(0) : maker,
                buyerMargin: buyerMargin,
                seller: isSeller ? maker : address(0),
                sellerMargin: sellerMargin,
                tokenIds: new uint256[](0),
                validTill: _getBlockTimestamp() + orderValidPeriod,
                deliveryPrice: deliveryPrice,
                deliveryTime: deliveryTime,
                challengeTime: deliveryTime + challengePeriod,
                takerWhiteList: new address[](0),
                state: OrderState.active,
                sellerDelivery: deposit && isSeller,
                buyerDelivery: deposit && !isSeller
            })
        );
        
        uint curOrderIndex = orders.length - 1;
        for (uint i = 0; i < tokenIds.length; i++) {
            orders[curOrderIndex].tokenIds.push(tokenIds[i]);
        }
        
        if (takerWhiteList.length > 0) {
            for (uint i = 0; i < takerWhiteList.length; i++) {
                orders[curOrderIndex].takerWhiteList.push(takerWhiteList[i]);
            }
        }
        
        emit CreateOrder(orders.length - 1, maker, tokenIds, orders[curOrderIndex].validTill, orders[curOrderIndex].deliveryPrice, orders[curOrderIndex].deliveryTime, orders[curOrderIndex].challengeTime, takerWhiteList, isSeller);
    }


    function takeOrder(uint orderId) external payable {
        address taker = msg.sender;
        // check condition
        require(orderId < orders.length, "!orderId");
        Order memory order = orders[orderId];
        require(_getBlockTimestamp() <= order.validTill && order.state == OrderState.active, "!valid & !active"); // okay redundant check
        
        if (order.takerWhiteList.length > 0) {
            require(_withinList(taker, order.takerWhiteList), "!whitelist");
        }

        uint takerMargin = orders[orderId].seller == address(0) ? orders[orderId].sellerMargin : orders[orderId].buyerMargin;
        _pullToken(taker, takerMargin);

        // change storage
        if (orders[orderId].buyer == address(0)) {
            orders[orderId].buyer = taker;
        } else {
            orders[orderId].seller = taker;
        }
        orders[orderId].state = OrderState.fill;
        emit TakeOrder(orderId, taker, takerMargin);
    }
    
    /**
    * @dev only maker or taker from orderId's order can invoke this method during challenge period
    * @param orderId the order msg.sender wants to deliver
     */
    
    function deliver(uint256 orderId) external payable {
        Order memory order = orders[orderId];
        require(checkOrderState(orderId) == uint(OrderState.challenge), "!challenge");
        address sender = msg.sender;
        require(sender == order.seller || sender == order.buyer, "only seller & buyer");

        if (sender == order.seller && !order.sellerDelivery) {
            // seller tends to deliver nfts
            _multiDeposit721(order.tokenIds);
            orders[orderId].sellerDelivery = true;
            emit Delivery(orderId, sender);
        }
        if (sender == order.buyer && !order.buyerDelivery) {
            // buyer tends to deliver tokens
            (uint fee, uint base) = IHedgehogFactory(owner()).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            _pullToken(sender, buyerAmount.sub(order.buyerMargin));
            orders[orderId].buyerDelivery = true;
            emit Delivery(orderId, sender);
        }

        _settle(orderId, false);

    }

    /**
    * @dev anybody can invoke this method to end orderId
    * @param orderId the order msg.sender wants to settle at the final stage
     */
    function settle(uint256 orderId) external {

        require(checkOrderState(orderId) == uint(OrderState.unsettle), "! force settle");
        _settle(orderId, true);
    }


    function _settle(uint256 orderId, bool forceSettle) internal {
        (uint fee, uint base) = IHedgehogFactory(owner()).getOperationFee();
        
        Order memory order = orders[orderId];
        if (order.sellerDelivery && order.buyerDelivery) {
            // send buyer nfts and seller margin
            _multiWithdraw721(order.tokenIds, order.buyer);
            // no margin for buyer
            uint bfee = order.deliveryPrice.mul(fee).div(base);
            // send seller payout
            uint sellerAmount = order.sellerMargin.add(order.deliveryPrice).sub(bfee);
            _pushToken(order.seller, sellerAmount);
            cfee = cfee.add(bfee.mul(2));

            orders[orderId].state = OrderState.settle;
            emit Settle(orderId);
            return; // must return here
        }
        if (forceSettle) {
            if (!order.sellerDelivery) {
                // blame seller if he/she does not deliver nfts  
                uint sfee = order.sellerMargin.mul(fee).div(base);
                cfee = cfee.add(sfee);
                _pushToken(order.buyer, order.sellerMargin.sub(sfee));
            } else {
                // blame buyer
                uint bfee = order.buyerMargin.mul(fee).div(base);
                cfee = cfee.add(bfee);
                _pushToken(order.seller, order.buyerMargin.sub(bfee));

            }
            orders[orderId].state = OrderState.settle;
            emit Settle(orderId);
        }

    }
    
    /**
     * @dev return order state based on orderId
     * @param orderId order index whose state to be checked.
     * @return 
            0: active, 
            1: order is dead, 
            2: order is filled, 
            3: order is being challenged between maker and taker,
            4: challenge ended, yet not settled
            5: order has been successfully settled
            6: not exist
     */
    function checkOrderState(uint orderId) public view returns (uint) {
        Order memory order = orders[orderId];
        if (order.validTill == 0 ) return 6;
        uint time = _getBlockTimestamp();
        if (time <= order.validTill) return uint(OrderState.active);
        if (order.buyer == address(0) || order.seller == address(0)) return uint(OrderState.dead);
        if (time <= order.deliveryTime) return uint(OrderState.fill);
        if (time <= order.challengeTime) return uint(OrderState.challenge);
        if (order.state != OrderState.settle) return uint(OrderState.unsettle);
        return uint(OrderState.settle);
    }

    function collectFee() external {
        address feeCollector = IHedgehogFactory(owner()).feeCollector();
        require(feeCollector != address(0), "!feeCollector");
        _pullToken(feeCollector, cfee);
        cfee = 0;
    }

    function _pullToken(address usr, uint amount) internal {
        if (marginToken == address(0)) {
            require(msg.value >= amount, "!margin");
        } else {
            uint laOld = IERC20Upgradeable(marginToken).balanceOf(address(this));
            IERC20Upgradeable(marginToken).safeTransferFrom(usr, address(this), amount);
            uint laNew = IERC20Upgradeable(marginToken).balanceOf(address(this));
            require(laNew.sub(laOld) == amount, "!support taxed token");
        }
        // TODO: directly deposit token to our hedgehog forward vault
        
    }

    function _pushToken(address usr, uint amount) internal {
        if (marginToken == address(0)) {
            payable(usr).transfer(amount);
        } else {
            uint laOld = IERC20Upgradeable(marginToken).balanceOf(address(this));
            IERC20Upgradeable(marginToken).safeTransfer(usr, amount);
            uint laNew = IERC20Upgradeable(marginToken).balanceOf(address(this));
            require(laOld.sub(laNew) == amount, "!support taxed token");
        }
    }

    function _multiDeposit721(uint256[] memory tokenIds) internal {
        // uint oldBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        for (uint i = 0; i < tokenIds.length; i++) {
            _deposit721(tokenIds[i]);
        }
        // uint newBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        // require(newBal.sub(oldBal) == tokenIds.length, "redundant Ids");
    }

    function _deposit721(uint256 tokenId) internal {

        _pullERC721(nftAddr, tokenId);
        
    }

    function _multiWithdraw721(uint256[] memory tokenIds, address to) internal {
        // uint oldBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        for (uint i = 0; i < tokenIds.length; i++) {
            _withdraw721(tokenIds[i], to);
        }
        // uint newBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        // require(oldBal.sub(newBal).div(10**) == tokenIds.length, "redundant Ids");
    }

    function _withdraw721(uint256 tokenId, address to) internal {
        _pushERC721(nftAddr, to, tokenId);
    }

    function _withinList(address addr, address[] memory list) internal pure returns (bool) {
        for (uint i = 0; i < list.length; i++) {
            if (addr == list[i]) {
                return true;
            }
        }
        return false;
    }

    
    function _getBlockTimestamp() internal view returns (uint) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }

    // Non-standard ERC721 projects:  https://docs.niftex.org/general/supported-nfts
    // implementation refers to: https://github.com/NFTX-project/nftx-protocol-v2/blob/master/contracts/solidity/NFTXVaultUpgradeable.sol#L444
    // TODO: improve implemention to include more non-standard ERC721 impl and change standard to safe-(invoke) way
    function _pushERC721(address assetAddr, address to, uint256 tokenId) internal virtual {
        address kitties = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
        address punks = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
        bytes memory data;
        if (assetAddr == kitties) {
            // Changed in v1.0.4.
            data = abi.encodeWithSignature("transfer(address,uint256)", to, tokenId);
        } else if (assetAddr == punks) {
            // CryptoPunks.
            data = abi.encodeWithSignature("transferPunk(address,uint256)", to, tokenId);
        } else {
            // Default.
            data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(this), to, tokenId);
        }
        (bool success,) = address(assetAddr).call(data);
        require(success);
    }

    function _pullERC721(address assetAddr, uint256 tokenId) internal virtual {
        address kitties = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
        address punks = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
        bytes memory data;
        if (assetAddr == kitties) {
            // Cryptokitties.
            data = abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), tokenId);
        } else if (assetAddr == punks) {
            // CryptoPunks.
            // Fix here for frontrun attack. Added in v1.0.2.
            bytes memory punkIndexToAddress = abi.encodeWithSignature("punkIndexToAddress(uint256)", tokenId);
            (bool checkSuccess, bytes memory result) = address(assetAddr).staticcall(punkIndexToAddress);
            (address owner) = abi.decode(result, (address));
            require(checkSuccess && owner == msg.sender, "Not the owner");
            data = abi.encodeWithSignature("buyPunk(uint256)", tokenId);
        } else {
            // Default.
            data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", msg.sender, address(this), tokenId);
        }
        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success, string(resultData));
    }

    

}