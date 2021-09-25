// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
    function takeOrder(address _taker, uint _orderId) external;
    function deliver(address _deliverer, uint _orderId) external;
    function settle(uint _orderId) external;

    function margin() external view returns (address);
}

interface IForward20 is IBaseForward {
    function createOrder(
        address _creator,
        uint256 _underlyingAmount, 
        // uint _orderValidPeriod, 
        // uint _nowToDeliverPeriod,
        // uint _deliveryPeriod,
        // uint256 _deliveryPrice,
        // uint256 _buyerMargin,
        // uint256 _sellerMargin,
        uint256[6] memory _uintData,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external;
}

interface IForward721 is IBaseForward {
    function createOrder(
        address _creator,
        uint256[] memory _tokenIds, 
        // uint _orderValidPeriod, 
        // uint _nowToDeliverPeriod,
        // uint _deliveryPeriod,
        // uint256 _deliveryPrice,
        // uint256 _buyerMargin,
        // uint256 _sellerMargin,
        uint256[6] memory _uintData,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external;
}

interface IForward1155 is IBaseForward {
    function createOrder(
        address _creator,
        uint256[] memory _ids,
        uint256[] memory _amounts, 
        // uint _orderValidPeriod, 
        // uint _nowToDeliverPeriod,
        // uint _deliveryPeriod,
        // uint256 _deliveryPrice,
        // uint256 _buyerMargin,
        // uint256 _sellerMargin,
        uint256[6] memory _uintData,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external;
}

contract ForwardEtherRouter {
    IWETH public weth;
    constructor(address _weth) {
        weth = IWETH(_weth);
    }
    
    function createOrder20(
        address _forward20,
        address _creator,
        uint256 _underlyingAmount,
        uint256[6] memory _uintData,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external payable {
        require(IForward20(_forward20).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();
        uint allowance = weth.allowance(address(this), _forward20);
        if (allowance == 0) {
            weth.approve(_forward20, type(uint256).max);
        }
        
        IForward20(_forward20).createOrder(
            _creator,
            _underlyingAmount,
            _uintData,
            _takerWhiteList,
            _deposit,
            _isSeller
        );
        if (weth.balanceOf(address(this)) > 0) {
            weth.withdraw(weth.balanceOf(address(this)));
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function createOrder721(
        address _forward721,
        address _creator,
        uint256[] memory _tokenIds,
        uint256[6] memory _uintData,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external payable {
        require(IForward721(_forward721).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();
        uint allowance = weth.allowance(address(this), _forward721);
        if (allowance == 0) {
            weth.approve(_forward721, type(uint256).max);
        }
        
        IForward721(_forward721).createOrder(
            _creator,
            _tokenIds,
            _uintData,
            _takerWhiteList,
            _deposit,
            _isSeller
        );
        if (weth.balanceOf(address(this)) > 0) {
            weth.withdraw(weth.balanceOf(address(this)));
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function createOrder1155(
        address _forward1155,
        address _creator,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        uint256[6] memory _uintData,
        address[] memory _takerWhiteList,
        bool _deposit,
        bool _isSeller
    ) external payable {
        require(IForward1155(_forward1155).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();
        uint allowance = weth.allowance(address(this), _forward1155);
        if (allowance == 0) {
            weth.approve(_forward1155, type(uint256).max);
        }
        
        IForward1155(_forward1155).createOrder(
            _creator,
            _ids,
            _amounts,
            _uintData,
            _takerWhiteList,
            _deposit,
            _isSeller
        );

        if (weth.balanceOf(address(this)) > 0) {
            weth.withdraw(weth.balanceOf(address(this)));
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function takeOrder(
        address _forward,
        address _taker,
        uint _orderId
    ) external payable {
        require(IForward20(_forward).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();
        IBaseForward(_forward).takeOrder(_taker, _orderId);

        if (weth.balanceOf(address(this)) > 0) {
            weth.withdraw(weth.balanceOf(address(this)));
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function deliver(
        address _forward,
        address _deliverer,
        uint _orderId
    ) external payable {
        require(IForward20(_forward).margin() == address(weth), "margin not weth");
        weth.deposit{value: msg.value}();

        IBaseForward(_forward).deliver(_deliverer, _orderId);

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

    // receive ether paid from weth
    receive() external payable {}
}