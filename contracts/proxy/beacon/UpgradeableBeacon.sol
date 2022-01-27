// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IBeacon.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

/**
 * @dev This contract is used in conjunction with one or more instances of {BeaconProxy} to determine their
 * implementation contract, which is where they will delegate all function calls.
 *
 * An owner is able to change the implementation the beacon points to, thus upgrading the proxies that use this beacon.
 */
 // Notice: dev changed Ownable into OwnableUpgradeable
contract UpgradeableBeacon is IBeacon, OwnableUpgradeable {
    address private _implementation;

    /**
     * @dev Emitted when the implementation returned by the beacon is changed.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Sets the address of the initial implementation, and the deployer account as the owner who can upgrade the
     * beacon.
     */
    // constructor(address implementation_) {
    //     _setImplementation(implementation_);
    // }
    // Notice: dev changed construtor into init
    function __UpgradeableBeacon__init(address implementation_) public initializer {
        __Ownable_init();
        _setChildImplementation(implementation_);
    }


    /**
     * @dev Returns the current implementation address.
     */
    function childImplementation() public view virtual override returns (address) {
        return _implementation;
    }

    /**
     * @dev Upgrades the beacon to a new implementation.
     *
     * Emits an {Upgraded} event.
     *
     * Requirements:
     *
     * - msg.sender must be the owner of the contract.
     * - `newChildImplementation` must be a contract.
     */
    function upgradeChildTo(address newChildImplementation) public virtual onlyOwner {
        _setChildImplementation(newChildImplementation);
        emit Upgraded(newChildImplementation);
    }

    /**
     * @dev Sets the implementation contract address for this beacon
     *
     * Requirements:
     *
     * - `newChildImplementation` must be a contract.
     */
    function _setChildImplementation(address newChildImplementation) private {
        require(AddressUpgradeable.isContract(newChildImplementation), "UpgradeableBeacon: child implementation is not a contract");
        _implementation = newChildImplementation;
    }
}
