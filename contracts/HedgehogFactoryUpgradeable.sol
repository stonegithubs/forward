// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// ERC721
import "./proxy/beacon/UpgradeableBeacon.sol";
import "./proxy/beacon/BeaconProxy.sol";
import "./interface/IHedgehogFactory.sol";
import "./proxy/Clones.sol";
import "./Forward721Upgradeable.sol";

contract HedgehogFactoryUpgradeable is UpgradeableBeacon, IHedgehogFactory {

    uint256 public fee;
    uint256 public constant Base = 10000;
    
    address[] public supportedCoins;
    mapping(address => int) public enabledCoins;
    
    address public override feeCollector;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PoolCreated(
        address indexed nftAddr,
        uint poolType,
        address liquidationCoin,
        uint index
    );

    constructor()
    {
        transferOwnership(address(0xdead));
    }

    function initialize(
        address _forward721Imp,
        address[] memory _liquidationCoins, 
        address _feeCollector,
        uint _fee
    ) public initializer {
        __UpgradeableBeacon__init(_forward721Imp);


        supportedCoins.push(address(0));
        for (uint i = 0; i < _liquidationCoins.length; i++) {
            supportedCoins.push(_liquidationCoins[i]);
            enabledCoins[_liquidationCoins[i]] = int(i + 1);
        }

        feeCollector = _feeCollector;
        require(_fee >= 0 && _fee < Base, "!fee");
        fee = _fee;
    }

    function enableCoin(address coin) external onlyOwner {
        require(coin != address(0), "!0x00");

        require(!ifCoinEnabled(coin), "enabled");
        if (uint(enabledCoins[coin]) == 0) {
            supportedCoins.push(coin);
            enabledCoins[coin] = int(supportedCoins.length);
        } else {
            enabledCoins[coin] = -enabledCoins[coin];
        }

    }
    function disableCoin(address coin) external onlyOwner {

        require(coin != address(0), "!0x00");

        require(ifCoinEnabled(coin), "disabled");

        enabledCoins[coin] = -enabledCoins[coin];

    }

    function setFee(uint _fee) external onlyOwner {
        require(_fee >= 0 && _fee < Base, "!fee");
        fee = _fee;
    }
    
    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "!feeCollector");
        feeCollector = _feeCollector;
    }


    function ifCoinEnabled(address coin) public view override returns (bool) {
        return coin == address(0) || enabledCoins[coin] > 0;
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
        address _liquidationCoin
    ) external {
        require(getPair[_nftAddr][_liquidationCoin] == address(0), "pool exist"); // single check is sufficient

        address beaconProxyAddr;
        if (_poolType == 721) {
            // Do not use Method 1 to prevent redundant contract deploy for same parameters, 
            //     because it will always succeed with contract account's nonce increasing
            // Method 1: deploy new beacon proxy
            // address beaconProxyAddr = address(new BeaconProxy(address(this), ""));

            // Method 2: 
            bytes32 salt = keccak256(abi.encodePacked(_nftAddr, _poolType, _liquidationCoin));
            beaconProxyAddr = Clones.cloneDeterministic(implementation(), salt);
            
            
            Forward721Upgradeable(beaconProxyAddr).initialize(_nftAddr, _poolType, _liquidationCoin);

        } else {
            revert("!support");
        }

        getPair[_nftAddr][_liquidationCoin] = beaconProxyAddr;
        getPair[_liquidationCoin][_nftAddr] = beaconProxyAddr;

        emit PoolCreated(_nftAddr, _poolType, beaconProxyAddr, allPairs.length);
    }
    
}