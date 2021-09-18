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

    function __Forward721__init(
        address _want,
        uint _poolType,
        address _margin
    ) public initializer {
        __BaseForward__init(_want, _poolType, _margin);
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
        uint shares;
        if (_deposit && !_isSeller) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint p = _deliveryPrice.mul(fee.add(base)).div(base);
            shares = _pullMargin(p, true);
        } else {
            // take margin from msg.sender normally
            shares = _pullMargin(_isSeller ? _sellerMargin : _buyerMargin, true);
        }

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
    function deliver(uint256 _orderId) external virtual override nonReentrant {
        _onlyNotPaused();
        Order memory order = orders[_orderId];
        require(checkOrderState(_orderId) == OrderState.delivery, "!delivery");
        address sender = msg.sender;
        require(sender == order.seller.addr || sender == order.buyer.addr, "only seller & buyer");

        if (sender == order.seller.addr && !order.seller.delivered) {
            // seller tends to deliver nfts
            _multiDeposit721(underlyingAssets[_orderId]);
            orders[_orderId].seller.delivered = true;
            emit Delivery(_orderId, sender);
        }
        if (sender == order.buyer.addr && !order.buyer.delivered) {
            // buyer tends to deliver tokens
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            _pullMargin(
                buyerAmount.sub(
                    order.buyer.share.mul(getPricePerFullShare()).div(1e18)
                ), 
                false /* here we do not farm delivered tokens since they just stay in contract for challenge period at most */
            );  
            orders[_orderId].buyer.delivered = true;
            emit Delivery(_orderId, sender);
        }

        // soft settle means settle if necessary otherwise wait for the counterpart to deliver
        _settle(_orderId, false); 

    }

    /**
    * @dev anybody can invoke this method to end orderId
    * @param _orderId the order msg.sender wants to settle at the final stage
     */
    function settle(uint256 _orderId) external virtual override nonReentrant {
        _onlyNotPaused();
        require(checkOrderState(_orderId) == OrderState.expired, "!expired");
        // challenge time has past, anyone can forcely settle this order 
        _settle(_orderId, true);
    }


    function _settle(uint256 _orderId, bool _forceSettle) internal {
        (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
        
        Order memory order = orders[_orderId];
        // in case both sides delivered
        if (order.seller.delivered && order.buyer.delivered) {
            // send buyer nfts and seller margin
            _multiWithdraw721(underlyingAssets[_orderId], order.buyer.addr);
            
            uint bfee = order.deliveryPrice.mul(fee).div(base);
            // carefully check if there is margin left for buyer in case buyer depositted both margin and deliveryPrice at the very first
            uint bsa /*Buyer Share token Amount*/ = order.buyer.share.mul(getPricePerFullShare()).div(1e18);
            // should send extra farmming profit to buyer
            if (bsa > order.deliveryPrice.add(bfee)) {
                _pushMargin(order.buyer.addr, bsa.sub(order.deliveryPrice).sub(bfee));
            }
            
            // send seller payout
            uint sellerAmount = order.seller.share.mul(getPricePerFullShare()).div(1e18).add(order.deliveryPrice).sub(bfee);
            _pushMargin(order.seller.addr, sellerAmount);
            cfee = cfee.add(bfee.mul(2));
            
            
            orders[_orderId].state = OrderState.settled;
            emit Settle(_orderId);
            return; // must return here
        }
        if (_forceSettle) {
            if (!order.seller.delivered) {
                // blame seller if he/she does not deliver nfts  
                uint sfee = order.seller.margin.mul(fee).div(base);
                cfee = cfee.add(sfee);
                _pushMargin(
                    order.buyer.addr, 
                    /* here we send both buyer and seller's margin to buyer except seller's op fee */
                    order.buyer.share.add(order.seller.share).mul(getPricePerFullShare()).div(1e18).sub(sfee)
                );
            } else if (!order.buyer.delivered) {
                // blame buyer
                uint bfee = order.buyer.margin.mul(fee).div(base);
                cfee = cfee.add(bfee);
                _pushMargin(
                    order.seller.addr,
                    order.seller.share.add(order.buyer.share).mul(getPricePerFullShare()).div(1e18).sub(bfee)
                );

            }
            // return nft (nfts of underlyingAssets[_orderId]) to seller
            _multiWithdraw721(underlyingAssets[_orderId], order.seller.addr);
            orders[_orderId].state = OrderState.settled;
            emit Settle(_orderId);
        }

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