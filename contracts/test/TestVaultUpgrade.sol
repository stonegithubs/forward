// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../vault/HForwardVaultUpgradeable.sol";

contract TestVaultUpgrade is HForwardVaultUpgradeable {
    function version() external virtual override view returns (string memory) {
        return "v1.1";
    }
}