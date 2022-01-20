// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBaseForward  {
    
    event CreateOrder(uint orderId, address maker);
    event TakeOrder(uint orderId, address taker);
    event Delivery(uint orderId, address deliver);
    event Settle(uint orderId);
    event CancelOrder(uint orderId);

    function factory() external view returns (address);
    function want() external view returns (address);
    function margin() external view returns (address);
    function fVault() external view returns (address);
    function cfee() external view returns (uint);
    function ratio() external view returns (uint);
    function paused() external view returns (bool);

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
    function orders(uint _index) external view returns (Order memory);
    function getOrder(uint _index) external view returns (Order memory);


    // read methods
    function version() external returns (string memory);
    function balance() external view returns (uint);
    function available() external view returns (uint);
    function balanceSavingsInFVault() external view returns (uint);
    function getPricePerFullShare() external view returns (uint);
    function getBuyerAmountToDeliver(uint _orderId) external view returns (uint);
    function checkOrderState(uint _orderId) external view returns (State);
    function ordersLengh() external view returns (uint);

    // write methods
    function takeOrderFor(address _taker, uint _orderId) external;
    function deliverFor(address _deliverer, uint _orderId) external;
    function settle(uint _orderId) external;
    function cancelOrder(uint _orderId) external;

    function setForwardVault(address _fVault) external;
}
