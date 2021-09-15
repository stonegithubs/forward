// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./proxy/beacon/UpgradeableBeacon.sol";
import "./proxy/beacon/BeaconProxy.sol";
import "./interface/IHedgehogFactory.sol";
import "./proxy/Clones.sol";
import "./Forward721Upgradeable.sol";

contract HedgehogFactoryUpgradeable is UpgradeableBeacon, IHedgehogFactory {

    uint256 public fee;
    uint256 public constant Base = 10000;
    
    address[] public enabledTokens;
    mapping(address => int) public supportedTokens;
    
    address public override feeCollector;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PoolCreated(
        address indexed nftAddr,
        uint poolType,
        address marginToken,
        uint index
    );

    constructor(){}

    function initialize(
        address _forward721Imp,
        address[] memory _marginTokens, 
        address _feeCollector,
        uint _fee
    ) public initializer {
        __UpgradeableBeacon__init(_forward721Imp);


        enabledTokens.push(address(0));
        for (uint i = 0; i < _marginTokens.length; i++) {
            enabledTokens.push(_marginTokens[i]);
            supportedTokens[_marginTokens[i]] = int(i + 1);
        }

        feeCollector = _feeCollector;
        require(_fee >= 0 && _fee < Base, "!fee");
        fee = _fee;
    }

    function supportToken(address _token) external onlyOwner {
        require(_token != address(0), "!0x00");

        require(!ifTokenSupported(_token), "supported already");
        if (uint(supportedTokens[_token]) == 0) {
            enabledTokens.push(_token);
            supportedTokens[_token] = int(enabledTokens.length);
        } else {
            supportedTokens[_token] = -supportedTokens[_token];
        }

    }
    function disableToken(address _token) external onlyOwner {

        require(_token != address(0), "!0x00");

        require(ifTokenSupported(_token), "disabled already");

        supportedTokens[_token] = -supportedTokens[_token];

    }

    function setFee(uint _fee) external onlyOwner {
        require(_fee >= 0 && _fee < Base, "!fee");
        fee = _fee;
    }
    
    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "!feeCollector");
        feeCollector = _feeCollector;
    }

    function setForwardVault(uint256 _poolId, address _forwardVault) external onlyOwner {
        Forward721Upgradeable(allPairs[_poolId]).setForwardVault(_forwardVault);
    }

    function ifTokenSupported(address _token) public view override returns (bool) {
        return _token == address(0) || supportedTokens[_token] > 0;
    }

    function getOperationFee() external view override returns (uint, uint) {
        return (fee, Base);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function deployPool(
        address _nftAddr,
        uint _poolType,
        address _marginToken
    ) external {
        require(getPair[_nftAddr][_marginToken] == address(0), "pool exist"); // single check is sufficient

        address beaconProxyAddr;
        if (_poolType == 721) {
            // Do not use Method 1 to prevent redundant contract deploy for same parameters, 
            //     because it will always succeed with contract account's nonce increasing
            // Method 1: deploy new beacon proxy
            // address beaconProxyAddr = address(new BeaconProxy(address(this), ""));

            // Method 2: 
            bytes32 salt = keccak256(abi.encodePacked(_nftAddr, _poolType, _marginToken));
            beaconProxyAddr = Clones.cloneDeterministic(implementation(), salt);
            
            
            Forward721Upgradeable(beaconProxyAddr).initialize(_nftAddr, _poolType, _marginToken);

        } else {
            revert("!support");
        }

        getPair[_nftAddr][_marginToken] = beaconProxyAddr;
        getPair[_marginToken][_nftAddr] = beaconProxyAddr;
        allPairs.push(beaconProxyAddr);

        emit PoolCreated(_nftAddr, _poolType, beaconProxyAddr, allPairs.length);
    }
    
    function version() external virtual override view returns (string memory) {
        return "v1.0";
    }
    
}