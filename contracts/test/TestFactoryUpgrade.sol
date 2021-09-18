// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../factory/Factory721Upgradeable.sol";

contract TestFactoryUpgrade is Factory721Upgradeable {
    function version() external virtual override view returns (string memory) {
        return "v1.1";
    }
}