// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../../interface/IHogletFactory.sol";
import "../../interface/IForwardVault.sol";


contract BaseForwardUpgradeableV2 is ReentrancyGuardUpgradeable {
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
    uint256 public ordersLength;
    
    // forward contract status 
    bool public paused;

    enum State { inactive, active, filled, dead, delivery, expired, settled }

    struct Order {
        uint256 buyerMargin;
        uint256 sellerMargin;
        uint256 buyerShare;
        uint256 sellerShare;
        uint256 deliveryPrice;
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
        // uint _orderValidPeriod,
        // uint _deliveryStart,
        // uint _deliveryPeriod,
        uint[] memory _times,
        // uint _deliveryPrice, 
        // uint _buyerMargin,
        // uint _sellerMargin,
        uint[] memory _prices,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) internal virtual {

        require(uint(_times[1]).add(_times[2]) < type(uint40).max && _getBlockTimestamp().add(_times[0]) < uint(_times[1]), "!time");
        uint _shares;
        if (_deposit && !_isSeller) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            _shares = _pullMargin(_prices[0].mul(fee.add(base)).div(base), true);
        } else {
            // take margin from msg.sender normally
            _shares = _pullMargin(_isSeller ? _prices[2] : _prices[1], true);
        }

        uint index = ordersLength++;
        orders[index] = Order({
            buyer: _isSeller ? address(0) : _creator,
            buyerMargin: _prices[1],
            buyerShare: _isSeller ? 0 : _shares,
            buyerDelivered: _deposit && !_isSeller,
            seller: _isSeller ? _creator : address(0),
            sellerMargin: _prices[2],
            sellerShare: _isSeller ? _shares : 0,
            sellerDelivered: _deposit && _isSeller,
            deliveryPrice: _prices[0],
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
        emit CreateOrder(index);
    
    }

    
    function takeOrderFor(address _taker, uint _orderId) external virtual nonReentrant {
        _onlyNotPaused();
        _takeOrderFor(_taker, _orderId);
    }

    function _takeOrderFor(address _taker, uint _orderId) internal virtual {

        require(checkOrderState(_orderId)== State.active, "!active");
        
        Order memory order = orders[_orderId];
        if (order.takerWhiteList.length > 0) {
            require(_withinList(_taker, order.takerWhiteList), "!whitelist");
        }

        uint shares = _pullMargin(
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
        emit TakeOrder(_orderId);
    }
    
    function _pullUnderlyingAssetsToSelf(uint256 _orderId) internal virtual {}
    function _pushUnderingAssetsFromSelf(uint256 _orderId, address _to) internal virtual {}

    function deliverFor(address _deliverer, uint256 _orderId) external virtual nonReentrant {
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
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            _pullMargin(
                buyerAmount.sub(
                    order.buyerShare.mul(getPricePerFullShare()).div(1e18)
                ), 
                false /* here we do not farm delivered tokens since they just stay in contract for challenge period at most */
            );  
            orders[_orderId].buyerDelivered = true;
            emit Delivery(_orderId);
        } else {
            revert("deliver bug");
        }

        // soft settle means settle if necessary otherwise wait for the counterpart to deliver
        _settle(_orderId, false); 
    }

    function settle(uint256 _orderId) external virtual nonReentrant{
        _onlyNotPaused();
        require(checkOrderState(_orderId) == State.expired, "!expired");
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
            
            
            orders[_orderId].state = State.settled;
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
            ava = available();
        }
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