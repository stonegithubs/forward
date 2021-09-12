// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../HedgehogFactoryUpgradeable.sol";

contract TestFactoryUpgrade is HedgehogFactoryUpgradeable {
    function version() external virtual override view returns (string memory) {
        return "v1.1";
    }
}