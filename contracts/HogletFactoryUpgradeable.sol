// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./proxy/beacon/UpgradeableBeacon.sol";
import "./proxy/beacon/BeaconProxy.sol";
import "./interface/IHogletFactory.sol";
import "./proxy/Clones.sol";
import "./forward/Forward721Upgradeable.sol";

contract HogletFactoryUpgradeable is UpgradeableBeacon, IHogletFactory {

    uint256 public fee;
    uint256 public constant Base = 10000;
    
    address[] public enabledMargins;
    mapping(address => int256) public supportedMargins;
    
    address public override feeCollector;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    address public poolDeployer;
    address public override weth;

    event PoolCreated(
        address indexed nftAddr,
        uint poolType,
        address marginToken,
        uint index
    );

    constructor(){}

    function __FactoryUpgradeable__init(
        address _forward721Imp,
        address[] memory _marginTokens, 
        address _feeCollector,
        uint _fee, 
        address _weth
    ) public initializer {
        __UpgradeableBeacon__init(_forward721Imp);

        poolDeployer = owner();

        enabledMargins.push(address(0));
        supportedMargins[address(0)] = type(int256).min;

        for (uint i = 0; i < _marginTokens.length; i++) {
            supportMargin(_marginTokens[i]);
        }

        feeCollector = _feeCollector;
        require(_fee >= 0 && _fee < Base, "!fee");
        fee = _fee;
        weth = _weth;
    }

    function supportMargin(address _token) public onlyOwner {
        require(_token != address(0), "!0x00");

        require(!ifMarginSupported(_token), "supported already");
        if (uint(supportedMargins[_token]) == 0) {
            enabledMargins.push(_token);
            supportedMargins[_token] = int(enabledMargins.length);
        } else {
            supportedMargins[_token] = -supportedMargins[_token];
        }

    }
    function disableMargin(address _token) external onlyOwner {

        require(ifMarginSupported(_token), "disabled already");

        supportedMargins[_token] = -supportedMargins[_token];

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

    function ifMarginSupported(address _token) public view override returns (bool) {
        return _token == address(0) || supportedMargins[_token] > 0;
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
        require(poolDeployer == address(0) || msg.sender == poolDeployer, "!poolDeployer");
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
            
            
            Forward721Upgradeable(beaconProxyAddr).__Forward721__init(_nftAddr, _poolType, _marginToken);

        } else {
            revert("!support");
        }

        getPair[_nftAddr][_marginToken] = beaconProxyAddr;
        getPair[_marginToken][_nftAddr] = beaconProxyAddr;
        allPairs.push(beaconProxyAddr);

        emit PoolCreated(_nftAddr, _poolType, beaconProxyAddr, allPairs.length);
    }
    
    function setPoolDeployer(address _deployer) external onlyOwner {
        require(owner() == address(0) || msg.sender == owner() || msg.sender == poolDeployer, "!auth");
        poolDeployer = _deployer;
    }

    function pausePools(uint256[] memory _poolIds) external onlyOwner {
        for (uint i = 0; i < _poolIds.length; i++) {
            Forward721Upgradeable(allPairs[_poolIds[i]]).pause();
        }
    }

    function unpausePools(uint256[] memory _poolIds) external onlyOwner {
        for (uint i = 0; i < _poolIds.length; i++) {
            Forward721Upgradeable(allPairs[_poolIds[i]]).unpause();
        }
    }

    function collectFee(address _to, uint256[] memory _poolIds) external onlyOwner {
        for(uint i = 0; i < _poolIds.length; i++) {
            Forward721Upgradeable(allPairs[_poolIds[i]]).collectFee(_to);
        }
    }
    
    function withdrawOther(uint _poolId, address _asset, address _to) external virtual {
        require(msg.sender == owner() || owner() == address(0), "!auth");
        Forward721Upgradeable(allPairs[_poolId]).withdrawOther(_asset, _to);

        
    }

    function version() external virtual override view returns (string memory) {
        return "v1.0";
    }
    
}