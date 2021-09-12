// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Forward721Upgradeable.sol";

contract TestForward721Upgrade is Forward721Upgradeable {
    function version() external virtual override view returns (string memory) {
        return "v1.1";
    }
}