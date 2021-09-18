// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../../interface/IHogletFactory.sol";
import "../../interface/IWETH.sol";
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
    // info of eth and weth
    address public eth;
    address public weth;
    // cumulative fee
    uint256 public cfee;
    // ratio = value of per share in forward : per share in fVault
    uint256 public ratio;
    
    // forward contract status 
    bool public paused;

    enum OrderState { inactive, active, filled, dead, delivery, expired, settled }    
    struct Dealer {
        uint256 margin;
        uint256 share;
        address addr;
        bool delivered;
    }
    struct Order {
        Dealer seller;
        Dealer buyer;
        uint256 deliveryPrice;
        uint validTill;
        uint deliverStart;         // timpstamp
        uint expireStart;          // timestamp
        OrderState state;
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
        uint _poolType,
        address _margin
    ) public initializer {
        __ReentrancyGuard_init();
        factory = msg.sender;
        require(_poolType == 20, "!20");
        IHogletFactory _factory = IHogletFactory(factory);
        require(_factory.ifMarginSupported(_margin), "!margin");
        want = _want;
        margin = _margin;
        weth = _factory.weth();
        eth = address(0);
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
            require(fvwant == margin || fvwant == weth, "!want");
            // approve margin tokens for new forward vault
            IERC20Upgradeable(fvwant).safeApprove(_fVault, 0);
            IERC20Upgradeable(fvwant).safeApprove(_fVault, type(uint256).max);

        } else if (fVault != address(0) && _fVault != address(0)) {
            
            // change vault from one to another one
            address fvwant = IForwardVault(_fVault).want();
            require(fvwant == margin || fvwant == weth, "!want");

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
            if (margin == eth) {
                uint _weth = IWETH(weth).balanceOf(address(this));
                if (_weth > 0) {
                    IWETH(weth).withdraw(_weth);
                }
            }
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
        _pushTokens(_to, cfee);
        cfee = 0;
    }


    function balance() public view returns (uint256) {
        return available().add(balanceSavingsInHVault());
    }

    function available() public view returns (uint256) {
        return margin == address(0) ? address(this).balance : IERC20Upgradeable(margin).balanceOf(address(this));
    }
    
    function balanceSavingsInHVault() public view returns (uint256) {
        return fVault == address(0) ? 0 : IForwardVault(fVault).balanceOf(address(this)).mul(
                                                    IForwardVault(fVault).getPricePerFullShare()
                                                    ).div(1e18);
    }

    function getPricePerFullShare() public view returns (uint256) {
        return fVault == address(0) ? 
            ratio : 
            ratio.mul(IForwardVault(fVault).getPricePerFullShare()).div(1e18);
    }

    function version() external virtual view returns (string memory) {
        return "v1.0";
    }

    function _createOrder(
        uint256 _orderValidPeriod, 
        uint256 _deliveryPrice, 
        uint256 _nowToDeliverPeriod,
        uint256 _deliveryPeriod,
        uint256 _buyerMargin,
        uint256 _sellerMargin,
        bool _deposit,
        bool _isSeller, 
        uint shares
    ) internal virtual {
        uint validTill = _getBlockTimestamp().add(_orderValidPeriod);
        uint deliverStart = _getBlockTimestamp().add(_nowToDeliverPeriod);
        uint expireStart = deliverStart.add(_deliveryPeriod);
        orders.push(
            Order({
                buyer: Dealer({
                    addr: _isSeller ? address(0) : msg.sender,
                    margin: _buyerMargin,
                    share: _isSeller ? 0 : shares,
                    delivered: _deposit && !_isSeller
                }),
                seller: Dealer({
                    addr: _isSeller ? msg.sender : address(0),
                    margin: _sellerMargin,
                    share: _isSeller ? shares : 0,
                    delivered: _deposit && _isSeller
                }),
                deliveryPrice: _deliveryPrice,
                validTill: validTill,
                deliverStart: deliverStart,
                expireStart: expireStart,
                state: OrderState.active,
                takerWhiteList: new address[](0)
            })
        );
    }

    function takeOrder(uint _orderId) external virtual nonReentrant payable {
        _onlyNotPaused();
        _takeOrder(_orderId);
    }

    function _takeOrder(uint _orderId) internal virtual {
        address taker = msg.sender;
        // check condition
        require(_orderId < orders.length, "!orderId");
        Order memory order = orders[_orderId];
        require(_getBlockTimestamp() <= order.validTill && order.state == OrderState.active, "!valid & !active"); // okay redundant check
        
        if (order.takerWhiteList.length > 0) {
            require(_withinList(taker, order.takerWhiteList), "!whitelist");
        }

        uint takerMargin = orders[_orderId].seller.addr == address(0) ? orders[_orderId].seller.margin : orders[_orderId].buyer.margin;
        uint shares = _pullTokens(taker, takerMargin, true);

        // change storage
        if (orders[_orderId].buyer.addr == address(0)) {
            orders[_orderId].buyer.addr = taker;
            orders[_orderId].buyer.share = shares;
        } else if (orders[_orderId].seller.addr == address(0)) {
            orders[_orderId].seller.addr = taker;
            orders[_orderId].seller.share = shares;
        } else {
            revert("bug");
        }
        orders[_orderId].state = OrderState.filled;
        emit TakeOrder(_orderId, taker, takerMargin);
    }
    
    /**
     * @dev only maker or taker from orderId's order be taken as _payer of this method during delivery period, 
     *       _payer needs to pay the returned margin token to deliver _orderId's order
     * @param _orderId the order for which we want to check _payers needs to pay at delivery
     * @param _payer the address which needs to pay for _orderId at delivery
     * @return how many margin token _payer needs to pay _orderId in order to deliver
     */
    function getAmountToDeliver(uint256 _orderId, address _payer) external virtual returns (uint) {}

    function deliver(uint256 _orderId) external virtual nonReentrant payable {}

    function settle(uint256 _orderId) external virtual nonReentrant{}

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
        if (order.buyer.addr == address(0) || order.seller.addr == address(0)) return OrderState.dead;
        if (time <= order.deliverStart) return OrderState.filled;
        if (time <= order.expireStart) return OrderState.delivery;
        if (order.state != OrderState.settled) return OrderState.expired;
        return OrderState.settled;
    }

    function orderLength() external virtual view returns (uint) {
        return orders.length;
    }

    
    function _pullTokens(address _from, uint amount, bool farm) internal virtual returns (uint shares) {
        if (margin == eth) {
            require(msg.value >= amount, "!margin"); // don't send more ether, won't pay you back
            // if vault exists, chagne ether to weth 
            if (fVault != address(0)) {
                IWETH(weth).deposit{value: msg.value}();
            }
        } else {
            uint mtOld = IERC20Upgradeable(margin).balanceOf(address(this));
            IERC20Upgradeable(margin).safeTransferFrom(_from, address(this), amount);
            uint mtNew = IERC20Upgradeable(margin).balanceOf(address(this));
            require(mtNew.sub(mtOld) == amount, "!support taxed token");
        }

        shares = fVault != address(0) && farm ? 
                    IForwardVault(fVault).deposit(amount).mul(1e18).div(ratio) /* current line equals above line */
                    :
                    amount.mul(1e18).div(getPricePerFullShare());
    }
    
    function _pushTokens(address _to, uint amount) internal virtual  {
        // check if balance not enough, if not, withdraw from vault
        uint ava = available();
        if (ava < amount && fVault != address(0)) {
            IForwardVault(fVault).withdraw(amount.sub(ava));
        }
        ava = available();
        if (amount > ava) {
            amount = margin == eth ? IWETH(weth).balanceOf(address(this)).add(ava) : ava;
        }
        
        if (margin == eth) {
            IWETH(weth).withdraw(IWETH(weth).balanceOf(address(this)));
            payable(_to).transfer(amount);

        } else {
            IERC20Upgradeable(margin).safeTransfer(_to, amount);
        }
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