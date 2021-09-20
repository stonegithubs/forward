// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
        uint256[] memory _ids,
        uint256[] memory _amounts,
        uint _orderValidPeriod, 
        uint _nowToDeliverPeriod,
        uint _deliveryPeriod,
        uint256 _deliveryPrice,
        uint256 _buyerMargin,
        uint256 _sellerMargin,
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

        // check if msg.sender wants to deposit tokens directly 
        uint shares = _pullMargin(
            _deliveryPrice, 
            _buyerMargin,
            _sellerMargin,
            _deposit, 
            _isSeller
        );

        // create order
        _createOrder(
            _orderValidPeriod, 
            _nowToDeliverPeriod, 
            _deliveryPeriod, 
            _deliveryPrice, 
            _buyerMargin, 
            _sellerMargin,
            _takerWhiteList, 
            _deposit, 
            _isSeller, 
            shares
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

    function getAmountToDeliver(uint256 _orderId, address _payer) external virtual override view returns (uint256 price) {
        Order memory order = orders[_orderId];        
        if (_payer == order.buyer.addr && !order.buyer.delivered) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            price = buyerAmount.sub(
                        order.buyer.share.mul(getPricePerFullShare()).div(1e18)
                    );
        }
        if (_payer == order.seller.addr) {
            price = order.seller.delivered ? 0 : 1; // here we define 1 as the status of not deliveried
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