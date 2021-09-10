// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../proxy/beacon/IBeacon.sol";
interface IHedgehogFactory is IBeacon {
    
    
    // read methods
    function ifCoinEnabled(address coin) external view returns (bool);
    function getOperationFee() external view returns (uint fee, uint base);
    function feeCollector() external view returns (address);
}
