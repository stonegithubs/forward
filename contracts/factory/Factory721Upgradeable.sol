// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./base/BaseFactoryUpgradeable.sol";
import "../forward/Forward721Upgradeable.sol";

contract Factory721Upgradeable is BaseFactoryUpgradeable {

    function _deployPool(
        address _asset,
        uint _poolType,
        address _margin
    ) internal virtual override returns (address) {

        address beaconProxyAddr;
        if (_poolType == 721) {
            beaconProxyAddr = address(new BeaconProxy(address(this), ""));
            Forward721Upgradeable(beaconProxyAddr).__Forward721Upgradeable__init(_asset, _poolType, _margin);

        } else {
            revert("only support 721");
        }
        
        getPair[_asset][_margin] = beaconProxyAddr;
        getPair[_margin][_asset] = beaconProxyAddr;
        
        return beaconProxyAddr;
    }
    
    
}