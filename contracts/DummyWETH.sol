// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


library DummyWETH {
    function getChainId() internal view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }
    
    function dummyWeth() internal view returns (address) {
        uint chainId = getChainId();
        
        if        (chainId == 1     /* eth mainnet */) {
            return address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        } else if (chainId == 56    /* bsc mainnet */) {
            return address(0);
        } else if (chainId == 128   /* heco mainnet */) {
            return address(0);
        } else if (chainId == 3     /* eth ropsten */) {
            return address(0xb603cEa165119701B58D56d10D2060fBFB3efad8);
        } else if (chainId == 4     /* eth rinkeby */){
            return address(0);
        } else if (chainId == 42    /* eth kovan */) {
            return address(0);
        } else if (chainId == 256   /* heco testnet */) {
            return address(0);
        } else if (chainId == 97    /* bsc testnet */) {
            return address(0);
        } else if (chainId == 61    /* etc mainnet */) {
            return address(0);
        } else if (chainId == 62    /* etc morden testnet */) {
            return address(0);
        } else {
            revert("dummyWeth not supported");
        }
        
    }
    
}