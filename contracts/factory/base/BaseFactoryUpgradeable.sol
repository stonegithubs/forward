// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../proxy/beacon/UpgradeableBeacon.sol";
import "../../proxy/beacon/BeaconProxy.sol";
import "../../interface/IHogletFactory.sol";
import "../../interface/IBaseForward.sol";
import "../../proxy/Clones.sol";
import "../../forward/Forward721Upgradeable.sol";
import "../../forward/Forward20Upgradeable.sol";
import "../../forward/Forward1155Upgradeable.sol";

abstract contract BaseFactoryUpgradeable is UpgradeableBeacon, IHogletFactory {

    uint256 public fee;
    uint256 public constant base = 10000;
    
    address[] public enabledMargins;
    mapping(address => int256) public supportedMargins;
    
    address public override feeCollector;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    address public poolDeployer;

    // only for emergency only if forward721, forward20, forward1155 is attacked
    bool public paused; 

    uint public orderValidPeriod;
    uint public deliveryPeriod;

    event PoolCreated(
        address indexed nftAddr,
        address margin,
        uint poolType,
        address marginToken,
        uint index
    );

    constructor(){}

    function __FactoryUpgradeable__init(
        address _forwardImp,
        address[] memory _margins, 
        address _feeCollector,
        uint _fee
    ) public initializer {
        __UpgradeableBeacon__init(_forwardImp);

        poolDeployer = owner();

        enabledMargins.push(address(0));
        supportedMargins[address(0)] = type(int256).min;

        for (uint i = 0; i < _margins.length; i++) {
            supportMargin(_margins[i]);
        }

        feeCollector = _feeCollector;
        require(_fee >= 0 && _fee < base, "!fee");
        fee = _fee;

        orderValidPeriod = 7 days;
        deliveryPeriod = 12 hours;

    }

    function supportMargin(address _token) public virtual onlyOwner {
        require(_token != address(0), "!0x00");

        require(!ifMarginSupported(_token), "supported already");
        if (uint(supportedMargins[_token]) == 0) {
            enabledMargins.push(_token);
            supportedMargins[_token] = int(enabledMargins.length);
        } else {
            supportedMargins[_token] = -supportedMargins[_token];
        }

    }
    function disableMargin(address _token) external virtual onlyOwner {

        require(ifMarginSupported(_token), "disabled already");

        supportedMargins[_token] = -supportedMargins[_token];

    }

    function setFee(uint _fee) external virtual onlyOwner {
        require(_fee >= 0 && _fee < base, "!fee");
        fee = _fee;
    }
    
    function setFeeCollector(address _feeCollector) external virtual onlyOwner {
        require(_feeCollector != address(0), "!feeCollector");
        feeCollector = _feeCollector;
    }

    function setPeriods(uint _orderValidPeriod, uint _deliveryPeriod) external virtual onlyOwner {
        orderValidPeriod = _orderValidPeriod;
        deliveryPeriod = _deliveryPeriod;
    }

    function setForwardVault(uint256 _poolId, address _forwardVault) external virtual onlyOwner {
        IBaseForward(allPairs[_poolId]).setForwardVault(_forwardVault);
    }

    function ifMarginSupported(address _token) public view virtual override returns (bool) {
        return _token == address(0) || supportedMargins[_token] > 0;
    }

    function getOperationFee() external view virtual override returns (uint, uint) {
        return (fee, base);
    }

    function getPeriods() external view virtual override returns (uint, uint) {
        return (orderValidPeriod, deliveryPeriod);
    }

    function allPairsLength() external virtual view returns (uint) {
        return allPairs.length;
    }

    function deployPool(
        address _asset,
        uint _poolType,
        address _margin
    ) external virtual {
        require(poolDeployer == address(0) || msg.sender == poolDeployer, "!poolDeployer");
        require(getPair[_asset][_margin] == address(0), "pool exist"); // single check is sufficient
        require(_margin != address(0), "ether as margin not support");
        
        // if (_poolType == 721) {
        //     // Do use Method 1 since when we upgrade the imp, all the pairs' logic will follow the new one
        //     // Method 1: deploy new beacon proxy
        //     address beaconProxyAddr = address(new BeaconProxy(address(this), ""));

        //     // // Method 2: Do NOT use this method since we need to upgrade pairs logic one by one
        //     // bytes32 salt = keccak256(abi.encodePacked(_asset, _poolType, _margin));
        //     // beaconProxyAddr = Clones.cloneDeterministic(implementation(), salt);
            
        //     Forward721Upgradeable(beaconProxyAddr).__Forward721__init(_asset, _poolType, _margin);

        // } else if (_poolType == 20) {
        //     revert("!support");
        // } else if (_poolType == 1155) {

        // }
        address beaconProxyAddr = _deployPool(_asset, _poolType, _margin);

        allPairs.push(beaconProxyAddr);

        emit PoolCreated(_asset, _margin, _poolType, beaconProxyAddr, allPairs.length);
    }

    function _deployPool(
         address _asset,
        uint _poolType,
        address _margin
    ) internal virtual returns (address);
    
    function setPoolDeployer(address _deployer) external virtual {
        require(owner() == address(0) || msg.sender == owner() || msg.sender == poolDeployer, "!auth");
        poolDeployer = _deployer;
    }

    function pausePools(uint256[] memory _poolIds) external virtual onlyOwner {
        for (uint i = 0; i < _poolIds.length; i++) {
            Forward721Upgradeable(allPairs[_poolIds[i]]).pause();
        }
    }

    function unpausePools(uint256[] memory _poolIds) external virtual onlyOwner {
        for (uint i = 0; i < _poolIds.length; i++) {
            Forward721Upgradeable(allPairs[_poolIds[i]]).unpause();
        }
    }

    function collectFee(address _to, uint256[] memory _poolIds) external virtual onlyOwner {
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

    /****************** For Emergency Only Begin *********************/
    // here we override UpgradeableBeacon's implementation 
    // in case forward is under attack
    function implementation() public view virtual override(UpgradeableBeacon, IBeacon) returns (address) {
        require(!paused, "paused");
        return super.implementation();
    }

    // when owner invoke pause, all the created forward contracts should stop working
    function pause() external virtual onlyOwner {
        paused = true;
    }

    function unpause() external virtual onlyOwner {
        paused = false;
    }
    
}