// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

pragma abicoder v2;


import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./base/BaseForwardUpgradeable.sol";
import "../interface/IHogletFactory.sol";
import "../interface/IForwardVault.sol";

contract Forward1155Upgradeable is BaseForwardUpgradeable {
    using SafeMathUpgradeable for uint256;
    
    struct Asset {
        uint256[] ids;
        uint256[] amounts;
    }
    // orderId => Asset
    Asset[] internal underlyingAssets;

    

    function __Forward1155Upgradeable__init(
        address _want,
        uint _poolType,
        address _margin
    ) public initializer {
        __BaseForward__init(_want, _margin);
        require(_poolType == 1155, "!1155");
    }

    function viewUnderlyingAssets(uint256 _orderId) external view returns (uint256[] memory, uint256[] memory) {
        Asset memory asset = underlyingAssets[_orderId];
        return (asset.ids, asset.amounts);
    }

    function createOrder(
        address _creator,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        // uint _orderValidPeriod, 
        // uint _nowToDeliverPeriod,
        // uint _deliveryPeriod,
        // uint256 _deliveryPrice,
        // uint256 _buyerMargin,
        // uint256 _sellerMargin,
        uint256[6] memory _uintData,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external nonReentrant {
        _onlyNotPaused();
        require(_ids.length == _amounts.length, "!len");
        // check if msg.sender wants to deposit _underlyingAmount amount of want directly
        if (_deposit && _isSeller) {
            _pull1155TokensToSelf(_ids, _amounts);
        }

        // create order
        _createOrder(
            _creator,
            // _orderValidPeriod, 
            // _nowToDeliverPeriod, 
            // _deliveryPeriod, 
            // _deliveryPrice, 
            // _buyerMargin, 
            // _sellerMargin,
            _uintData,
            _takerWhiteList, 
            _deposit, 
            _isSeller
        );
        underlyingAssets.push(
            Asset({
                ids: new uint256[](0),
                amounts: new uint256[](0)
            })
        );
        for (uint i = 0; i < _ids.length; i++) {
            underlyingAssets[underlyingAssets.length - 1].ids.push(_ids[i]);
            underlyingAssets[underlyingAssets.length - 1].amounts.push(_amounts[i]);
        }
    }

    function _pullUnderlyingAssetsToSelf(uint256 _orderId) internal virtual override {
        _pull1155TokensToSelf(underlyingAssets[_orderId].ids, underlyingAssets[_orderId].amounts);
    }

    function _pushUnderingAssetsFromSelf(uint256 _orderId, address _to) internal virtual override {
        Asset memory asset = underlyingAssets[_orderId];
        _push1155TokensFromSelf(_to, asset.ids, asset.amounts);
    }

    function _onlyNotProtectedTokens(address _asset) internal virtual override view {
        require(_asset != want, "!want");
        require(_asset != margin, "!margin");
        require(_asset != fVault, "!fVault");
    }

    function _pull1155TokensToSelf(
        uint256[] memory _ids,
        uint256[] memory _amounts
    ) internal {
        IERC1155Upgradeable(want).safeBatchTransferFrom(
            msg.sender, 
            address(this),
            _ids,
            _amounts,
            ""
        );
    }
    
    function _push1155TokensFromSelf(
        address _to,
        uint256[] memory _ids,
        uint256[] memory _amounts
    ) internal {
        IERC1155Upgradeable(want).safeBatchTransferFrom(
            address(this),
            _to, 
            _ids,
            _amounts,
            ""
        );
    }

}