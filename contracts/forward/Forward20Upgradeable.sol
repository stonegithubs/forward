// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/BaseForwardUpgradeable.sol";
import "../interface/IHogletFactory.sol";
import "../interface/IForwardVault.sol";

contract Forward20Upgradeable is BaseForwardUpgradeable {
    
    // orderId => amount of want
    uint[] public underlyingAssets;

    function __Forward20Upgradeable__init(
        address _want,
        uint _poolType,
        address _margin
    ) public initializer {
        __BaseForward__init(_want, _margin);
        require(_poolType == 20, "!20");
    }

    function createOrderFor(
        address _creator,
        uint _underlyingAmount, 
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
    ) external {
        _onlyNotPaused();

        // check if msg.sender wants to deposit _underlyingAmount amount of want directly
        if (_deposit && _isSeller) {
            _pullTokensToSelf(want, _underlyingAmount);
        }

        // create order
        _createOrderFor(
            _creator,
            // _orderValidPeriod,
            // _deliveryStart, 
            // _deliveryPeriod,
            _times,
            // _deliveryPrice, 
            // _buyerMargin, 
            // _sellerMargin,
            _prices,
            _takerWhiteList, 
            _deposit, 
            _isSeller
        );

        underlyingAssets.push(_underlyingAmount);
    }

    function _pullUnderlyingAssetsToSelf(uint _orderId) internal virtual override {
        _pullTokensToSelf(want, underlyingAssets[_orderId]);
    }

    function _pushUnderlyingAssetsFromSelf(uint _orderId, address _to) internal virtual override {
        _pushTokensFromSelf(want, _to, underlyingAssets[_orderId]);
    }
    
    function _onlyNotProtectedTokens(address _asset) internal virtual override view {
        require(_asset != want, "!want");
        require(_asset != margin, "!margin");
        require(_asset != fVault, "!fVault");
    }


}