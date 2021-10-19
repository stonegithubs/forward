// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./base/BaseFactoryUpgradeable.sol";
import "../forward/Forward1155Upgradeable.sol";

contract Factory1155Upgradeable is BaseFactoryUpgradeable {

    function _deployPool(
        address _asset,
        uint _assetType,
        address _margin
    ) internal virtual override returns (address) {

        address beaconProxyAddr;
        if (_assetType == 1155) {
            beaconProxyAddr = address(new BeaconProxy(address(this), ""));
            Forward1155Upgradeable(beaconProxyAddr).__Forward1155Upgradeable__init(_asset, _assetType, _margin);

        } else {
            revert("only support 1155");
        }
        
        getPair[_asset][_margin] = beaconProxyAddr;
        getPair[_margin][_asset] = beaconProxyAddr;
        
        return beaconProxyAddr;
    }
    
    
}