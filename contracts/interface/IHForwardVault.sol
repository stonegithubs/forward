// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IHForwardVault is IERC20Upgradeable {
    

    // write methods
    function deposit(uint256 _amount) external returns (uint256 shares);
    function depositAll() external returns (uint256 shares);
    function withdraw(uint256 _shares) external returns (uint256 tokens);
    function withdrawAll() external returns (uint256 tokens); 

    // read methods
    function balance() external view returns (uint256);
    function balanceSavingsInYVault() external view returns (uint256);
    function suitable() external view returns (uint256);
    function getPricePerFullShare() external view returns (uint256);
    function want() external view returns (address);
    function yVault() external view returns (address);
    function governance() external view returns (address);
    
    function version() external returns (string memory);

}
