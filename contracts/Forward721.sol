pragma solidity ^0.8.0;


// ERC721
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./interface/IHedgehogFactory.sol";

contract Forward721 is OwnableUpgradeable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint;

    address public nftAddr;
    address public liquidationAsset;

    enum OrderState { active, dead, fill, challenge, settle }
    struct Order {
        address maker;
        uint makerMargin;
        uint256[] tokenIds;
        uint validTill;
        uint deliveryPrice;
        uint deliveryTime;
        uint challengeTime;
        address[] takerWhiteList;
        OrderState state;

        address taker;
        uint takerMargin;

        bool makerDelivery;
        bool takerDelivery;
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
        address[] takerWhiteList
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

    function initialize(
        address _nftAddr,
        uint _poolType,
        address _liquidationAsset
        
    ) public initializer {
        // init ownership
        __Ownable_init();

        
        // check conditions
        IHedgehogFactory factory = IHedgehogFactory(owner());
        require(_tokenType == factory.ERC721_POOL(), "!721");
        require(factory.ifEnabledCoin(liquidationAsset), "liquidation asset not enabled");

        // check parameters
        nftAddr = _nftAddr;
        liquidationAsset = _liquidationAsset;
    }

    function createOrder(
        uint256[] memory tokenIds, 
        uint orderValidPeriod, 
        uint deliveryPrice, 
        uint deliveryTime,
        uint challengePeriod,
        address[] takerWhiteList,
        bool deposit
    ) external payable {
        address maker = msg.sender;

        // check if maker wants to deposit tokenId nft directly
        if (deposit) {
            _multiDeposit721(tokenIds);
        }


        // get margin ratio from factory
        (uint mr, , uint base) = IHedgehogFactory(owner()).getMarginRatios();
        // take margin from maker
        uint makerMargin = deliveryPrice.mul(mr).div(base);
        _takeMargin(maker, makerMargin);

        // create order
        uint time = _getBlockTimestamp();
        orders.push(
            Order({
                maker: maker,
                makerMargin: makerMargin,
                validTill: time + orderValidPeriod,
                deliveryPrice: deliveryPrice,
                deliveryTime: deliveryTime,
                chanllengeTime: deliveryTime + challengePeriod,
                state: OrderState.active,
                makerDelivery: deposit
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
        
        emit CreateOrder(orders.length - 1, maker, tokenIds, validTill, deliveryPrice, deliveryTime, deliveryTime + challengePeriod, takerWhiteList);
    }


    function takeOrder(uint orderId) external payable {
        address taker = msg.sender;
        // check condition
        require(orderId < orders.length, "!orderId");
        Orders memory order = orders[orderId];
        require(_getBlockTimestamp() <= validTill && order.state == OrderState.active, "!valid & !active"); // okay redundant check
        
        if (order.takerWhiteList.length > 0) {
            require(_withinList(taker, order.takerWhiteList), "!whitelist");
        }

        (, uint tr, uint base) = IHedgehogFactory(owner()).getMarginRatios();
        uint takerMargin = order.deliveryPrice.mul(tr).div(base);
        _takeMargin(maker, takerMargin);

        // change storage
        orders[orderId].taker = taker;
        orders[orderId].takerMargin = takerMargin;
        orders[orderId].state = OrderState.fill;
        emit TakeOrder(orderId, taker, takerMargin);
    }
    
    /**
    * @dev only maker or taker from orderId's order can invoke this method during challenge period
    * @param orderId
     */
    
    function delivery(uint256 orderId) external payable {
        Orders memory order = orders[orderId];
        require(checkOrderState(orderId) == uint(OrderState.challenge), "!challenge");
        address sender = msg.sender;
        require(sender == order.maker || sender == order.taker, "only maker & sender");

        if (sender == order.maker && !order.makerDelivery) {
            // maker tends to deliver nfts
            _multiDeposit721(order.tokenIds);
            orders[orderId].makerDelivery = true;
            emit Delivery(orderId, sender);
        }
        if (sender == order.taker) {
            // taker tends to deliver tokens
            _takeMargin(sender, order.deliveryPrice.sub(takerMargin));
            orders[orderId].takerMargin = order.deliveryPrice;
            orders[orderId].takerDelivery = true;
            emit Delivery(orderId, sender);
        }

        _settle(orderId, false);

    }

    /**
    * @dev anybody can invoke this method to end orderId
    * @param orderId
     */
    function settle(uint256 orderId) external {

        require(checkOrderState(orderId) == 6, "! force settle");
        _settle(orderId, true);
    }


    function _settle(uint256 orderId, bool forceSettle) internal {
        Orders memory order = orders[orderId];
        if (order.makerDelivery && order.takerDelivery) {
            // send taker nfts and maker tokens

            orders[orderId].state = OrderState.settle;
            emit Settle(orderId);
            return; // must return here
        }

        if (forceSettle) {
            if (!order.makerDelivery) {
                // blame maker if he/she does not deliver nfts  

            } else {
                // blame taker 

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
            4: order has been successfully settled
            5: not exist
            6: challenge ended, yet not settled
     */
    function checkOrderState(uint orderId) public view returns (uint) {
        Orders memory order = orders[orderId];
        if (order.validTill == 0 ) return 5;
        uint time = _getBlockTimestamp();
        if (time <= order.validTill) return OrderState.active;
        if (order.taker == address(0)) return OrderState.dead;
        if (time <= order.deliveryTime) return OrderState.fill;
        if (time <= order.challengeTime) return OrderState.challenge;
        if (order.state == OrderState.challenge) return 6;
        return OrderState.settle;
    }

    function _takeMargin(address usr, uint amount) internal payable {
        if (liquidationAsset == address(0)) {
            require(msg.value >= amount, "!margin");
        } else {
            uint laOld = IERC20Upgradeable(liquidationAsset).balanceOf(address(this));
            IERC20Upgradeable(liquidationAsset).safeTransferFrom(usr, address(this), amount);
            uint laNew = IERC20Upgradeable(liquidationAsset).balanceOf(address(this));
            require(laNew.sub(laOld) == amount, "!support taxed token");
        }
    }

    function _multiDeposit721(uint256[] memory tokenIds) internal {
        uint oldBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        for (uint i = 0; i < tokenIds.length; i++) {
            _deposit721(tokenIds[i]);
        }
        uint newBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        require(newBal.sub(oldBal) == tokenIds.length, "redundant Ids");
    }

    function _deposit721(uint256 tokenId) internal {
        IERC721Upgradeable(nftAddr).transferFrom(
            msg.sender,
            address(this),
            tokenId
        );
        // check transfer succeeds
        require(IERC721Upgradeable(nftAddr).ownerOf(tokenId) == address(this), "721 transfer fail");
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
}