// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./base/BaseForwardUpgradeable.sol";
import "../interface/IHogletFactory.sol";
import "../interface/IForwardVault.sol";

contract Forward20Upgradeable is BaseForwardUpgradeable {
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
        uint256 _underlyingAmount, 
        uint _orderValidPeriod, 
        uint _nowToDeliverPeriod,
        uint _deliveryPeriod,
        uint256 _deliveryPrice,
        uint256 _buyerMargin,
        uint256 _sellerMargin,
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
        uint shares = _pullMargin(
            _deliveryPrice, 
            _buyerMargin,
            _sellerMargin,
            _deposit, 
            _isSeller
        );

        // create order
        _createOrder(
            _orderValidPeriod, 
            _nowToDeliverPeriod, 
            _deliveryPeriod, 
            _deliveryPrice, 
            _buyerMargin, 
            _sellerMargin,
            _takerWhiteList, 
            _deposit, 
            _isSeller, 
            shares
        );

        underlyingAssets.push(_underlyingAmount);
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

    

    function _pullUnderlyingAssetsToSelf(uint256 _orderId) internal virtual override {
        _pullTokensToSelf(want, underlyingAssets[_orderId]);
    }

    function _pushUnderingAssetsFromSelf(uint256 _orderId, address _to) internal virtual override {
        _pushTokensFromSelf(want, _to, underlyingAssets[_orderId]);
    }
    
    function _onlyNotProtectedTokens(address _asset) internal virtual override view {
        require(_asset != want, "!want");
        require(_asset != margin, "!margin");
        require(_asset != fVault, "!fVault");
    }


}