// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./base/BaseForwardUpgradeable.sol";
import "../interface/IHogletFactory.sol";
import "../interface/IWETH.sol";
import "../interface/IForwardVault.sol";

contract Forward20Upgradeable is BaseForwardUpgradeable {
    using SafeMathUpgradeable for uint256;
    
    // orderId => amount of want
    mapping(uint256 => uint256) public underlyingAssets;

    function __Forward20Upgradeable__init(
        address _want,
        uint _poolType,
        address _margin
    ) public initializer {
        __BaseForward__init(_want, _poolType, _margin);
        require(_poolType == 20, "!20");
    }

    function createOrder(
        uint256 _underlyingAmount, 
        uint _orderValidPeriod, 
        uint256 _deliveryPrice,
        uint _nowToDeliverPeriod,
        uint _deliveryPeriod,
        address[] memory _takerWhiteList,
        uint256 _buyerMargin,
        uint256 _sellerMargin,
        bool _deposit,
        bool _isSeller
    ) external nonReentrant payable {
        _onlyNotPaused();

        // check if msg.sender wants to deposit _underlyingAmount amount of want directly
        if (_deposit && _isSeller) {
            _pullTokens(msg.sender, _underlyingAmount, false);
        }

        // check if msg.sender wants to deposit tokens directly 
        uint shares;
        if (_deposit && !_isSeller) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint p = _deliveryPrice.mul(fee.add(base)).div(base);
            shares = _pullTokens(msg.sender, p, true);
        } else {
            // take margin from msg.sender normally
            shares = _pullTokens(msg.sender, _isSeller ? _sellerMargin : _buyerMargin, true);
        }

        // create order
        _createOrder(_orderValidPeriod, _deliveryPrice, _nowToDeliverPeriod, _deliveryPeriod, _buyerMargin, _sellerMargin, _deposit, _isSeller, shares);
        
        uint curOrderIndex = orders.length - 1;
        underlyingAssets[orders.length-1] = _underlyingAmount;
        if (_takerWhiteList.length > 0) {
            for (uint i = 0; i < _takerWhiteList.length; i++) {
                orders[curOrderIndex].takerWhiteList.push(_takerWhiteList[i]);
            }
        }
        
        emit CreateOrder(curOrderIndex, msg.sender);
    }

    function getAmountToDeliver(uint256 _orderId, address _payer) external virtual override view returns (uint256 price) {
        Order memory order = orders[_orderId];        
        if (_payer == order.buyer.addr && !order.buyer.delivered) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            price = buyerAmount.sub(
                        order.buyer.share.mul(getPricePerFullShare()).div(1e18)
                    );
        }
        if (_payer == order.seller.addr && !order.seller.delivered) {
            price = order.deliveryPrice;
        }
    }


}