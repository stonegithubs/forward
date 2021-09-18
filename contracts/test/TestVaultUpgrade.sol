// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../vault/ForwardVaultUpgradeable.sol";

contract TestVaultUpgrade is ForwardVaultUpgradeable {
    function version() external virtual override view returns (string memory) {
        return "v1.1";
    }
}