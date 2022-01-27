// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// ERC721

import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "./base/BaseForwardUpgradeable.sol";
import "../interface/IHogletFactory.sol";
import "../library/TransferHelper.sol";

contract Forward721Upgradeable is BaseForwardUpgradeable, ERC721HolderUpgradeable {

    // orderId => tokenIds
    struct Asset {
        uint[] amounts;
    }
    mapping(uint => Asset) internal underlyingAssets_;

    function underlyingAssets(uint _orderId) external view returns (uint[] memory) {
        return underlyingAssets_[_orderId].amounts;
    }

    function __Forward721Upgradeable__init(
        address _want,
        uint _poolType,
        address _margin
    ) public initializer {
        __BaseForward__init(_want, _margin);
        require(_poolType == 721, "!721");
    }

    function createOrderFor(
        address _creator,
        uint[] memory _tokenIds, 
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
    ) external returns (uint orderId) {
        _onlyNotPaused();
        // check if msg.sender wants to deposit tokenId nft directly
        if (_deposit && _isSeller) {
            _pull721TokensToSelf(_tokenIds);
        }

        // create order
        orderId = _createOrderFor(
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

        for (uint i = 0; i < _tokenIds.length; i++) {
            underlyingAssets_[orderId].amounts.push(_tokenIds[i]);
        }
    }
    
    /**
    * @dev only maker or taker from orderId's order can invoke this method during challenge period
    * @param _orderId the order msg.sender wants to deliver
     */
    function _pullUnderlyingAssetsToSelf(uint _orderId) internal virtual override {
        _pull721TokensToSelf(underlyingAssets_[_orderId].amounts);
    }

    function _pushUnderlyingAssetsFromSelf(uint _orderId, address _to) internal virtual override {
        _push721FromSelf(underlyingAssets_[_orderId].amounts, _to);
    }
    

    function _onlyNotProtectedTokens(address _asset) internal virtual override view {
        require(_asset != margin, "!margin");
        require(_asset != fVault, "!fVault");
    }


    function _pull721TokensToSelf(uint[] memory _tokenIds) internal {
        for (uint i = 0; i < _tokenIds.length; i++) {
            TransferHelper._pullERC721(want, msg.sender, address(this), _tokenIds[i]);
        }
    }

    function _push721FromSelf(uint[] memory tokenIds, address to) internal {
        for (uint i = 0; i < tokenIds.length; i++) {
            TransferHelper._pushERC721(want, address(this), to, tokenIds[i]);
        }
    }

}