// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IHedgehogFactory {
    
    // read methods
    function ifCoinEnabled(address coin) external view returns (bool);
    function getMarginRatios() external view returns (uint maker, uint taker, uint base);
    function ERC721_POOL() external view returns (bytes32);

    // write methods
    function deployMarket(
        address contractAddr,
        uint tokenType
    ) external;
}
