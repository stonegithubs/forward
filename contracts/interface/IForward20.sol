// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IBaseForward.sol";

interface IForward721 is IBaseForward  {
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
    ) external;

    function underlyingAssets(uint _orderId) external view returns (uint amount);
}
