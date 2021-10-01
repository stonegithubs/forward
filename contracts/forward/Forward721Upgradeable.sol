// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// ERC721
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "./base/BaseForwardUpgradeable.sol";
import "../interface/IHogletFactory.sol";

contract Forward721Upgradeable is BaseForwardUpgradeable, ERC721HolderUpgradeable {

    // orderId => tokenIds
    mapping(uint => uint[]) public underlyingAssets;

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
        uint[] memory _times,
        // uint _deliveryPrice, 
        // uint _buyerMargin,
        // uint _sellerMargin,
        uint[] memory _prices,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external {
        _onlyNotPaused();
        // check if msg.sender wants to deposit tokenId nft directly
        if (_deposit && _isSeller) {
            _pull721TokensToSelf(_tokenIds);
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
        for (uint i = 0; i < _tokenIds.length; i++) {
            underlyingAssets[curOrderIndex].push(_tokenIds[i]);
        }
        
    }
    
    /**
    * @dev only maker or taker from orderId's order can invoke this method during challenge period
    * @param _orderId the order msg.sender wants to deliver
     */
    function _pullUnderlyingAssetsToSelf(uint _orderId) internal virtual override {
        _pull721TokensToSelf(underlyingAssets[_orderId]);
    }

    function _pushUnderlyingAssetsFromSelf(uint _orderId, address _to) internal virtual override {
        _push721FromSelf(underlyingAssets[_orderId], _to);
    }
    

    function _onlyNotProtectedTokens(address _asset) internal virtual override view {
        require(_asset != margin, "!margin");
        require(_asset != fVault, "!fVault");
    }


    function _pull721TokensToSelf(uint[] memory _tokenIds) internal {
        for (uint i = 0; i < _tokenIds.length; i++) {
            _pullERC721(want, _tokenIds[i]);
        }
    }

    function _push721FromSelf(uint[] memory tokenIds, address to) internal {
        for (uint i = 0; i < tokenIds.length; i++) {
            _pushERC721(want, to, tokenIds[i]);
        }
    }

    // Non-standard ERC721 projects:  https://docs.niftex.org/general/supported-nfts
    // implementation refers to: https://github.com/NFTX-project/nftx-protocol-v2/blob/master/contracts/solidity/NFTXVaultUpgradeable.sol#L444
    // TODO: improve implemention to include more non-standard ERC721 impl and change standard to safe-(invoke) way
    function _pushERC721(address assetAddr, address to, uint256 tokenId) internal virtual {
        address kitties = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
        address punks = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
        bytes memory data;
        if (assetAddr == kitties) {
            // Changed in v1.0.4.
            data = abi.encodeWithSignature("transfer(address,uint256)", to, tokenId);
        } else if (assetAddr == punks) {
            // CryptoPunks.
            data = abi.encodeWithSignature("transferPunk(address,uint256)", to, tokenId);
        } else {
            // Default.
            data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(this), to, tokenId);
        }
        (bool success,) = address(assetAddr).call(data);
        require(success);
    }

    function _pullERC721(address assetAddr, uint256 tokenId) internal virtual {
        address kitties = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
        address punks = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
        bytes memory data;
        if (assetAddr == kitties) {
            // Cryptokitties.
            data = abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), tokenId);
        } else if (assetAddr == punks) {
            // CryptoPunks.
            // Fix here for frontrun attack. Added in v1.0.2.
            bytes memory punkIndexToAddress = abi.encodeWithSignature("punkIndexToAddress(uint256)", tokenId);
            (bool checkSuccess, bytes memory result) = address(assetAddr).staticcall(punkIndexToAddress);
            (address owner) = abi.decode(result, (address));
            require(checkSuccess && owner == msg.sender, "Not the owner");
            data = abi.encodeWithSignature("buyPunk(uint256)", tokenId);
        } else {
            // Default.
            data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", msg.sender, address(this), tokenId);
        }
        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success, string(resultData));
    }



}