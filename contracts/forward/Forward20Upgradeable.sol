// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "../interface/IHedgehogFactory.sol";
import "../interface/IWETH.sol";
import "../interface/IHForwardVault.sol";


contract Forward20Upgradeable is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint;

    address public want;
    address public margin;

    address public fVault;
    address public eth;
    address public weth;

    uint256 public cfee;
    uint256 public ratio;
    bool public paused;
    
    enum OrderState { inactive, active, dead, fill, challenge, unsettle, settle }
    
    // TODO: check following will increase compiling err: stack too deep,:(
    // struct Order {
    //     address buyer;
    //     address seller;
    //     uint256 buyerMargin;
    //     uint256 buyerShare;
    //     uint256 sellerMargin;
    //     uint256 sellerShare;
    //     uint256 forward; // forward amount of want erc20 token
    //     uint256 validTill;
    //     uint256 deliveryPrice;
    //     uint256 deliveryTime;
    //     uint256 challengeTime;
    //     OrderState state;
    //     bool sellerDelivery;
    //     bool buyerDelivery;
    //     address[] takerWhiteList;
    // }

    // Order[] public orders;

    constructor() {}

    function __Forward20Upgradeable__init(

    ) public initializer {
        // init ownership
        __Ownable_init();

        // 
    }
}