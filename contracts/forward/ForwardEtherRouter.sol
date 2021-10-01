// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IWETH {

    function deposit() external payable;

    function withdraw(uint) external;

    function approve(address, uint) external returns(bool);

    function transfer(address, uint) external returns(bool);

    function transferFrom(address, address, uint) external returns(bool);

    function balanceOf(address) external view returns(uint);

    function allowance(address owner, address spender) external view returns (uint);
}


interface IBaseForward {
    function cancelOrder(uint _orderId) external;
    function takeOrderFor(address _taker, uint _orderId) external;
    function deliverFor(address _deliverer, uint _orderId) external;
    function settle(uint _orderId) external;

    function margin() external view returns (address);
    function want() external view returns (address);
}

interface IForward20 is IBaseForward {
    function createOrderFor(
        address _creator,
        uint _underlyingAmount, 
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
    ) external;
}

interface IForward721 is IBaseForward {
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
    ) external;
}

interface IForward1155 is IBaseForward {
    function createOrderFor(
        address _creator,
        uint[] memory _ids,
        uint[] memory _amounts,
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
    ) external;
}

contract ForwardEtherRouter2 {
    using SafeERC20 for IERC20;
    IWETH public weth;
    constructor(address _weth) {
        weth = IWETH(_weth);
    }
    
    function createOrder20For(
        address _forward20,
        address _creator,
        uint _underlyingAmount, 
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
    ) external payable {
        require(IForward20(_forward20).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();
        uint allowance = weth.allowance(address(this), _forward20);
        if (allowance == 0) {
            weth.approve(_forward20, type(uint).max);
        }

        // if (_deposit) {
        //     if (_isSeller) IERC20(IForward20(_forward20).want()).safeTransferFrom(msg.sender, address(this), _underlyingAmount);
        //     else IERC20(IForward20(_forward20).margin()).safeTransferFrom(msg.sender, address(this), _prices[0]); // unnecessary since ether comes actively
        // }
        // above equals below on condition that want != margin
        if (_deposit && _isSeller) {
            address want = IForward20(_forward20).want();
            IERC20(want).safeTransferFrom(msg.sender, address(this), _underlyingAmount);
            allowance = IERC20(want).allowance(address(this), _forward20);
            if (allowance == 0) {
                IERC20(want).approve(_forward20, type(uint).max);
            }
        }

        IForward20(_forward20).createOrderFor(
            _creator,
            _underlyingAmount,
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
        if (weth.balanceOf(address(this)) > 0) {
            weth.withdraw(weth.balanceOf(address(this)));
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function createOrder721For(
        address _forward721,
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
    ) external payable {
        require(IForward721(_forward721).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();
        uint allowance = weth.allowance(address(this), _forward721);
        if (allowance == 0) {
            weth.approve(_forward721, type(uint).max);
        }

        // if (_deposit) {
        //     if (_isSeller) {
        //         // transfer _tokenIds 721 asset into address(this)
        //         // approve these _tokenIds 721 asset to forward721
        //     } else {
        //         // nothing to do since weth approved to forward721
        //     }
        // }
        // above equals below on condition that want != margin
        if (_deposit && _isSeller) {
            // TODO: transfer _tokenIds 721 asset into address(this) then approve to forward721
        }

        IForward721(_forward721).createOrderFor(
            _creator,
            _tokenIds,
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
        if (weth.balanceOf(address(this)) > 0) {
            weth.withdraw(weth.balanceOf(address(this)));
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function createOrder1155For(
        address _forward1155,
        address _creator,
        uint[] memory _ids,
        uint[] memory _amounts,
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
    ) external payable {
        require(IForward1155(_forward1155).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();
        uint allowance = weth.allowance(address(this), _forward1155);
        if (allowance == 0) {
            weth.approve(_forward1155, type(uint).max);
        }

        // if (_deposit) {
        //     if (_isSeller) {
        //         // transfer _tokenIds 1155 asset into address(this)
        //         // approve these _tokenIds 721 asset to forward1155
        //     } else {
        //         // nothing to do since weth approved to forward1155
        //     }
        // }
        // above equals below on condition that want != margin
        if (_deposit && _isSeller) {
            // TODO: transfer _tokenIds 1155 asset into address(this) then approve to forward1155
        }

        IForward1155(_forward1155).createOrderFor(
            _creator,
            _ids,
            _amounts,
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

        if (weth.balanceOf(address(this)) > 0) {
            weth.withdraw(weth.balanceOf(address(this)));
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function takeOrderFor(
        address _forward,
        address _taker,
        uint _orderId
    ) external payable {
        require(IForward20(_forward).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();
        // below is not necessary since if someone takeOrder, it means someone else has already created order, allowance > 0
        // uint allowance = weth.allowance(address(this), _forward);
        // if (allowance == 0) {
        //     weth.approve(_forward, type(uint).max);
        // }

        IBaseForward(_forward).takeOrderFor(_taker, _orderId);

        if (weth.balanceOf(address(this)) > 0) {
            weth.withdraw(weth.balanceOf(address(this)));
            payable(msg.sender).transfer(address(this).balance);
        }
    }


    function deliverFor(
        address _forward,
        address _deliverer,
        uint _orderId
    ) external payable {
        require(IForward20(_forward).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();

        // not consider how seller should deliver, also, how seller deposit asset token like 20, 721, 1155 
        // TODO: take 20, 721, 1155 underlying assets from msg.sender, then approve them to forward contract

        IBaseForward(_forward).deliverFor(_deliverer, _orderId);

        if (weth.balanceOf(address(this)) > 0) {
            weth.withdraw(weth.balanceOf(address(this)));
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function settle(
        address _forward,
        uint _orderId
    ) external {
        IBaseForward(_forward).settle(_orderId);
    }

    function cancelOrder(
        address _forward,
        uint _orderId
    ) external payable {
        // here we would return weth margin to seller or buyer, not ether
        IBaseForward(_forward).cancelOrder(_orderId);
    }

    // receive ether paid from weth
    receive() external payable {}
    // function() external payable {}
}