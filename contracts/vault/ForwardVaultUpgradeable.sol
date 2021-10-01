// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../interface/IYearnYVault.sol";

contract ForwardVaultUpgradeable is ERC20Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint;

    IYearnYVault public yVault;
    IERC20Upgradeable public want;
    
    uint public min;
    uint public tolerance; // rebase tolerance for suitable
    uint public constant max = 10000;

    address public governance;
    
    constructor() {}

    function __ForwardVaultUpgradeable_init(
        address _want,
        address _yVault,
        address _governance,
        uint _min,
        uint _tolerance
    ) public initializer {
        __ERC20_init(
            string(abi.encodePacked("hoglet forward vault ", ERC20Upgradeable(_want).name())),
            string(abi.encodePacked("hfv ", ERC20Upgradeable(_want).symbol()))
        );
        want = IERC20Upgradeable(_want);
        governance = _governance;
        yVault = IYearnYVault(_yVault);
        want.safeApprove(_yVault, type(uint).max);
        require(_min < max && _tolerance < max, "!min or !tolerance");
        min = _min;
        tolerance = _tolerance;
    }

    function balance() public view returns (uint) {
        return want.balanceOf(address(this)).add(
            balanceSavingsInYVault()
        );
    }
    function balanceSavingsInYVault() public view returns (uint) {
        return yVault.balanceOf(address(this)).mul(yVault.getPricePerFullShare()).div(1e18);
    }

    function setMinTolerance(uint _min, uint _tolerance) public {
        require(msg.sender == governance, "!governance");
        require(_min < max, "!min");
        require(_tolerance < max, "!tolerance");
        if (_min != 0) {
            min = _min;
        }
        if (_tolerance != 0) {
            tolerance = _tolerance;
        }
    }
    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    // suitable for farming on yearn.finance
    function suitable() public view returns (uint) {
        return balance().mul(min).div(max);
    }


    function rebase() public {
        uint _real = balanceSavingsInYVault();
        uint _suit = suitable();
        uint _diff = _real < _suit ? _suit.sub(_real) : _real.sub(_suit);
        require(_diff >= _suit.mul(tolerance).div(max), "!diff");
        if (_real < _suit) {
            yVault.deposit(_diff);
            // TODO: check if invoking yVault.earn() is necessary based on its historistal frequency
            yVault.earn();
        } else {
            yVault.withdraw(_diff.mul(1e18).div(yVault.getPricePerFullShare()));
        }
    }

    function deposit(uint _amount) public returns (uint) {
        uint _pool = balance();
        uint _before = want.balanceOf(address(this));
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = want.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
        return shares;
    }

    function depositAll() external returns (uint) {
        return deposit(want.balanceOf(msg.sender));
    }
    

    function withdraw(uint _shares) public returns (uint) {
        uint r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint b = want.balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b);
            uint _wshare = _withdraw.mul(1e18).div(yVault.getPricePerFullShare());
            yVault.withdraw(_wshare);
            uint _after = want.balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        want.safeTransfer(msg.sender, r);
        return r;
    }

    function withdrawAll() external returns (uint) {
        return withdraw(balanceOf(msg.sender));
    }

    function getPricePerFullShare() public view returns (uint) {
        uint supply = totalSupply();
        return supply == 0 ? 1e18 : balance().mul(1e18).div(supply);
    }

    function _onlyNotProtectedTokens(address _asset) internal view {
        require(_asset != address(want), "!want");
        require(_asset != address(yVault), "!ytoken");
    }

    function withdrawOther(address _asset, address _to) external virtual {
        require(msg.sender == governance, "!gov");
        _onlyNotProtectedTokens(_asset);
        IERC20Upgradeable(_asset).safeTransfer(_to, IERC20Upgradeable(_asset).balanceOf(address(this)));
    }

    function version() external virtual view returns (string memory) {
        return "v1.0";
    }
}

