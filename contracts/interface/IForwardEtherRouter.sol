// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IForwardEtherRouter  {
    function createOrder20For(
        address _forward20,
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
    ) external payable returns (uint orderId);

    function createOrder721For(
        address _forward721,
        address _creator,
        uint[] memory _tokenIds, 
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
    ) external payable returns (uint orderId);

    function createOrder1155For(
        address _forward1155,
        address _creator,
        uint[] memory _ids,
        uint[] memory _amounts,
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
    ) external payable returns (uint orderId);

    function takeOrderFor(
        address _forward,
        address _taker,
        uint _orderId
    ) external payable;

    function deliverFor(
        address _forward,
        address _deliverer,
        uint _orderId
    ) external payable;

    function settle(
        address _forward,
        uint _orderId
    ) external;

    function cancelOrder(
        address _forward,
        uint _orderId
    ) external;

    function ordersLength(address _forward) external view returns (uint);
    function weth() external view returns (address);
}
