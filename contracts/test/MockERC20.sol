// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor (string memory _name, string memory _symbol, uint _s) ERC20(_name, _symbol) {
        _mint(msg.sender, _s*1e18);
    }

    function mint(uint amount) external {
        _mint(msg.sender, amount);
    }
    
    function burn(uint amount) external {
        _burn(msg.sender, amount);       
    }
}