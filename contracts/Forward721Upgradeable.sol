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

    enum OrderState { active, dead, fill, challenge, unsettle, settle }
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

    constructor() {
        transferOwnership(address(0xdead));

    }

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
        require(factory.ifTokenSupported(marginToken), "margin token not supported");

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

            uint256 oldShares = IHForwardVault(forwardVault).balanceOf(address(this));
            uint256 tokens = oldShares > 0 ? IHForwardVault(forwardVault).withdraw(oldShares) : 0;
            if (marginToken == eth) {
                uint _weth = IWETH(weth).balanceOf(address(this));
                if (_weth > 0) {
                    IWETH(weth).withdraw(_weth);
                }
            }
            IERC20Upgradeable(want).safeApprove(forwardVault, 0);
            ratio = oldShares > 0 ? tokens.mul(1e18).div(oldShares) : ratio;

            require(want == marginToken || want == weth, "!want");
            IERC20Upgradeable(want).safeApprove(_forwardVault, 0);
            IERC20Upgradeable(want).safeApprove(_forwardVault, type(uint256).max);


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
            ratio = oldShares > 0 ? tokens.mul(1e18).div(oldShares) : ratio;

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
        uint256[] calldata tokenIds, 
        uint256 orderValidPeriod, 
        uint256 deliveryPrice, 
        uint256 deliveryTime,
        uint256 challengePeriod,
        address[] calldata takerWhiteList,
        bool deposit,
        uint256 buyerMargin,
        uint256 sellerMargin,
        bool isSeller
    ) external payable {

        // check if msg.sender wants to deposit tokenId nft directly
        if (deposit && isSeller) {
            _multiDeposit721(tokenIds);
        }

        // check if msg.sender wants to deposit tokens directly 
        uint shares;
        if (deposit && !isSeller) {
            uint256 p;
            {
                (uint fee, uint base) = IHedgehogFactory(owner()).getOperationFee();
                p = deliveryPrice.mul(fee.add(base)).div(base);
            }
            shares = _pullToken(msg.sender, p, true);
        } else {
            // take margin from msg.sender normally
            shares = _pullToken(msg.sender, isSeller ? sellerMargin : buyerMargin, true);
        }


        // create order
        orders.push(
            Order({
                buyer: isSeller ? address(0) : msg.sender,
                buyerMargin: buyerMargin,
                buyerShare: isSeller ? 0 : shares,
                seller: isSeller ? msg.sender : address(0),
                sellerMargin: sellerMargin,
                sellerShare: isSeller ? shares : 0,
                tokenIds: new uint256[](0),
                validTill: _getBlockTimestamp() + orderValidPeriod,
                deliveryPrice: deliveryPrice,
                deliveryTime: deliveryTime,
                challengeTime: deliveryTime + challengePeriod,
                takerWhiteList: new address[](0),
                state: OrderState.active,
                sellerDelivery: deposit && isSeller,
                buyerDelivery: deposit && !isSeller
            })
        );
        
        uint curOrderIndex = orders.length - 1;
        for (uint i = 0; i < tokenIds.length; i++) {
            orders[curOrderIndex].tokenIds.push(tokenIds[i]);
        }
        
        if (takerWhiteList.length > 0) {
            for (uint i = 0; i < takerWhiteList.length; i++) {
                orders[curOrderIndex].takerWhiteList.push(takerWhiteList[i]);
            }
        }
        
        emit CreateOrder(orders.length - 1, msg.sender, tokenIds, orders[curOrderIndex].validTill, orders[curOrderIndex].deliveryPrice, orders[curOrderIndex].deliveryTime, orders[curOrderIndex].challengeTime, takerWhiteList, isSeller);
    }


    function takeOrder(uint orderId) external payable {
        address taker = msg.sender;
        // check condition
        require(orderId < orders.length, "!orderId");
        Order memory order = orders[orderId];
        require(_getBlockTimestamp() <= order.validTill && order.state == OrderState.active, "!valid & !active"); // okay redundant check
        
        if (order.takerWhiteList.length > 0) {
            require(_withinList(taker, order.takerWhiteList), "!whitelist");
        }

        uint takerMargin = orders[orderId].seller == address(0) ? orders[orderId].sellerMargin : orders[orderId].buyerMargin;
        uint shares = _pullToken(taker, takerMargin, true);

        // change storage
        if (orders[orderId].buyer == address(0)) {
            orders[orderId].buyer = taker;
            orders[orderId].buyerShare = shares;
        } else {
            orders[orderId].seller = taker;
            orders[orderId].sellerShare = shares;
        }
        orders[orderId].state = OrderState.fill;
        emit TakeOrder(orderId, taker, takerMargin);
    }
    
    /**
    * @dev only maker or taker from orderId's order can invoke this method during challenge period
    * @param orderId the order msg.sender wants to deliver
     */
    
    function deliver(uint256 orderId) external payable {
        Order memory order = orders[orderId];
        require(checkOrderState(orderId) == uint(OrderState.challenge), "!challenge");
        address sender = msg.sender;
        require(sender == order.seller || sender == order.buyer, "only seller & buyer");

        if (sender == order.seller && !order.sellerDelivery) {
            // seller tends to deliver nfts
            _multiDeposit721(order.tokenIds);
            orders[orderId].sellerDelivery = true;
            emit Delivery(orderId, sender);
        }
        if (sender == order.buyer && !order.buyerDelivery) {
            // buyer tends to deliver tokens
            (uint fee, uint base) = IHedgehogFactory(owner()).getOperationFee();
            uint buyerAmount = order.deliveryPrice.mul(fee.add(base)).div(base);
            _pullToken(
                sender, 
                // TODO: check carefully calculate the remaining debt of buyer
                buyerAmount.sub(
                    forwardVault == address(0) ? order.buyerMargin :
                    order.buyerShare.mul(getPricePerFullShare()).div(1e18)
                ), 
                false);
            orders[orderId].buyerDelivery = true;
            emit Delivery(orderId, sender);
        }

        _settle(orderId, false);

    }

    /**
    * @dev anybody can invoke this method to end orderId
    * @param orderId the order msg.sender wants to settle at the final stage
     */
    function settle(uint256 orderId) external {

        require(checkOrderState(orderId) == uint(OrderState.unsettle), "! force settle");
        _settle(orderId, true);
    }


    function _settle(uint256 orderId, bool forceSettle) internal {
        (uint fee, uint base) = IHedgehogFactory(owner()).getOperationFee();
        
        Order memory order = orders[orderId];
        if (order.sellerDelivery && order.buyerDelivery) {
            // send buyer nfts and seller margin
            _multiWithdraw721(order.tokenIds, order.buyer);
            // no margin for buyer
            uint bfee = order.deliveryPrice.mul(fee).div(base);
            // send seller payout
            // uint sellerAmount = order.sellerMargin.add(order.deliveryPrice).sub(bfee);
            uint sellerAmount = forwardVault == address(0) ?  
                                    order.sellerMargin.add(order.deliveryPrice).sub(bfee) :
                                    order.sellerShare.mul(getPricePerFullShare()).div(1e18).add(order.deliveryPrice).sub(bfee);
            _pushToken(order.seller, sellerAmount);
            cfee = cfee.add(bfee.mul(2));

            orders[orderId].state = OrderState.settle;
            emit Settle(orderId);
            return; // must return here
        }
        if (forceSettle) {
            if (!order.sellerDelivery) {
                // blame seller if he/she does not deliver nfts  
                uint sfee = order.sellerMargin.mul(fee).div(base);
                cfee = cfee.add(sfee);
                _pushToken(
                    order.buyer, 
                    forwardVault == address(0) ? order.sellerMargin.sub(sfee) : 
                        order.sellerShare.mul(getPricePerFullShare()).div(1e18).sub(sfee)
                );
            } else {
                // blame buyer
                uint bfee = order.buyerMargin.mul(fee).div(base);
                cfee = cfee.add(bfee);
                _pushToken(
                    order.seller,
                    forwardVault == address(0) ? order.buyerMargin.sub(bfee) : 
                        order.buyerShare.mul(getPricePerFullShare()).div(1e18).sub(bfee)
                );

            }
            orders[orderId].state = OrderState.settle;
            emit Settle(orderId);
        }

    }
    
    /**
     * @dev return order state based on orderId
     * @param orderId order index whose state to be checked.
     * @return 
            0: active, 
            1: order is dead, 
            2: order is filled, 
            3: order is being challenged between maker and taker,
            4: challenge ended, yet not settled
            5: order has been successfully settled
            6: not exist
     */
    function checkOrderState(uint orderId) public view returns (uint) {
        Order memory order = orders[orderId];
        if (order.validTill == 0 ) return 6;
        uint time = _getBlockTimestamp();
        if (time <= order.validTill) return uint(OrderState.active);
        if (order.buyer == address(0) || order.seller == address(0)) return uint(OrderState.dead);
        if (time <= order.deliveryTime) return uint(OrderState.fill);
        if (time <= order.challengeTime) return uint(OrderState.challenge);
        if (order.state != OrderState.settle) return uint(OrderState.unsettle);
        return uint(OrderState.settle);
    }

    function collectFee() external {
        address feeCollector = IHedgehogFactory(owner()).feeCollector();
        require(feeCollector != address(0), "!feeCollector");
        _pushToken(feeCollector, cfee);
        cfee = 0;
    }

    function _pullToken(address usr, uint amount, bool farm) internal returns (uint256 shares) {
        if (marginToken == eth) {
            require(msg.value >= amount, "!margin"); // don't send more ether, won't payback
            // if vault exists, chagne ether to weth 
            if (forwardVault != address(0)) {
                IWETH(weth).deposit{value: msg.value}();
            }
        } else {
            uint rbOld = IERC20Upgradeable(marginToken).balanceOf(address(this));
            IERC20Upgradeable(marginToken).safeTransferFrom(usr, address(this), amount);
            uint rbNew = IERC20Upgradeable(marginToken).balanceOf(address(this));
            require(rbNew.sub(rbOld) == amount, "!support taxed token");
        }

        shares = forwardVault == address(0) && farm ? amount : IHForwardVault(forwardVault).deposit(amount);
        
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
            // uint laOld = IERC20Upgradeable(marginToken).balanceOf(address(this));
            IERC20Upgradeable(marginToken).safeTransfer(usr, amount);
            // uint laNew = IERC20Upgradeable(marginToken).balanceOf(address(this));
            // require(laOld.sub(laNew) == amount, "!support taxed token");
        }
    }

    function _multiDeposit721(uint256[] memory tokenIds) internal {
        // uint oldBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        for (uint i = 0; i < tokenIds.length; i++) {
            _deposit721(tokenIds[i]);
        }
        // uint newBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        // require(newBal.sub(oldBal) == tokenIds.length, "redundant Ids");
    }

    function _deposit721(uint256 tokenId) internal {

        _pullERC721(nftAddr, tokenId);
        
    }

    function _multiWithdraw721(uint256[] memory tokenIds, address to) internal {
        // uint oldBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        for (uint i = 0; i < tokenIds.length; i++) {
            _withdraw721(tokenIds[i], to);
        }
        // uint newBal = IERC721Upgradeable(nftAddr).balanceOf(address(this));
        // require(oldBal.sub(newBal).div(10**) == tokenIds.length, "redundant Ids");
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

    

}