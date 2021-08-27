pragma solidity ^0.8.0;


// ERC721
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "./interface/IHedgehogFactory.sol";

import "./Forward721.sol";

contract HedgehogFactory is AccessControlEnumerableUpgradeable, IHedgehogFactory {

    bytes32 public constant DEFAULT_GOV_ROLE = 0x01;

    uint256 public constant Base = 10000;
    
    address[] public supportedCoins;
    mapping(address => int) public enabledCoins;

    uint public makerMargin;
    uint public takerMargin;

    bytes32 public constant ERC721_POOL  = bytes32(uint256(keccak256("ERC721_POOL")) - 1);
    bytes32 public constant ERC1155_POOL = bytes32(uint256(keccak256("ERC1155_POOL")) - 1);
    bytes32 public constant ERC20_POOL   = bytes32(uint256(keccak256("ERC20_POOL")) - 1);
    


    constructor()
    {
        _setupRole(DEFAULT_ADMIN_ROLE, address(0xdead));
    }

    function initialize(
        address[] _liquidationCoins,
        uint _makerMargin, uint _takerMargin
    ) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        supportedCoins.push(address(0x00));
        for (i = 0; i < liquidationCoins.length; i++) {
            supportedCoins.push(liquidationCoins[i]);
            enabledCoins[liquidationCoins[i]] = i + 1;
        }

        makerMargin = _makerMargin;
        takerMargin = _takerMargin;
    }

    function enableCoin(address coin) external {
        require(hasRole(DEFAULT_GOV_ROLE, msg.sender), "!gov");
        require(coin != address(0x00), "!0x00");

        require(!ifCoinEnabled(coin), "enabled");
        if (enabledCoins[coin] == 0) {
            supportedCoins.push(coin);
            enabledCoins[coin] = supportedCoins.length;
        } else {
            enabledCoins[coin] = -enabledCoins[coin];
        }

    }
    function disableCoin(address coin) external {
        require(hasRole(DEFAULT_GOV_ROLE, msg.sender), "!gov");
        require(coin != address(0x00), "!0x00");

        require(ifCoinEnabled(coin), "disabled");

        enabledCoins[coin] = -enabledCoins[coin];

    }

    function ifCoinEnabled(address coin) public view returns (bool) {
        return coin == address(0x00) || enabledCoins[coin] > 0;
    }

    function getMarginRatios() external view returns (uint maker, uint taker, uint base) {
        maker = makerMargin;
        taker = takerMargin;
        base = Base;
    }

    function deployPool(
        address contractAddr,
        uint poolType,
        address liquidationCoin
    ) external {
        if (poolType == 721) {
            address f721 = new Forward721();
            f721.initialize();
        } else {
            revert("!support");
        }
    }

    function upgradePool() external {
        require(hasRole(DEFAULT_GOV_ROLE, msg.sender), "!gov");
        // TODO: upgrade old pool to new pool
    }

    
}