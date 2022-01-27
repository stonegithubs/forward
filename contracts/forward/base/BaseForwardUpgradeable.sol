// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../interface/IHogletFactory.sol";
import "../../interface/IForwardVault.sol";


contract BaseForwardUpgradeable is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint;


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
    uint public cfee;
    // ratio = value of per share in forward : per share in fVault
    uint public ratio;
    // record orders.length
    uint public ordersLength;
    
    // forward contract status 
    bool public paused;

    enum State { inactive, active, filled, dead, delivery, expired, settled, canceled}

    struct Order {
        // using uint128 can help save 50k gas
        uint128 buyerMargin;
        uint128 sellerMargin;
        uint128 buyerShare;
        uint128 sellerShare;
        uint128 deliveryPrice;
        uint40 validTill;
        uint40 deliverStart;         // timpstamp
        uint40 expireStart;
        address buyer;
        address seller;
        bool buyerDelivered;
        bool sellerDelivered;
        State state;
        address[] takerWhiteList;
    }
    // here we use map rather than array to save gas
    mapping(uint => Order) public orders;


    // event
    event CreateOrder(uint orderId, address maker);
    event TakeOrder(uint orderId, address taker);
    event Delivery(uint orderId, address deliver);
    event Settle(uint orderId);
    event CancelOrder(uint orderId);

    // constructor() {}

    
    /***************** initializer begin **********************/
    function __BaseForward__init(
        address _want,
        address _margin
    ) public onlyInitializing {
        factory = msg.sender;
        IHogletFactory _factory = IHogletFactory(factory);
        require(_factory.ifMarginSupported(_margin), "!margin");
        want = _want;
        margin = _margin;
        ratio = 1e18;
    }
    /***************** initializer end **********************/


    /***************** condition check begin **********************/
    function _onlyFactory() internal view {
        require(msg.sender == factory, "!factory");
    }

    function _onlyNotPaused() internal view {
        require(!paused, "paused");
    }

    function _onlyNotProtectedTokens(address _token) internal virtual view {}

    /***************** condition check end **********************/
    

    /***************** authed function begin **********************/
    function pause() external {
        _onlyFactory();
        paused = true;
    }

    function unpause() external {
        _onlyFactory();
        paused = false;
    }

    function collectFee(address _to) external {
        address feeCollector = IHogletFactory(factory).feeCollector();
        require(msg.sender == factory || msg.sender == feeCollector, "!auth");
        _pushMargin(_to, cfee);
        cfee = 0;
    }

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

    function setForwardVault(address _fVault) external virtual {
        _onlyFactory();

        if (fVault == address(0) && _fVault != address(0)) {
            
            // enable vault first time
            address fvwant = IForwardVault(_fVault).want();
            require(fvwant == margin, "!want");
            // approve margin tokens for new forward vault
            IERC20Upgradeable(fvwant).safeApprove(_fVault, 0);
            IERC20Upgradeable(fvwant).safeApprove(_fVault, type(uint).max);

        } else if (fVault != address(0) && _fVault != address(0)) {
            
            // change vault from one to another one
            address fvwant = IForwardVault(_fVault).want();
            require(fvwant == margin, "!want");

            uint oldShares = IForwardVault(fVault).balanceOf(address(this));
            uint tokens = oldShares > 0 ? IForwardVault(fVault).withdraw(oldShares) : 0;

            IERC20Upgradeable(fvwant).safeApprove(fVault, 0);
            
            IERC20Upgradeable(fvwant).safeApprove(_fVault, 0);
            IERC20Upgradeable(fvwant).safeApprove(_fVault, type(uint).max);

            // ratio = oldShares > 0 ? IForwardVault(_fVault).deposit(tokens).mul(1e18).div(oldShares) : ratio;
            // we use the following to save gas
            if (oldShares > 0) {
                uint newShares = IForwardVault(_fVault).deposit(tokens);
                ratio = newShares.mul(1e18).div(oldShares);
            }

        } else if (fVault != address(0) && _fVault == address(0)) {
            
            // disable vault finally
            uint oldShares = IForwardVault(fVault).balanceOf(address(this));
            uint tokens = oldShares > 0 ? IForwardVault(fVault).withdraw(oldShares) : 0;
            
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
    /***************** authed function end **********************/


    /***************** read function begin **********************/
    function balance() public view returns (uint) {
        return available().add(balanceSavingsInFVault());
    }

    function available() public view returns (uint) {
        return IERC20Upgradeable(margin).balanceOf(address(this));
    }
    
    function balanceSavingsInFVault() public view returns (uint) {
        return fVault == address(0) ? 0 : IForwardVault(fVault).balanceOf(address(this)).mul(
                                                        IForwardVault(fVault).getPricePerFullShare()
                                                    ).div(1e18);
    }

    function getPricePerFullShare() public view returns (uint) {
        return fVault == address(0) ? 
            ratio : 
            ratio.mul(IForwardVault(fVault).getPricePerFullShare()).div(1e18);
    }

    
    function getBuyerAmountToDeliver(uint _orderId) external virtual view returns (uint price) {
        Order memory order = orders[_orderId];        
        if (!order.buyerDelivered) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint buyerAmount = fee.add(base).mul(order.deliveryPrice).div(base);
            price = buyerAmount.sub(getPricePerFullShare().mul(order.buyerShare).div(1e18));
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
            7--canceled: order has been created and then canceled since no taker
     */
    function checkOrderState(uint _orderId) public virtual view returns (State) {
        Order memory order = orders[_orderId];
        if (order.validTill == 0 ) return State.inactive;
        if (order.state == State.canceled) return State.canceled;
        uint time = _getBlockTimestamp();
        if (time <= order.validTill) {
            if (order.state != State.filled) return State.active;
            return State.filled;
        }
        if (order.state == State.active) return State.dead;
        if (time <= order.deliverStart) {
            if (order.state != State.filled) return State.dead;
            return State.filled;
        }
        if (time <= order.expireStart) {
            if (order.state != State.settled) return State.delivery;
            return State.settled;
        }
        if (order.state != State.settled) return State.expired;
        return State.settled; // can only be settled
    }

    function getOrder(uint _orderId) external virtual view returns (Order memory order) {
        order = orders[_orderId];
    }
    function version() external virtual view returns (string memory) {
        return "v1.0";
    }
    /***************** read function end **********************/


    /***************** write function begin **********************/
    function cancelOrder(uint _orderId) external virtual {
        _onlyNotPaused();
        require(checkOrderState(_orderId)== State.dead, "!dead");
        _cancelOrder(_orderId);
    }
    function takeOrderFor(address _taker, uint _orderId) external virtual {
        _onlyNotPaused();
        require(checkOrderState(_orderId)== State.active, "!active");
        _takeOrderFor(_taker, _orderId);
    }
    
    function deliverFor(address _deliverer, uint _orderId) external virtual {
        _onlyNotPaused();
        require(checkOrderState(_orderId) == State.delivery, "!delivery");
        _deliverFor(_deliverer, _orderId);
    }

    function settle(uint _orderId) external virtual{
        _onlyNotPaused();
        require(checkOrderState(_orderId) == State.expired, "!expired");
        // delivery time has past, anyone can forcely settle/exercise this order
        _settle(_orderId, true);
    }
    /***************** write function end **********************/

    
    /***************** internal function start **********************/
    function _createOrderFor(
        address _creator,
        // uint _orderValidPeriod,
        // uint _deliveryStart,
        // uint _deliveryPeriod,
        uint[3] memory _times,
        // uint _deliveryPrice, 
        // uint _buyerMargin,
        // uint _sellerMargin,
        uint[3] memory _prices,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) internal virtual returns (uint) {
        require(_prices[0] < type(uint128).max && _prices[1] < type(uint128).max && _prices[2] < type(uint128).max, "overflow");
        require(uint(_prices[1].add(_prices[2])) < type(uint128).max, "deliver may overflow");
        require(uint(_times[1]).add(_times[2]) < type(uint40).max && _getBlockTimestamp().add(_times[0]) < uint(_times[1]), "!time");
        uint128 _shares;
        if (_deposit && !_isSeller) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            _shares = _pullMargin(fee.add(base).mul(_prices[0]).div(base), true);
        } else {
            // take margin from msg.sender normally
            _shares = _pullMargin(_isSeller ? _prices[2] : _prices[1], true);
        }

        uint index = ordersLength++;
        orders[index] = Order({
            buyer: _isSeller ? address(0) : _creator,
            buyerMargin: uint128(_prices[1]),
            buyerShare: _isSeller ? 0 : _shares,
            buyerDelivered: _deposit && !_isSeller,
            seller: _isSeller ? _creator : address(0),
            sellerMargin: uint128(_prices[2]),
            sellerShare: _isSeller ? _shares : 0,
            sellerDelivered: _deposit && _isSeller,
            deliveryPrice: uint128(_prices[0]),
            validTill: uint40(_getBlockTimestamp().add(_times[0])),
            deliverStart: uint40(_times[1]),
            expireStart: uint40(_times[1].add(_times[2])),
            state: State.active,
            takerWhiteList: new address[](0)
        });
        
        if (_takerWhiteList.length > 0) {
            for (uint i = 0; i < _takerWhiteList.length; i++) {
                orders[index].takerWhiteList.push(_takerWhiteList[i]);
            }
        }
        emit CreateOrder(index, _creator);
        return index;
    }

    function _cancelOrder(uint _orderId) internal virtual {
        Order memory order = orders[_orderId];
        // return margin to maker, underlyingAssets to maker if deposit
        if (order.buyer != address(0)) {
            _pushMargin(order.buyer, getPricePerFullShare().mul(order.buyerShare).div(1e18));
        } else if (order.seller != address(0)) {
            _pushMargin(order.seller, getPricePerFullShare().mul(order.sellerShare).div(1e18));
            if (order.sellerDelivered) _pushUnderlyingAssetsFromSelf(_orderId, order.seller);
        } else {
            revert("cancelOrder bug");
        }

        // mark order as canceled
        orders[_orderId].state = State.canceled;
        emit CancelOrder(_orderId);
    }


    function _takeOrderFor(address _taker, uint _orderId) internal virtual {
        Order memory order = orders[_orderId];
        if (order.takerWhiteList.length > 0) require(_withinList(_taker, order.takerWhiteList), "!whitelist");

        uint128 shares = _pullMargin(
            orders[_orderId].seller == address(0) ? orders[_orderId].sellerMargin : orders[_orderId].buyerMargin,
            true
        );

        // change storage
        if (orders[_orderId].buyer == address(0)) {
            orders[_orderId].buyer = _taker;
            orders[_orderId].buyerShare = shares;
        } else if (orders[_orderId].seller == address(0)) {
            orders[_orderId].seller = _taker;
            orders[_orderId].sellerShare = shares;
        } else {
            revert("takeOrder bug");
        }
        orders[_orderId].state = State.filled;
        emit TakeOrder(_orderId, _taker);
    }
    

    function _deliverFor(address _deliverer, uint _orderId) internal virtual {
        Order memory order = orders[_orderId];


        if (_deliverer == order.seller && !order.sellerDelivered) {
            // seller tends to deliver underlyingAssets[_orderId] amount of want tokens
            _pullUnderlyingAssetsToSelf(_orderId);
            orders[_orderId].sellerDelivered = true;
            emit Delivery(_orderId, _deliverer);
        } else if (_deliverer == order.buyer && !order.buyerDelivered) {
            // buyer tends to deliver tokens
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint debt = fee.add(base).mul(order.deliveryPrice).div(base);
            _pullMargin(
                debt.sub(getPricePerFullShare().mul(order.buyerShare).div(1e18)), 
                false /* here we do not farm delivered tokens since they just stay in contract for delivery period at most */
            );  
            orders[_orderId].buyerDelivered = true;
            emit Delivery(_orderId, _deliverer);
        } else {
            revert("deliver bug");
        }

        // soft settle means settle if necessary otherwise wait for the counterpart to deliver or the order to expire
        _settle(_orderId, false); 
    }


    function _settle(uint _orderId, bool _forceSettle) internal {
        (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
        Order memory order = orders[_orderId];
        // in case both sides delivered
        if (order.sellerDelivered && order.buyerDelivered) {
            // send buyer underlyingAssets[_orderId] amount of want tokens and seller margin
            _pushUnderlyingAssetsFromSelf(_orderId, order.buyer);
            uint bfee = fee.mul(order.deliveryPrice).div(base);
            // carefully check if there is margin left for buyer in case buyer depositted both margin and deliveryPrice at the very first
            uint bsa /*Buyer Share token Amount*/ = getPricePerFullShare().mul(order.buyerShare).div(1e18);
            // should send extra farmming profit to buyer
            if (bsa > bfee.add(order.deliveryPrice)) {
                _pushMargin(order.buyer, bsa.sub(order.deliveryPrice).sub(bfee));
            }
            
            // send seller payout
            uint sellerAmount = getPricePerFullShare().mul(order.sellerShare).div(1e18).add(order.deliveryPrice).sub(bfee);
            _pushMargin(order.seller, sellerAmount);
            cfee = cfee.add(bfee.mul(2));
            
            
            orders[_orderId].state = State.settled;
            emit Settle(_orderId);
            return; // must return here
        }
        if (_forceSettle) {
            if (!order.sellerDelivered) {
                // blame seller if he/she does not deliver nfts  
                uint sfee = fee.mul(order.sellerMargin).div(base);
                cfee = cfee.add(sfee);
                _pushMargin(
                    order.buyer, 
                    /* here we send both buyer and seller's margin to buyer except seller's op fee */
                    uint(order.buyerShare).add(order.sellerShare).mul(getPricePerFullShare()).div(1e18).sub(sfee)
                );
            } else if (!order.buyerDelivered) {
                // blame buyer
                uint bfee = fee.mul(order.buyerMargin).div(base);
                cfee = cfee.add(bfee);
                _pushMargin(
                    order.seller,
                    uint(order.sellerShare).add(order.buyerShare).mul(getPricePerFullShare()).div(1e18).sub(bfee)
                );
                // return underying assets (underlyingAssets[_orderId] amount of want) to seller
                _pushUnderlyingAssetsFromSelf(_orderId, order.seller);
            }
            orders[_orderId].state = State.settled;
            emit Settle(_orderId);
        }
    }



    
    function _pullMargin(uint _amount, bool _farm) internal virtual returns (uint128) {
        _pullTokensToSelf(margin, _amount);
        uint shares = _farm && fVault != address(0) ? 
                    IForwardVault(fVault).deposit(_amount).mul(1e18).div(ratio)
                    :
                    _amount.mul(1e18).div(getPricePerFullShare());
        return uint128(shares); // won't overflow since both _amount/ratio and 1e18/getPricePerFullShare < 1
    }

    function _pushMargin(address _to, uint _amount) internal virtual  {
        // check if balance not enough, if not, withdraw from vault
        uint ava = available();
        if (ava < _amount && fVault != address(0)) {
            IForwardVault(fVault).withdraw(_amount.sub(ava));
            ava = available();
        }
        if (_amount > ava) _amount = ava;
        _pushTokensFromSelf(margin, _to, _amount);
    }
    

    function _pullTokensToSelf(address _token, uint _amount) internal virtual {
        // below check is not necessary since we would check supported margin is untaxed
        // uint mtOld = IERC20Upgradeable(_token).balanceOf(address(this));
        if (_amount > 0) {
            IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
        // uint mtNew = IERC20Upgradeable(_token).balanceOf(address(this));
        // require(mtNew.sub(mtOld) == _amount, "!support taxed token");
        
    }
    
    function _pushTokensFromSelf(address _token, address _to, uint _amount) internal virtual {
        IERC20Upgradeable(_token).safeTransfer(_to, _amount);
    }


    function _withinList(address addr, address[] memory list) internal pure returns (bool) {
        for (uint i = 0; i < list.length; i++) {
            if (addr == list[i]) return true;
        }
        return false;
    }

    function _getBlockTimestamp() internal view returns (uint) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }

    function _pullUnderlyingAssetsToSelf(uint _orderId) internal virtual {}
    function _pushUnderlyingAssetsFromSelf(uint _orderId, address _to) internal virtual {}
    /***************** internal function end **********************/
}