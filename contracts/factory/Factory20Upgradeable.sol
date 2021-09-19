// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./base/BaseFactoryUpgradeable.sol";
import "../forward/Forward20Upgradeable.sol";

contract Factory20Upgradeable is BaseFactoryUpgradeable {


    function _deployPool(
        address _asset,
        uint _poolType,
        address _margin
    ) internal virtual override returns (address) {

        address beaconProxyAddr;
        if (_poolType == 20) {
            // Do use Method 1 
            // Method 1: deploy new beacon proxy
            beaconProxyAddr = address(new BeaconProxy(address(this), ""));

            // // Method 2: Do NOT use this method
            // bytes32 salt = keccak256(abi.encodePacked(_asset, _poolType, _margin));
            // beaconProxyAddr = Clones.cloneDeterministic(implementation(), salt);
            
            
            Forward20Upgradeable(beaconProxyAddr).__Forward20Upgradeable__init(_asset, _poolType, _margin);

        } else {
            revert("only support 20");
        }
        
        getPair[_asset][_margin] = beaconProxyAddr;
        // we should enable the creation of  forward contract with _magin as asset goods and _asset as margin token
        // getPair[_margin][_asset] = beaconProxyAddr;
        
        return beaconProxyAddr;
    }
    
    
}