// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../interface/IHogletFactory.sol";
import "../../interface/IForwardVault.sol";


contract BaseForwardUpgradeable is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    // cumulative fee
    uint256 public cfee;
    // ratio = value of per share in forward : per share in fVault
    uint256 public ratio;
    uint256 public ordersLength;

    // use factory rather than Ownable's modifier to save gas
    address public factory;
    // want can be erc20, erc721, erc1155
    address public want; 
    // margin can be erc20 or ether--address(0)
    address public margin;
    // forward vault for margin token
    address public fVault;
    // info of eth 
    address public eth;

    // forward contract status 
    bool public paused;

    enum State { inactive, active, filled, dead, delivery, expired, settled }

    struct Dealer {        
        address buyer;
        address seller;
        bool sellerDelivered;
        bool buyerDelivered;
        State state;

    }
    struct Order {
        uint256 buyerMargin;
        uint256 sellerMargin;
        uint256 deliveryPrice;
        // uint256 validTill;
        // uint256 deliverStart;
        // uint256 expireStart;

        // Compare with above, below types helps us save approx 90k gas
        // uint128 buyerMargin; // max > 1e36
        // uint128 sellerMargin; 
        // uint128 deliveryPrice;
        uint40 validTill;
        uint40 deliverStart;
        uint40 expireStart;
        
        // // above needs 2 slot
        // // below needs 43 bytes 128-42 = 86
        address buyer;
        address seller;
        bool buyerDelivered;
        bool sellerDelivered;
        State state;

    }

    // struct Order {
    //     uint256 buyerMargin;
    //     uint256 sellerMargin;
    //     uint256 deliveryPrice;
    //     uint64 validTill;
    //     uint64 deliverStart;
    // }


    // struct Order {
    //     uint256 buyerMargin;
    //     uint256 sellerMargin;
    //     uint256 deliveryPrice;
    //     uint256 validTill;
    //     uint256 deliverStart;         // timpstamp
    //     address buyer;
    //     address seller;
    //     OrderState state;
    //     bool buyerDelivered;
    //     bool sellerDelivered;
    // }

    

    // Order[] public orders;
    mapping(uint256 => Order) public orders;

    // event
    event CreateOrder(
        uint orderId
    );

    event TakeOrder(
        uint orderId
    );

    event Delivery(
        uint orderId
    );

    event Settle(
        uint orderId
    );


    constructor() {}

    function __BaseForward__init(
        address _want,
        address _margin
    ) public initializer {
        factory = msg.sender;
        IHogletFactory _factory = IHogletFactory(factory);
        require(_factory.ifMarginSupported(_margin), "!margin");
        want = _want;
        margin = _margin;
        ratio = 1e18;
    }
    
    function _onlyFactory() internal view {
        require(msg.sender == factory, "!factory");
    }

    function _onlyNotPaused() internal view {
        require(!paused, "paused");
    }
    
    function pause() external {
        _onlyFactory();
        paused = true;
    }

    function unpause() external {
        _onlyFactory();
        paused = false;
    }


    function _onlyNotProtectedTokens(address _token) internal virtual view {}

    function withdrawOther(address _token, address _to) external virtual {
        address feeCollector = IHogletFactory(factory).feeCollector();
        require(msg.sender == factory || msg.sender == feeCollector, "!auth");
        _onlyNotProtectedTokens(_token);

        if (_token == eth) {
            payable(_to).transfer(address(this).balance);
        } else {
            IERC20Upgradeable(_token).safeTransfer(_to, IERC20Upgradeable(_token).balanceOf(address(this)));
        }
    }

    function collectFee(address _to) external {
        address feeCollector = IHogletFactory(factory).feeCollector();
        require(msg.sender == factory || msg.sender == feeCollector, "!auth");
        _pushMargin(_to, cfee);
        cfee = 0;
    }


    function available() public view returns (uint256) {
        return IERC20Upgradeable(margin).balanceOf(address(this));
    }
    

    
    // function getBuyerAmountToDeliver(uint256 _orderId) external virtual view returns (uint256 price) {
    //     Order memory order = orders[_orderId];        
    //     if (!order.buyerDelivered) {
    //         (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
    //         uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
    //         price = buyerAmount.sub(order.buyerMargin);
    //     }
    // }


    function version() external virtual view returns (string memory) {
        return "v1.0";
    }
    
    function _createOrderFor(
        address _creator,
        uint _orderValidPeriod,
        uint _deliveryStart,
        uint _deliveryPeriod,
        uint _deliveryPrice, 
        uint _buyerMargin,
        uint _sellerMargin,
        bool _deposit,
        bool _isSeller
    ) internal virtual {
        // condition check for time params
        require(uint(_deliveryStart).add(_deliveryPeriod) < type(uint40).max && _getBlockTimestamp().add(_orderValidPeriod) < uint(_deliveryStart), "!time");
        require(_deliveryPrice < type(uint128).max && _buyerMargin < type(uint128).max && _sellerMargin < type(uint128).max, "exceed max");
        
        if (_deposit && !_isSeller) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            _pullMargin(_deliveryPrice.mul(fee.add(base)).div(base));
        } else {
            // take margin from msg.sender normally
            _pullMargin(_isSeller ? _sellerMargin : _buyerMargin);
        }

        uint index = ordersLength++;
        orders[index] = Order({
            buyerMargin: uint128(_buyerMargin),
            sellerMargin: uint128(_sellerMargin),
            deliveryPrice: uint128(_deliveryPrice),
            validTill: uint40(_getBlockTimestamp().add(_orderValidPeriod)),
            deliverStart: uint40(_deliveryStart),
            expireStart: uint40(uint(_deliveryStart).add(_deliveryPeriod)),
            buyer: _isSeller ? address(0) : _creator,
            sellerDelivered: _deposit && _isSeller,
            buyerDelivered: _deposit && !_isSeller,
            seller: _isSeller ? _creator : address(0),
            state: State.active
        });
        emit CreateOrder(index);
    
    }

    
    function takeOrderFor(address _taker, uint _orderId) external virtual {
        _onlyNotPaused();
        _takeOrderFor(_taker, _orderId);
    }

    function _takeOrderFor(address _taker, uint _orderId) internal virtual {
        // makes sure order exist and still active
        // require(_orderId < ordersLength, "!orderId"); // no need to check 
        require(checkOrderState(_orderId) == State.active, "!active");

        Order memory order = orders[_orderId];
        _pullMargin(order.seller == address(0) ? order.sellerMargin : order.buyerMargin);

        // change storage
        if (order.buyer == address(0)) {
            orders[_orderId].buyer = _taker;
        } else if (order.seller == address(0)) {
            orders[_orderId].seller = _taker;
        } else {
            revert("takeOrder bug");
        }
        orders[_orderId].state = State.filled;
        emit TakeOrder(_orderId);
        // 450495
    }

    function deliverFor(address _deliverer, uint256 _orderId) external virtual {
        _onlyNotPaused();
        Order memory order = orders[_orderId];
        require(checkOrderState(_orderId) == State.delivery, "!delivery");

        if (_deliverer == order.seller && !order.sellerDelivered) {
            // seller tends to deliver underlyingAssets[_orderId] amount of want tokens
            _pullUnderlyingAssetsToSelf(_orderId);
            orders[_orderId].sellerDelivered = true;
            emit Delivery(_orderId);
        } else if (_deliverer == order.buyer && !order.buyerDelivered) {
            // buyer tends to deliver tokens
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint buyerAmount = fee.add(base).mul(order.deliveryPrice).div(base);
            _pullMargin(buyerAmount.sub(order.buyerMargin));  
            orders[_orderId].buyerDelivered = true;
            emit Delivery(_orderId);
        } else {
            revert("deliver bug");
        }

        // soft settle means settle if necessary otherwise wait for the counterpart to deliver
        _settle(_orderId, false); 
    }

    function settle(uint256 _orderId) external virtual {
        _onlyNotPaused();
        require(checkOrderState(_orderId) == State.expired, "!expired");
        // challenge time has past, anyone can forcely settle this order
        _settle(_orderId, true);
    }

    function _settle(uint256 _orderId, bool _forceSettle) internal {
        Order memory order = orders[_orderId];
        (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
        
        // in case both sides delivered
        if (order.sellerDelivered && order.buyerDelivered) {
            // send buyer underlyingAssets[_orderId] amount of want tokens and seller margin
            _pushUnderingAssetsFromSelf(_orderId, order.buyer);
            uint bfee = uint(order.deliveryPrice).mul(fee).div(base);
            
            // send seller payout
            _pushMargin(order.seller, uint(order.sellerMargin).add(order.deliveryPrice).sub(bfee));
            cfee = cfee.add(bfee.mul(2));
            
            
            orders[_orderId].state = State.settled;
            emit Settle(_orderId);
            return; // must return here
        }
        if (_forceSettle) {
            if (!order.sellerDelivered) {
                // blame seller if he/she does not deliver nfts  
                uint sfee = uint(order.sellerMargin).mul(fee).div(base);
                cfee = cfee.add(sfee);
                _pushMargin(
                    order.buyer, 
                    uint(order.sellerMargin).sub(sfee)
                );
            } else if (!order.buyerDelivered) {
                // blame buyer
                uint bfee = fee.mul(order.buyerMargin).div(base);
                cfee = cfee.add(bfee);
                _pushMargin(
                    order.seller,
                    uint(order.buyerMargin).sub(bfee)
                );
                // return underying assets (underlyingAssets[_orderId] amount of want) to seller
                _pushUnderingAssetsFromSelf(_orderId, order.seller);
            }
            orders[_orderId].state = State.settled;
            emit Settle(_orderId);
        }
        
    }

    /**
     * @dev return order state based on orderId
     * @param _orderId order index whose state to be checked.
     * @return 
            0--inactive: order not exist
            1--active: order has been successfully created 
            2--filled: order has been filled, 
            3--dead: order not filled till validTill timestamp, 
            4--delivery: order can be delivered, being challenged between buyer and seller,
            5--expired: order is expired, yet not settled
            6--settled: order has been successfully settled
     */
    function checkOrderState(uint256 _orderId) public virtual view returns (State) {
        Order memory order = orders[_orderId];

        if (order.validTill == 0 ) return State.inactive;
        uint time = _getBlockTimestamp();
        if (time <= order.validTill) {
            if (order.state != State.filled) return State.active;
            return State.filled;
        }
        
        if (time <= order.deliverStart) {
            if (order.state != State.filled) return State.dead;
            return State.filled;
        }
        if (time <= order.expireStart) {
            if (order.state != State.settled) return State.delivery;
            return State.settled;
        }
        if (order.state != State.settled) return State.expired;
        return State.settled;
    }

    function _pullUnderlyingAssetsToSelf(uint256 _orderId) internal virtual {}
    function _pushUnderingAssetsFromSelf(uint256 _orderId, address _to) internal virtual {}

    function _pullMargin(uint _amount) internal virtual {
        _pullTokensToSelf(margin, _amount);
        
    }

    function _pushMargin(address _to, uint _amount) internal virtual  {
        _pushTokensFromSelf(margin, _to, _amount);

    }
    
    function _pushTokensFromSelf(address _token, address _to, uint _amount) internal virtual {
        IERC20Upgradeable(_token).safeTransfer(_to, _amount);
    }
    
    function _pullTokensToSelf(address _token, uint _amount) internal virtual {
        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function _getBlockTimestamp() public view returns (uint) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }

    
}