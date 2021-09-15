// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// ERC721
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./interface/IHedgehogFactory.sol";
import "./DummyWETH.sol";
import "./interface/IWETH.sol";
import "./interface/IHForwardVault.sol";

contract Forward721Upgradeable is OwnableUpgradeable, ERC721HolderUpgradeable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint;

    address public nftAddr;
    address public marginToken;
    uint public cfee;

    address public forwardVault;
    address public eth; 
    address public weth; 
    uint256 public ratio;

    enum OrderState { inactive, active, dead, fill, challenge, unsettle, settle }
    struct Order {
        address buyer;
        uint buyerMargin;
        uint buyerShare;
        address seller;
        uint sellerMargin;
        uint sellerShare;

        uint256[] tokenIds;
        uint validTill;
        uint deliveryPrice;
        uint deliveryTime;
        uint challengeTime;
        address[] takerWhiteList;
        OrderState state;


        bool sellerDelivery;
        bool buyerDelivery;
    }
    Order[] public orders;

    event CreateOrder(
        uint orderId,
        address maker,
        uint256[] tokenIds,
        uint validTill,
        uint deliveryPrice,
        uint deliveryTime,
        uint challengeTill,
        address[] takerWhiteList,
        bool isSeller
    );
    event TakeOrder(
        uint orderId,
        address taker,
        uint takerMargin
    );

    event Delivery(
        uint orderId,
        address sender
    );

    event Settle(
        uint orderId
    );

    constructor() {}

    function initialize(
        address _nftAddr,
        uint _poolType,
        address _marginToken
    ) public initializer {
        // init ownership
        __Ownable_init();

        
        // check conditions
        IHedgehogFactory factory = IHedgehogFactory(owner());
        require(_poolType == 721, "!721");
        require(factory.ifTokenSupported(_marginToken), "margin token not supported");

        // check parameters
        nftAddr = _nftAddr;
        marginToken = _marginToken;

        weth = DummyWETH.dummyWeth();
        eth = DummyWETH.dummyEth();
        
        ratio = 1e18;
    }
    
    function setForwardVault(address _forwardVault) external onlyOwner {



        if (forwardVault == address(0) && _forwardVault != address(0)) {
            
            // enable vault first time
            address want = IHForwardVault(_forwardVault).want();
            require(want == marginToken || want == weth, "!want");
            // approve margin tokens for new forward vault
            IERC20Upgradeable(want).safeApprove(_forwardVault, 0);
            IERC20Upgradeable(want).safeApprove(_forwardVault, type(uint256).max);

        } else if (forwardVault != address(0) && _forwardVault != address(0)) {
            
            // change vault from one to another one
            address want = IHForwardVault(_forwardVault).want();
            require(want == marginToken || want == weth, "!want");

            uint256 oldShares = IHForwardVault(forwardVault).balanceOf(address(this));
            uint256 tokens = oldShares > 0 ? IHForwardVault(forwardVault).withdraw(oldShares) : 0;

            IERC20Upgradeable(want).safeApprove(forwardVault, 0);
            
            IERC20Upgradeable(want).safeApprove(_forwardVault, 0);
            IERC20Upgradeable(want).safeApprove(_forwardVault, type(uint256).max);

            // ratio = oldShares > 0 ? IHForwardVault(_forwardVault).deposit(tokens).mul(1e18).div(oldShares) : ratio;
            if (oldShares > 0) {
                uint newShares = IHForwardVault(_forwardVault).deposit(tokens);
                ratio = newShares.mul(1e18).div(oldShares);
            }

        } else if (forwardVault != address(0) && _forwardVault == address(0)) {
            
            // disable vault finally
            uint256 oldShares = IHForwardVault(forwardVault).balanceOf(address(this));
            uint256 tokens = oldShares > 0 ? IHForwardVault(forwardVault).withdraw(oldShares) : 0;
            if (marginToken == eth) {
                uint _weth = IWETH(weth).balanceOf(address(this));
                if (_weth > 0) {
                    IWETH(weth).withdraw(_weth);
                }
            }
            // close approval
            IERC20Upgradeable(IHForwardVault(forwardVault).want()).safeApprove(forwardVault, 0);
            // remember the ratio
            if (oldShares > 0) {
                ratio = tokens.mul(1e18).div(oldShares);
            }
            

        } else {
            revert("nonsense");
        }

        forwardVault = _forwardVault;

    }

    function balance() public view returns (uint256) {
        return available().add(balanceSavingsInHVault());
    }

    function available() public view returns (uint256) {
        return marginToken == address(0) ? address(this).balance : IERC20Upgradeable(marginToken).balanceOf(address(this));
    }
    
    function balanceSavingsInHVault() public view returns (uint256) {
        return forwardVault == address(0) ? 0 : IHForwardVault(forwardVault).balanceOf(address(this)).mul(
                                                    IHForwardVault(forwardVault).getPricePerFullShare()
                                                ).div(1e18);
    }

    function getPricePerFullShare() public view returns (uint256) {
        return forwardVault == address(0) ? 
            ratio : 
            ratio.mul(IHForwardVault(forwardVault).getPricePerFullShare()).div(1e18);
    }

    function createOrder(
        uint256[] memory _tokenIds, 
        uint256 _orderValidPeriod, 
        uint256 _deliveryPrice, 
        uint256 _deliveryPeriod,
        uint256 _challengePeriod,
        address[] memory _takerWhiteList,
        uint256 _buyerMargin,
        uint256 _sellerMargin,
        bool _deposit,
        bool _isSeller
    ) external payable {

        // check if msg.sender wants to deposit tokenId nft directly
        if (_deposit && _isSeller) {
            _multiDeposit721(_tokenIds);
        }

        // check if msg.sender wants to deposit tokens directly 
        uint shares;
        if (_deposit && !_isSeller) {
            uint256 p;
            (uint fee, uint base) = IHedgehogFactory(owner()).getOperationFee();
            p = _deliveryPrice.mul(fee.add(base)).div(base);
            shares = _pullToken(msg.sender, p, true);
        } else {
            // take margin from msg.sender normally
            shares = _pullToken(msg.sender, _isSeller ? _sellerMargin : _buyerMargin, true);
        }


        // create order
        _pushOrder(_orderValidPeriod, _deliveryPrice, _deliveryPeriod, _challengePeriod, _buyerMargin, _sellerMargin, _deposit, _isSeller, shares);
        
        uint curOrderIndex = orders.length - 1;
        for (uint i = 0; i < _tokenIds.length; i++) {
            orders[curOrderIndex].tokenIds.push(_tokenIds[i]);
        }
        
        if (_takerWhiteList.length > 0) {
            for (uint i = 0; i < _takerWhiteList.length; i++) {
                orders[curOrderIndex].takerWhiteList.push(_takerWhiteList[i]);
            }
        }
        
        emit CreateOrder(
            curOrderIndex, 
            msg.sender, 
            _tokenIds, 
            orders[curOrderIndex].validTill, 
            orders[curOrderIndex].deliveryPrice, 
            orders[curOrderIndex].deliveryTime, 
            orders[curOrderIndex].challengeTime, 
            _takerWhiteList, 
            _isSeller
        );
    }

    function _pushOrder(
        uint256 _orderValidPeriod, 
        uint256 _deliveryPrice, 
        uint256 _deliveryPeriod,
        uint256 _challengePeriod,
        uint256 _buyerMargin,
        uint256 _sellerMargin,
        bool _deposit,
        bool _isSeller, 
        uint shares
    ) internal {
        uint validTill = _getBlockTimestamp().add(_orderValidPeriod);
        uint deliveryTime = validTill.add(_deliveryPeriod);
        uint challengeTime = deliveryTime.add(_challengePeriod);
        orders.push(
            Order({
                buyer: _isSeller ? address(0) : msg.sender,
                buyerMargin: _buyerMargin,
                buyerShare: _isSeller ? 0 : shares,
                seller: _isSeller ? msg.sender : address(0),
                sellerMargin: _sellerMargin,
                sellerShare: _isSeller ? shares : 0,
                tokenIds: new uint256[](0),
                validTill: validTill,
                deliveryPrice: _deliveryPrice,
                deliveryTime: deliveryTime,
                challengeTime: challengeTime,
                takerWhiteList: new address[](0),
                state: OrderState.active,
                sellerDelivery: _deposit && _isSeller,
                buyerDelivery: _deposit && !_isSeller
            })
        );
    }

    function takeOrder(uint _orderId) external payable {
        address taker = msg.sender;
        // check condition
        require(_orderId < orders.length, "!orderId");
        Order memory order = orders[_orderId];
        require(_getBlockTimestamp() <= order.validTill && order.state == OrderState.active, "!valid & !active"); // okay redundant check
        
        if (order.takerWhiteList.length > 0) {
            require(_withinList(taker, order.takerWhiteList), "!whitelist");
        }

        uint takerMargin = orders[_orderId].seller == address(0) ? orders[_orderId].sellerMargin : orders[_orderId].buyerMargin;
        uint shares = _pullToken(taker, takerMargin, true);

        // change storage
        if (orders[_orderId].buyer == address(0)) {
            orders[_orderId].buyer = taker;
            orders[_orderId].buyerShare = shares;
        } else if (orders[_orderId].seller == address(0)) {
            orders[_orderId].seller = taker;
            orders[_orderId].sellerShare = shares;
        } else {
            revert("bug");
        }
        orders[_orderId].state = OrderState.fill;
        emit TakeOrder(_orderId, taker, takerMargin);
    }
    
    /**
    * @dev only maker or taker from orderId's order can invoke this method during challenge period
    * @param _orderId the order msg.sender wants to deliver
     */
    
    function deliver(uint256 _orderId) external payable {
        Order memory order = orders[_orderId];
        require(checkOrderState(_orderId) == OrderState.challenge, "!challenge");
        address sender = msg.sender;
        require(sender == order.seller || sender == order.buyer, "only seller & buyer");

        if (sender == order.seller && !order.sellerDelivery) {
            // seller tends to deliver nfts
            _multiDeposit721(order.tokenIds);
            orders[_orderId].sellerDelivery = true;
            emit Delivery(_orderId, sender);
        }
        if (sender == order.buyer && !order.buyerDelivery) {
            // buyer tends to deliver tokens
            (uint fee, uint base) = IHedgehogFactory(owner()).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            _pullToken(
                sender, 
                // TODO: check carefully calculate the remaining debt of buyer
                buyerAmount.sub(
                    // forwardVault == address(0) ? order.buyerMargin : /* we will not use buyerMargin since ratio remembers the ratio between share and margin amount */
                    order.buyerShare.mul(getPricePerFullShare()).div(1e18)
                ), 
                false /* here we do not farm delivered tokens since they just stay in contract for challenge period at most */
            );  
            orders[_orderId].buyerDelivery = true;
            emit Delivery(_orderId, sender);
        }

        // soft settle means settle if necessary otherwise wait for the counterpart to deliver
        _settle(_orderId, false); 

    }

    /**
    * @dev anybody can invoke this method to end orderId
    * @param _orderId the order msg.sender wants to settle at the final stage
     */
    function settle(uint256 _orderId) external {

        require(checkOrderState(_orderId) == OrderState.unsettle, "!unsettle");
        // challenge time has past, anyone can forcely settle this order 
        _settle(_orderId, true);
    }


    function _settle(uint256 _orderId, bool _forceSettle) internal {
        (uint fee, uint base) = IHedgehogFactory(owner()).getOperationFee();
        
        Order memory order = orders[_orderId];
        // in case both sides delivered
        if (order.sellerDelivery && order.buyerDelivery) {
            // send buyer nfts and seller margin
            _multiWithdraw721(order.tokenIds, order.buyer);
            
            // carefully check if there is margin left for buyer in case buyer depositted both margin and deliveryPrice at the very first
            uint bsa /*Buyer Share token Amount*/ = order.buyerShare.mul(getPricePerFullShare()).div(1e18);
            // should send extra farmming profit to buyer
            if (bsa > order.deliveryPrice) {
                _pushToken(order.buyer, bsa.sub(order.deliveryPrice));
            }
            
            uint bfee = order.deliveryPrice.mul(fee).div(base);
            // send seller payout
            // uint sellerAmount = order.sellerMargin.add(order.deliveryPrice).sub(bfee);
            uint sellerAmount = order.sellerShare.mul(getPricePerFullShare()).div(1e18).add(order.deliveryPrice).sub(bfee);
            _pushToken(order.seller, sellerAmount);
            cfee = cfee.add(bfee.mul(2));

            orders[_orderId].state = OrderState.settle;
            emit Settle(_orderId);
            return; // must return here
        }
        if (_forceSettle) {
            if (!order.sellerDelivery) {
                // blame seller if he/she does not deliver nfts  
                uint sfee = order.sellerMargin.mul(fee).div(base);
                cfee = cfee.add(sfee);
                _pushToken(
                    order.buyer, 
                    /* here we send both buyer and seller's margin to buyer except seller's op fee */
                    order.buyerShare.add(order.sellerShare).mul(getPricePerFullShare()).div(1e18).sub(sfee)
                );
            } else {
                // blame buyer
                uint bfee = order.buyerMargin.mul(fee).div(base);
                cfee = cfee.add(bfee);
                _pushToken(
                    order.seller,
                    order.sellerShare.add(order.buyerShare).mul(getPricePerFullShare()).div(1e18).sub(bfee)
                );

            }
            orders[_orderId].state = OrderState.settle;
            emit Settle(_orderId);
        }

    }
    
    /**
     * @dev return order state based on orderId
     * @param _orderId order index whose state to be checked.
     * @return 
            0: inactive, or not exist
            1: active, 
            2: order is dead, 
            3: order is filled, 
            4: order is being challenged between maker and taker,
            5: challenge ended, yet not settled
            6: order has been successfully settled
     */
    function checkOrderState(uint _orderId) public view returns (OrderState) {
        Order memory order = orders[_orderId];
        if (order.validTill == 0 ) return OrderState.inactive;
        uint time = _getBlockTimestamp();
        if (time <= order.validTill) return OrderState.active;
        if (order.buyer == address(0) || order.seller == address(0)) return OrderState.dead;
        if (time <= order.deliveryTime) return OrderState.fill;
        if (time <= order.challengeTime) return OrderState.challenge;
        if (order.state != OrderState.settle) return OrderState.unsettle;
        return OrderState.settle;
    }

    function ordersLength() external view returns (uint) {
        return orders.length;
    }

    function collectFee(address _to) external {
        address factory = owner();
        address feeCollector = IHedgehogFactory(factory).feeCollector();
        require(msg.sender != factory || msg.sender == feeCollector, "!auth");
        _pushToken(_to, cfee);
        cfee = 0;
    }

    function _pullToken(address usr, uint amount, bool farm) internal returns (uint256 shares) {
        if (marginToken == eth) {
            require(msg.value >= amount, "!margin"); // don't send more ether, won't pay you back
            // if vault exists, chagne ether to weth 
            if (forwardVault != address(0)) {
                IWETH(weth).deposit{value: msg.value}();
            }
        } else {
            uint mtOld = IERC20Upgradeable(marginToken).balanceOf(address(this));
            IERC20Upgradeable(marginToken).safeTransferFrom(usr, address(this), amount);
            uint mtNew = IERC20Upgradeable(marginToken).balanceOf(address(this));
            require(mtNew.sub(mtOld) == amount, "!support taxed token");
        }

        // TODO: check if giving amount to shares is correct when empty forwardVault
        shares = forwardVault != address(0) && farm ? 
                    // IHForwardVault(forwardVault).deposit(amount).mul(IHForwardVault(forwardVault).getPricePerFullShare()).div(getPricePerFullShare())
                    IHForwardVault(forwardVault).deposit(amount).mul(1e18).div(ratio) /* current line equals above line */
                    :
                    amount.mul(1e18).div(getPricePerFullShare());


    }

    function _pushToken(address usr, uint amount) internal {
        // check if balance not enough, if not, withdraw from vault
        uint ava = available();
        if (ava < amount && forwardVault != address(0)) {
            IHForwardVault(forwardVault).withdraw(amount.sub(ava));
        }

        amount = marginToken == eth ? IWETH(weth).balanceOf(address(this)).add(available()) : available();
        
        if (marginToken == eth) {
            IWETH(weth).withdraw(IWETH(weth).balanceOf(address(this)));
            payable(usr).transfer(amount);

        } else {
            IERC20Upgradeable(marginToken).safeTransfer(usr, amount);
        }
    }

    function _multiDeposit721(uint256[] memory _tokenIds) internal {
        for (uint i = 0; i < _tokenIds.length; i++) {
            _deposit721(_tokenIds[i]);
        }
    }

    function _deposit721(uint256 _tokenId) internal {

        _pullERC721(nftAddr, _tokenId);
        
    }

    function _multiWithdraw721(uint256[] memory tokenIds, address to) internal {
        for (uint i = 0; i < tokenIds.length; i++) {
            _withdraw721(tokenIds[i], to);
        }
    }

    function _withdraw721(uint256 tokenId, address to) internal {
        _pushERC721(nftAddr, to, tokenId);
    }

    function _withinList(address addr, address[] memory list) internal pure returns (bool) {
        for (uint i = 0; i < list.length; i++) {
            if (addr == list[i]) {
                return true;
            }
        }
        return false;
    }

    
    function _getBlockTimestamp() internal view returns (uint) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
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

    function version() external virtual view returns (string memory) {
        return "v1.0";
    }

}