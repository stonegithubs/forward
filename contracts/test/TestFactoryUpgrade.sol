// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../HogletFactoryUpgradeable.sol";

contract TestFactoryUpgrade is HogletFactoryUpgradeable {
    function version() external virtual override view returns (string memory) {
        return "v1.1";
    }
}