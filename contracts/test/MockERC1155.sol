// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract MockERC1155 is ERC1155 {
    constructor (string memory _uri) ERC1155(_uri) {
    }
    
    function mintBatch(address to, uint[] memory ids, uint[] memory amounts) public {
        _mintBatch(to, ids, amounts, "");
    }

    function mint(address to, uint256 id, uint amount) public {
        _mint(to, id, amount, "");
    }

}