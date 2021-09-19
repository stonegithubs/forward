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
        uint shares;
        if (_deposit && !_isSeller) {
            (uint fee, uint base) = IHogletFactory(factory).getOperationFee();
            shares = _pullMargin(_deliveryPrice.mul(fee.add(base)).div(base), true);
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

    function deliver(uint256 _orderId) external virtual override nonReentrant {
        _onlyNotPaused();
        Order memory order = orders[_orderId];
        require(checkOrderState(_orderId) == OrderState.delivery, "!delivery");
        address sender = msg.sender;
        require(sender == order.seller.addr || sender == order.buyer.addr, "only seller & buyer");

        if (sender == order.seller.addr && !order.seller.delivered) {
            // seller tends to deliver underlyingAssets[_orderId] amount of want tokens
            _pull1155TokensToSelf(underlyingAssets[_orderId].ids, underlyingAssets[_orderId].amounts);
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
        Asset memory asset = underlyingAssets[_orderId];
        if (order.seller.delivered && order.buyer.delivered) {
            // send buyer underlyingAssets[_orderId] amount of want tokens and seller margin
            _push1155TokensFromSelf(order.buyer.addr, asset.ids, asset.amounts);
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
                // return nft to seller
                _push1155TokensFromSelf(order.seller.addr, asset.ids, asset.amounts);
            }
            orders[_orderId].state = OrderState.settled;
            emit Settle(_orderId);
        }
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