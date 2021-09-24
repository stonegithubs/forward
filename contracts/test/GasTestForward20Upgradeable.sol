// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./GasTestBaseForwardUpgradeable.sol";
import "../interface/IHogletFactory.sol";
import "../interface/IForwardVault.sol";

contract GasTestForward20Upgradeable is GasTestBaseForwardUpgradeable {
    using SafeMathUpgradeable for uint256;
    
    // orderId => amount of want
    uint256[] public underlyingAssets;

    function __Forward20Upgradeable__init(
        address _want,
        uint _poolType,
        address _margin
    ) public initializer {
        __BaseForward__init(_want, _margin);
        require(_poolType == 20, "!20");
    }

    function createOrder(
        address _creator,
        uint256 _underlyingAmount, 
        // uint _orderValidPeriod, 
        // uint _nowToDeliverPeriod,
        // uint _deliveryPeriod,
        // uint256 _deliveryPrice,
        // uint256 _buyerMargin,
        // uint256 _sellerMargin,
        uint256[6] memory _uintData,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external nonReentrant {
        _onlyNotPaused();

        // check if msg.sender wants to deposit _underlyingAmount amount of want directly
        if (_deposit && _isSeller) {
            _pullTokensToSelf(want, _underlyingAmount);
        }

        // check if msg.sender wants to deposit tokens directly 
        uint shares;
        if (_deposit && !_isSeller) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            shares = _pullMargin(_uintData[3].mul(fee.add(base)).div(base), true);
        } else {
            // take margin from msg.sender normally
            shares = _pullMargin(_isSeller ? _uintData[5] : _uintData[4], true);
        }

        // create order
        _createOrder(
            _creator,
            // _orderValidPeriod, 
            // _nowToDeliverPeriod, 
            // _deliveryPeriod, 
            // _deliveryPrice, 
            // _buyerMargin, 
            // _sellerMargin,
            _uintData,
            _takerWhiteList, 
            _deposit, 
            _isSeller, 
            shares
        );

        underlyingAssets.push(_underlyingAmount);
    }

    function getAmountToDeliver(uint256 _orderId, address _payer) external virtual override view returns (uint256 price) {
        Order memory order = orders[_orderId];        
        if (_payer == order.buyer && !order.buyerDelivered) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            price = buyerAmount.sub(
                        order.buyerShare.mul(getPricePerFullShare()).div(1e18)
                    );
        }
        if (_payer == order.seller && !order.sellerDelivered) {
            price = order.deliveryPrice;
        }
    }

    function deliver(address _deliverer, uint256 _orderId) external virtual override nonReentrant {
        _onlyNotPaused();
        Order memory order = orders[_orderId];
        require(checkOrderState(_orderId) == OrderState.delivery, "!delivery");

        require(_deliverer == order.seller || _deliverer == order.buyer, "only seller & buyer");

        if (_deliverer == order.seller && !order.sellerDelivered) {
            // seller tends to deliver underlyingAssets[_orderId] amount of want tokens
            _pullTokensToSelf(want, underlyingAssets[_orderId]);
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

    /**
    * @dev anybody can invoke this method to end orderId
    * @param _orderId the order msg.sender wants to settle at the final stage
     */
    function settle(uint256 _orderId) external virtual override nonReentrant {
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
            _pushTokensFromSelf(want, order.buyer, underlyingAssets[_orderId]);
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
                _pushTokensFromSelf(want, order.seller, underlyingAssets[_orderId]);
            }
            orders[_orderId].state = OrderState.settled;
            emit Settle(_orderId);
        }
    }

    function _onlyNotProtectedTokens(address _asset) internal virtual override view {
        require(_asset != want, "!want");
        require(_asset != margin, "!margin");
        require(_asset != fVault, "!fVault");
    }


}