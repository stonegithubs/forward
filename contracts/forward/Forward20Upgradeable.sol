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
            _isSeller
        );

        underlyingAssets.push(_underlyingAmount);
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