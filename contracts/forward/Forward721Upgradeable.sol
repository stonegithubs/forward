// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// ERC721
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./base/BaseForwardUpgradeable.sol";
import "../interface/IHogletFactory.sol";

contract Forward721Upgradeable is BaseForwardUpgradeable, ERC721HolderUpgradeable {

    using SafeMathUpgradeable for uint256;

    // orderId => tokenIds
    mapping(uint256 => uint256[]) underlyingAssets;

    function __Forward721Upgradeable__init(
        address _want,
        uint _poolType,
        address _margin
    ) public initializer {
        __BaseForward__init(_want, _margin);
        require(_poolType == 721, "!721");
    }

    function createOrder(
        uint256[] memory _tokenIds, 
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
        // check if msg.sender wants to deposit tokenId nft directly
        if (_deposit && _isSeller) {
            _multiDeposit721(_tokenIds);
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
        uint curOrderIndex = orders.length - 1;
        for (uint i = 0; i < _tokenIds.length; i++) {
            underlyingAssets[curOrderIndex].push(_tokenIds[i]);
        }
        
    }

 
    /**
     * @dev only maker or taker from orderId's order be taken as _payer of this method during delivery period, 
     *       _payer needs to pay the returned margin token to deliver _orderId's order
     * @param _orderId the order for which we want to check _payers needs to pay at delivery
     * @param _payer the address which needs to pay for _orderId at delivery
     * @return price which _payer needs to pay for _orderId for delivery, here means nft numbers if _payer is seller
     */
    function getAmountToDeliver(uint256 _orderId, address _payer) external virtual override view returns (uint256 price) {
        Order memory order = orders[_orderId];
        
        if (_payer == order.buyer.addr && !order.buyer.delivered) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            price = buyerAmount.sub(
                        order.buyer.share.mul(getPricePerFullShare()).div(1e18)
                    );
        }
        if (_payer == order.seller.addr && !order.seller.delivered) {
            uint paid = 0;
            for(uint i = 0; i < underlyingAssets[_orderId].length; i++) {
                if (IERC721Upgradeable(want).ownerOf(underlyingAssets[_orderId][i]) == address(this)) {
                    paid++;
                }
            }
            price = underlyingAssets[_orderId].length.sub(paid);
        }
    }

    
    
    /**
    * @dev only maker or taker from orderId's order can invoke this method during challenge period
    * @param _orderId the order msg.sender wants to deliver
     */
    function _pullUnderlyingAssetsToSelf(uint256 _orderId) internal virtual override {
        _multiDeposit721(underlyingAssets[_orderId]);
    }

    function _pushUnderingAssetsFromSelf(uint256 _orderId, address _to) internal virtual override {
        _multiWithdraw721(underlyingAssets[_orderId], _to);
    }
    

    function _onlyNotProtectedTokens(address _asset) internal virtual override view {
        require(_asset != margin, "!margin");
        require(_asset != fVault, "!fVault");
    }


    function _multiDeposit721(uint256[] memory _tokenIds) internal {
        for (uint i = 0; i < _tokenIds.length; i++) {
            _pullERC721(want, _tokenIds[i]);
        }
    }

    function _multiWithdraw721(uint256[] memory tokenIds, address to) internal {
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