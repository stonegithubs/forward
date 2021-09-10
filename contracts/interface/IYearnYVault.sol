// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IYearnYVault is IERC20Upgradeable {

    // read methods
    function balance() external view returns (uint256);
    function available() external view returns (uint256);
    function getPricePerFullShare() external view returns (uint256);
    function token() external view returns (address); // deposited token
    

    // write methods
    function depositAll() external;
    function deposit(uint256 _amount) external;
    function withdrawAll() external;
    function withdraw(uint256 _shares) external;
    function earn() external;
}