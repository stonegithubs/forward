// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../../interface/IHogletFactory.sol";
import "../../interface/IForwardVault.sol";


contract BaseForwardUpgradeable is ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;


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
    // cumulative fee
    uint256 public cfee;
    // ratio = value of per share in forward : per share in fVault
    uint256 public ratio;
    
    // forward contract status 
    bool public paused;

    enum OrderState { inactive, active, filled, dead, delivery, expired, settled }

    struct Order {
        uint256 buyerMargin;
        uint256 sellerMargin;
        uint256 buyerShare;
        uint256 sellerShare;
        uint256 deliveryPrice;
        uint256 validTill;
        uint256 deliverStart;         // timpstamp
        address buyer;
        address seller;
        OrderState state;
        bool buyerDelivered;
        bool sellerDelivered;
        address[] takerWhiteList;
    }
    Order[] public orders;

    // event
    event CreateOrder(
        uint orderId,
        address maker
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


    constructor() {}

    function __BaseForward__init(
        address _want,
        address _margin
    ) public initializer {
        __ReentrancyGuard_init();
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

    function setForwardVault(address _fVault) external virtual {
        _onlyFactory();

        if (fVault == address(0) && _fVault != address(0)) {
            
            // enable vault first time
            address fvwant = IForwardVault(_fVault).want();
            require(fvwant == margin, "!want");
            // approve margin tokens for new forward vault
            IERC20Upgradeable(fvwant).safeApprove(_fVault, 0);
            IERC20Upgradeable(fvwant).safeApprove(_fVault, type(uint256).max);

        } else if (fVault != address(0) && _fVault != address(0)) {
            
            // change vault from one to another one
            address fvwant = IForwardVault(_fVault).want();
            require(fvwant == margin, "!want");

            uint256 oldShares = IForwardVault(fVault).balanceOf(address(this));
            uint256 tokens = oldShares > 0 ? IForwardVault(fVault).withdraw(oldShares) : 0;

            IERC20Upgradeable(fvwant).safeApprove(fVault, 0);
            
            IERC20Upgradeable(fvwant).safeApprove(_fVault, 0);
            IERC20Upgradeable(fvwant).safeApprove(_fVault, type(uint256).max);

            // ratio = oldShares > 0 ? IForwardVault(_fVault).deposit(tokens).mul(1e18).div(oldShares) : ratio;
            if (oldShares > 0) {
                uint newShares = IForwardVault(_fVault).deposit(tokens);
                ratio = newShares.mul(1e18).div(oldShares);
            }

        } else if (fVault != address(0) && _fVault == address(0)) {
            
            // disable vault finally
            uint256 oldShares = IForwardVault(fVault).balanceOf(address(this));
            uint256 tokens = oldShares > 0 ? IForwardVault(fVault).withdraw(oldShares) : 0;
            
            // close approval
            IERC20Upgradeable(IForwardVault(fVault).want()).safeApprove(fVault, 0);
            // remember the ratio
            if (oldShares > 0) {
                ratio = tokens.mul(1e18).div(oldShares);
            }
        } else {
            revert("nonsense");
        }

        fVault = _fVault;

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


    function balance() public view returns (uint256) {
        return available().add(balanceSavingsInFVault());
    }

    function available() public view returns (uint256) {
        return IERC20Upgradeable(margin).balanceOf(address(this));
    }
    
    function balanceSavingsInFVault() public view returns (uint256) {
        return fVault == address(0) ? 0 : IForwardVault(fVault).balanceOf(address(this)).mul(
                                                    IForwardVault(fVault).getPricePerFullShare()
                                                    ).div(1e18);
    }

    function getPricePerFullShare() public view returns (uint256) {
        return fVault == address(0) ? 
            ratio : 
            ratio.mul(IForwardVault(fVault).getPricePerFullShare()).div(1e18);
    }

    
    function getBuyerAmountToDeliver(uint256 _orderId) external virtual view returns (uint256 price) {
        Order memory order = orders[_orderId];        
        if (!order.buyerDelivered) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            price = buyerAmount.sub(order.buyerShare.mul(getPricePerFullShare()).div(1e18));
        }
    }


    function version() external virtual view returns (string memory) {
        return "v1.0";
    }
    
    function _createOrderFor(
        address _creator,
        uint _nowToDeliverPeriod,
        uint256 _deliveryPrice, 
        uint256 _buyerMargin,
        uint256 _sellerMargin,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) internal virtual {
        uint _shares;
        if (_deposit && !_isSeller) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            _shares = _pullMargin(_deliveryPrice.mul(fee.add(base)).div(base), true);
        } else {
            // take margin from msg.sender normally
            _shares = _pullMargin(_isSeller ? _sellerMargin : _buyerMargin, true);
        }

        (uint _orderValidPeriod, ) = IHogletFactory(factory).getPeriods();
        orders.push(
            Order({
                buyer: _isSeller ? address(0) : _creator,
                buyerMargin: _buyerMargin,
                buyerShare: _isSeller ? 0 : _shares,
                buyerDelivered: _deposit && !_isSeller,
                seller: _isSeller ? _creator : address(0),
                sellerMargin: _sellerMargin,
                sellerShare: _isSeller ? _shares : 0,
                sellerDelivered: _deposit && _isSeller,
                deliveryPrice: _deliveryPrice,
                validTill: _getBlockTimestamp().add(_orderValidPeriod),
                deliverStart: _getBlockTimestamp().add(_nowToDeliverPeriod),
                state: OrderState.active,
                takerWhiteList: new address[](0)
            })
        );

        uint curOrderIndex = orders.length - 1;
        
        if (_takerWhiteList.length > 0) {
            for (uint i = 0; i < _takerWhiteList.length; i++) {
                orders[curOrderIndex].takerWhiteList.push(_takerWhiteList[i]);
            }
        }
        emit CreateOrder(curOrderIndex, _creator);
    
    }

    
    function takeOrderFor(address _taker, uint _orderId) external virtual nonReentrant {
        _onlyNotPaused();
        _takeOrderFor(_taker, _orderId);
    }

    function _takeOrderFor(address _taker, uint _orderId) internal virtual {
        // check condition
        require(_orderId < orders.length, "!orderId");
        Order memory order = orders[_orderId];
        require(_getBlockTimestamp() <= order.validTill && order.state == OrderState.active, "!valid & !active"); // okay redundant check
        
        if (order.takerWhiteList.length > 0) {
            require(_withinList(_taker, order.takerWhiteList), "!whitelist");
        }

        uint takerMargin = orders[_orderId].seller == address(0) ? orders[_orderId].sellerMargin : orders[_orderId].buyerMargin;
        uint shares = _pullMargin(takerMargin, true);

        // change storage
        if (orders[_orderId].buyer == address(0)) {
            orders[_orderId].buyer = _taker;
            orders[_orderId].buyerShare = shares;
        } else if (orders[_orderId].seller == address(0)) {
            orders[_orderId].seller = _taker;
            orders[_orderId].sellerShare = shares;
        } else {
            revert("bug");
        }
        orders[_orderId].state = OrderState.filled;
        emit TakeOrder(_orderId, _taker, takerMargin);
    }
    
    function _pullUnderlyingAssetsToSelf(uint256 _orderId) internal virtual {}
    function _pushUnderingAssetsFromSelf(uint256 _orderId, address _to) internal virtual {}

    function deliverFor(address _deliverer, uint256 _orderId) external virtual nonReentrant {
        _onlyNotPaused();
        Order memory order = orders[_orderId];
        require(checkOrderState(_orderId) == OrderState.delivery, "!delivery");
        require(_deliverer == order.seller || _deliverer == order.buyer, "only seller & buyer");

        if (_deliverer == order.seller && !order.sellerDelivered) {
            // seller tends to deliver underlyingAssets[_orderId] amount of want tokens
            _pullUnderlyingAssetsToSelf(_orderId);
            orders[_orderId].sellerDelivered = true;
            emit Delivery(_orderId, _deliverer);
        }
        if (_deliverer == order.buyer && !order.buyerDelivered) {
            // buyer tends to deliver tokens
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            _pullMargin(
                buyerAmount.sub(
                    order.buyerShare.mul(getPricePerFullShare()).div(1e18)
                ), 
                false /* here we do not farm delivered tokens since they just stay in contract for challenge period at most */
            );  
            orders[_orderId].buyerDelivered = true;
            emit Delivery(_orderId, _deliverer);
        }

        // soft settle means settle if necessary otherwise wait for the counterpart to deliver
        _settle(_orderId, false); 
    }

    function settle(uint256 _orderId) external virtual nonReentrant{
        _onlyNotPaused();
        require(checkOrderState(_orderId) == OrderState.expired, "!expired");
        // challenge time has past, anyone can forcely settle this order 
        _settle(_orderId, true);
    }

    function _settle(uint256 _orderId, bool _forceSettle) internal {
        (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
        
        Order memory order = orders[_orderId];
        // in case both sides delivered
        if (order.sellerDelivered && order.buyerDelivered) {
            // send buyer underlyingAssets[_orderId] amount of want tokens and seller margin
            _pushUnderingAssetsFromSelf(_orderId, order.buyer);
            uint bfee = order.deliveryPrice.mul(fee).div(base);
            // carefully check if there is margin left for buyer in case buyer depositted both margin and deliveryPrice at the very first
            uint bsa /*Buyer Share token Amount*/ = order.buyerShare.mul(getPricePerFullShare()).div(1e18);
            // should send extra farmming profit to buyer
            if (bsa > order.deliveryPrice.add(bfee)) {
                _pushMargin(order.buyer, bsa.sub(order.deliveryPrice).sub(bfee));
            }
            
            // send seller payout
            uint sellerAmount = order.sellerShare.mul(getPricePerFullShare()).div(1e18).add(order.deliveryPrice).sub(bfee);
            _pushMargin(order.seller, sellerAmount);
            cfee = cfee.add(bfee.mul(2));
            
            
            orders[_orderId].state = OrderState.settled;
            emit Settle(_orderId);
            return; // must return here
        }
        if (_forceSettle) {
            if (!order.sellerDelivered) {
                // blame seller if he/she does not deliver nfts  
                uint sfee = order.sellerMargin.mul(fee).div(base);
                cfee = cfee.add(sfee);
                _pushMargin(
                    order.buyer, 
                    /* here we send both buyer and seller's margin to buyer except seller's op fee */
                    order.buyerShare.add(order.sellerShare).mul(getPricePerFullShare()).div(1e18).sub(sfee)
                );
            } else if (!order.buyerDelivered) {
                // blame buyer
                uint bfee = order.buyerMargin.mul(fee).div(base);
                cfee = cfee.add(bfee);
                _pushMargin(
                    order.seller,
                    order.sellerShare.add(order.buyerShare).mul(getPricePerFullShare()).div(1e18).sub(bfee)
                );
                // return underying assets (underlyingAssets[_orderId] amount of want) to seller
                _pushUnderingAssetsFromSelf(_orderId, order.seller);
            }
            orders[_orderId].state = OrderState.settled;
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
    function checkOrderState(uint256 _orderId) public virtual view returns (OrderState) {
        Order memory order = orders[_orderId];
        if (order.validTill == 0 ) return OrderState.inactive;
        uint time = _getBlockTimestamp();
        if (time <= order.validTill) return OrderState.active;
        if (order.buyer == address(0) || order.seller == address(0)) return OrderState.dead;
        if (time <= order.deliverStart) return OrderState.filled;
        (, uint _deliveryPeriod ) = IHogletFactory(factory).getPeriods();
        if (time <= order.deliverStart.add(_deliveryPeriod)) return OrderState.delivery;
        if (order.state != OrderState.settled) return OrderState.expired;
        return OrderState.settled;
    }

    function ordersLength() external virtual view returns (uint) {
        return orders.length;
    }

    
    function _pullMargin(uint _amount, bool _farm) internal virtual returns (uint shares) {
        
        _pullTokensToSelf(margin, _amount);
        shares = _farm && fVault != address(0) ? 
                    IForwardVault(fVault).deposit(_amount).mul(1e18).div(ratio) /* current line equals above line */
                    :
                    _amount.mul(1e18).div(getPricePerFullShare());
    }

    function _pullTokensToSelf(address _token, uint _amount) internal virtual {
        uint mtOld = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint mtNew = IERC20Upgradeable(_token).balanceOf(address(this));
        require(mtNew.sub(mtOld) == _amount, "!support taxed token");
    }

    function _pushMargin(address _to, uint _amount) internal virtual  {
        // check if balance not enough, if not, withdraw from vault
        uint ava = available();
        if (ava < _amount && fVault != address(0)) {
            IForwardVault(fVault).withdraw(_amount.sub(ava));
        }
        ava = available();
        if (_amount > ava) {
            _amount = ava;
        }
        
        _pushTokensFromSelf(margin, _to, _amount);

    }
    
    function _pushTokensFromSelf(address _token, address _to, uint _amount) internal virtual {
        IERC20Upgradeable(_token).safeTransfer(_to, _amount);
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