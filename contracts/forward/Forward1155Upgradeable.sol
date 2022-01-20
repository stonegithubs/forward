// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "./base/BaseForwardUpgradeable.sol";
import "../interface/IHogletFactory.sol";
import "../interface/IForwardVault.sol";

contract Forward1155Upgradeable is BaseForwardUpgradeable, ERC1155HolderUpgradeable {
    
    struct Asset {
        uint[] ids;
        uint[] amounts;
    }
    // orderId => Asset, we use map rather than array to save gas
    mapping(uint => Asset) internal underlyingAssets_;

    

    function __Forward1155Upgradeable__init(
        address _want,
        uint _poolType,
        address _margin
    ) public initializer {
        __BaseForward__init(_want, _margin);
        require(_poolType == 1155, "!1155");
    }

    function underlyingAssets(uint _orderId) external view returns (uint[] memory, uint[] memory) {
        Asset memory asset = underlyingAssets_[_orderId];
        return (asset.ids, asset.amounts);
    }

    function createOrderFor(
        address _creator,
        uint[] memory _ids,
        uint[] memory _amounts,
        // uint _orderValidPeriod,
        // uint _deliveryStart,
        // uint _deliveryPeriod,
        uint[3] memory _times,
        // uint _deliveryPrice, 
        // uint _buyerMargin,
        // uint _sellerMargin,
        uint[3] memory _prices,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external {
        _onlyNotPaused();
        require(_ids.length == _amounts.length, "!len");
        // check if msg.sender wants to deposit _underlyingAmount amount of want directly
        if (_deposit && _isSeller) {
            _pull1155TokensToSelf(_ids, _amounts);
        }

        // create order
        _createOrderFor(
            _creator,
            // _orderValidPeriod,
            // _deliveryStart, 
            // _deliveryPeriod,
            _times,
            // _deliveryPrice, 
            // _buyerMargin, 
            // _sellerMargin,
            _prices,
            _takerWhiteList, 
            _deposit, 
            _isSeller
        );

        uint curOrderIndex = ordersLength - 1;
        for (uint i = 0; i < _ids.length; i++) {
            underlyingAssets_[curOrderIndex].ids.push(_ids[i]);
            underlyingAssets_[curOrderIndex].amounts.push(_amounts[i]);
        }
    }

    function _pullUnderlyingAssetsToSelf(uint _orderId) internal virtual override {
        _pull1155TokensToSelf(underlyingAssets_[_orderId].ids, underlyingAssets_[_orderId].amounts);
    }

    function _pushUnderlyingAssetsFromSelf(uint _orderId, address _to) internal virtual override {
        Asset memory asset = underlyingAssets_[_orderId];
        _push1155TokensFromSelf(_to, asset.ids, asset.amounts);
    }

    function _onlyNotProtectedTokens(address _asset) internal virtual override view {
        require(_asset != want, "!want");
        require(_asset != margin, "!margin");
        require(_asset != fVault, "!fVault");
    }

    function _pull1155TokensToSelf(
        uint[] memory _ids,
        uint[] memory _amounts
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
        uint[] memory _ids,
        uint[] memory _amounts
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