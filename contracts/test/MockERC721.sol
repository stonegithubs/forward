// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC721 is ERC721, Ownable {
    uint public totalSupply;
    constructor (string memory _name, string memory _symbol) ERC721(_name, _symbol) {
    }

    
    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
        totalSupply++;
    }

    function mintBatch(address to, uint[] memory ids) public {
        for (uint i = 0; i < ids.length; i++) {
            _mint(to, ids[i]);
            totalSupply++;
        }
    }

    function safeMint(address to, uint256 tokenId) public {
        _safeMint(to, tokenId);
        totalSupply++;
    }

    function safeMint(address to, uint256 tokenId, bytes memory _data) public {
        _safeMint(to, tokenId, _data);
        totalSupply++;
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);
        totalSupply--;
    }
    
}