const { ethers, upgrades, network } = require("hardhat");
const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { expect } = require("chai");
const Web3 = require('web3');
const ether = require("@openzeppelin/test-helpers/src/ether");
const toWei = Web3.utils.toWei

describe("Router TestCase with marginToken as weth and support forward router for ether", function() {
    before(async() => {
        this.signers = await ethers.getSigners()
        this.alice = this.signers[0]
        this.bob = this.signers[1]
        this.carol = this.signers[2]

        this.WETH = await ethers.getContractFactory("WETH9")
        
        this.Forward20Imp = await ethers.getContractFactory("Forward20Upgradeable")
        this.Forward721Imp = await ethers.getContractFactory("Forward721Upgradeable")
        this.Forward1155Imp = await ethers.getContractFactory("Forward1155Upgradeable")
        
        this.Factory20 = await ethers.getContractFactory("Factory20Upgradeable")
        this.Factory721 = await ethers.getContractFactory("Factory721Upgradeable")
        this.Factory1155 = await ethers.getContractFactory("Factory1155Upgradeable")
        this.Token20 = await ethers.getContractFactory("MockERC20")
        this.Token721 = await ethers.getContractFactory("MockERC721")
        this.Token1155 = await ethers.getContractFactory("MockERC1155")

        this.YVault = await ethers.getContractFactory("MockYVault")
        this.FVault = await ethers.getContractFactory("ForwardVaultUpgradeable")

        this.Router = await ethers.getContractFactory("ForwardEtherRouter")
    })
    beforeEach(async() => {
        // dai as margin, following standard erc20 protocol
        this.dai = await this.Token20.deploy("Dai Token", "DAI", 0)
        await this.dai.deployed()
        // weth as margin 1
        this.weth = await this.WETH.deploy();
        await this.weth.deployed();

        this.router = await this.Router.deploy(this.weth.address);
        await this.router.deployed();


        // as the want/asset token, like nft token in forward20
        this.want20 = await this.Token20.deploy("Want20 Token", "WANT", 0)
        await this.want20.deployed();
        
        this.want721 = await this.Token721.deploy("NFT", "NFT")
        await this.want721.deployed();

        this.want1155 = await this.Token1155.deploy("uri")
        await this.want1155.deployed();

        this.yVaultDai = await this.YVault.deploy(this.dai.address)
        await this.yVaultDai.deployed()
        this.yVaultWeth = await this.YVault.deploy(this.weth.address)
        await this.yVaultWeth.deployed()

        this.forward20Imp = await this.Forward20Imp.deploy()
        await this.forward20Imp.deployed()
        this.forward721Imp = await this.Forward721Imp.deploy()
        await this.forward721Imp.deployed()
        this.forward1155Imp = await this.Forward1155Imp.deploy()
        await this.forward1155Imp.deployed()


        this.opFee = new BN(1); // 1/10000
        this.factory20 = await upgrades.deployProxy(
            this.Factory20,
            [this.forward20Imp.address, [this.dai.address, this.weth.address], this.alice.address, this.opFee.toString()],
            {
                initializer: "__FactoryUpgradeable__init"
            }
        );
        this.factory721 = await upgrades.deployProxy(
            this.Factory721,
            [this.forward721Imp.address, [this.dai.address, this.weth.address], this.alice.address, this.opFee.toString()],
            {
                initializer: "__FactoryUpgradeable__init"
            }
        );
        this.factory1155 = await upgrades.deployProxy(
            this.Factory1155,
            [this.forward1155Imp.address, [this.dai.address, this.weth.address], this.alice.address, this.opFee.toString()],
            {
                initializer: "__FactoryUpgradeable__init"
            }
        );

        this.min = 8000
        this.base = 10000
        this.tolerance = 500
        this.fVaultDai = await upgrades.deployProxy(
            this.FVault,
            [this.dai.address, this.yVaultDai.address, this.alice.address, this.min, this.tolerance],
            {
                initializer: "__ForwardVaultUpgradeable_init"
            }
        );

        this.fVaultWeth = await upgrades.deployProxy(
            this.FVault,
            [this.weth.address, this.yVaultWeth.address, this.alice.address, this.min, this.tolerance],
            {
                initializer: "__ForwardVaultUpgradeable_init"
            }
        );
        
        // deploy pool
        await this.factory20.connect(this.alice).deployPool(this.want20.address, 20, this.dai.address)
        await this.factory20.connect(this.alice).deployPool(this.want20.address, 20, this.weth.address)
        await this.factory721.connect(this.alice).deployPool(this.want721.address, 721, this.dai.address)
        await this.factory721.connect(this.alice).deployPool(this.want721.address, 721, this.weth.address)
        await this.factory1155.connect(this.alice).deployPool(this.want1155.address, 1155, this.dai.address)
        await this.factory1155.connect(this.alice).deployPool(this.want1155.address, 1155, this.weth.address)
        
        // load pool
        this.forward20dai = await this.Forward20Imp.attach(await this.factory20.allPairs(0));
        this.forward20weth = await this.Forward20Imp.attach(await this.factory20.allPairs(1));
        this.forward721dai = await this.Forward721Imp.attach(await this.factory721.allPairs(0));
        this.forward721weth = await this.Forward721Imp.attach(await this.factory721.allPairs(1));
        this.forward1155dai = await this.Forward1155Imp.attach(await this.factory1155.allPairs(0));
        this.forward1155weth = await this.Forward1155Imp.attach(await this.factory1155.allPairs(1));
    })

    it("should deliver correctly for both seller and buyer with margin as weth and asset as erc20", async() => {
        expect(await this.forward20weth.margin()).to.equal(this.weth.address)
        let amount = toWei("10");
        let orderValidPeriod = 600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let now = (await time.latest()).toNumber();
        console.log("now = ", now)
        let deliveryStart = now + nowToDeliverPeriod;
        let deliveryPeriod = 600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let order;
        {
            console.log("before createOrder, seller ether ballance: ", await web3.eth.getBalance(this.alice.address))
            {
                const tx = await this.router.connect(this.alice).createOrder20For(
                    this.forward20weth.address,
                    this.alice.address,
                    amount,
                    [orderValidPeriod,
                    deliveryStart,
                    deliveryPeriod],
                    [deliveryPrice,
                    buyerMargin,
                    sellerMargin],
                    [],
                    deposit,
                    isSeller,
                    {value: amount}
                );
            }
            console.log("after createOrder, seller ether ballance: ", await web3.eth.getBalance(this.alice.address))
            
            console.log("before takeOrder, buyer ether ballance: ", await web3.eth.getBalance(this.bob.address))
            {
                const tx = await this.router.connect(this.bob).takeOrderFor(this.forward20weth.address, this.bob.address, 0, {value: amount});
            }
            console.log("after takeOrder, buyer ether ballance: ", await web3.eth.getBalance(this.bob.address))
        }

        await network.provider.send("evm_increaseTime", [nowToDeliverPeriod])
        await network.provider.send('evm_mine');
        // now into challenge period or delivery period
        order = await this.forward20weth.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.buyerShare.toString()).to.equal(buyerMargin)
        expect((await this.forward20weth.checkOrderState(0)).toString()).to.equal("4") // delivering

        // seller delivers: NOTICE: seller should deliver through forward directly
        await this.want20.connect(this.alice).mint(amount)
        await this.want20.connect(this.alice).approve(this.forward20weth.address, amount)
        {
            const tx = await this.forward20weth.connect(this.alice).deliverFor(this.alice.address, 0);
        }
        order = await this.forward20weth.orders(0);
        expect(order.sellerDelivered).to.equal(true);
        
        // buyer delivers and settle
        {
            const tx = await this.router.connect(this.bob).deliverFor(this.forward20weth.address, this.bob.address, 0, {value: deliveryPrice});
        }

        order = await this.forward20weth.orders(0);
        expect(order.buyerDelivered).to.equal(true);
        expect(order.state.toString()).to.equal("6"); // settled
        // calculate cfee
        let cfee = (new BN(deliveryPrice)).mul(new BN(2)).mul(this.opFee).div(new BN(this.base)); // * 2 means taking fee from both sides
        expect((await this.forward20weth.cfee()).toString()).to.equal(cfee.toString())
        
    }).timeout(100000)


    it("should deliver correctly for both seller and buyer with margin as weth and asset as erc721", async() => {
        expect(await this.forward721weth.margin()).to.equal(this.weth.address)
        let ids = [1, 2, 3, 4, 5];
        let orderValidPeriod = 600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let now = (await time.latest()).toNumber();
        console.log("now = ", now)
        let deliveryStart = now + nowToDeliverPeriod;
        let deliveryPeriod = 600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let order;
        {
            console.log("before createOrder, seller ether ballance: ", await web3.eth.getBalance(this.alice.address))
            {
                const tx = await this.router.connect(this.alice).createOrder721For(
                    this.forward721weth.address,
                    this.alice.address,
                    ids,
                    [orderValidPeriod,
                    deliveryStart,
                    deliveryPeriod],
                    [deliveryPrice,
                    buyerMargin,
                    sellerMargin],
                    [],
                    deposit,
                    isSeller,
                    {value: sellerMargin}
                );
            }
            console.log("after createOrder, seller ether ballance: ", await web3.eth.getBalance(this.alice.address))
            
            console.log("before takeOrder, buyer ether ballance: ", await web3.eth.getBalance(this.bob.address))
            {
                const tx = await this.router.connect(this.bob).takeOrderFor(this.forward721weth.address, this.bob.address, 0, {value: buyerMargin});
            }
            console.log("after takeOrder, buyer ether ballance: ", await web3.eth.getBalance(this.bob.address))
        }

        await network.provider.send("evm_increaseTime", [nowToDeliverPeriod])
        await network.provider.send('evm_mine');
        // now into challenge period or delivery period
        order = await this.forward721weth.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.buyerShare.toString()).to.equal(buyerMargin)
        expect((await this.forward721weth.checkOrderState(0)).toString()).to.equal("4") // delivering

        // seller delivers: NOTICE: seller should deliver through forward directly
        await this.want721.connect(this.alice).mintBatch(this.alice.address, ids)
        await this.want721.connect(this.alice).setApprovalForAll(this.forward721weth.address, true)
        {
            const tx = await this.forward721weth.connect(this.alice).deliverFor(this.alice.address, 0);
        }
        order = await this.forward721weth.orders(0);
        expect(order.sellerDelivered).to.equal(true);
        
        // buyer delivers and settle
        {
            const tx = await this.router.connect(this.bob).deliverFor(this.forward721weth.address, this.bob.address, 0, {value: deliveryPrice});
        }

        order = await this.forward721weth.orders(0);
        expect(order.buyerDelivered).to.equal(true);
        expect(order.state.toString()).to.equal("6"); // settled

        let balance = await this.want721.balanceOf(this.bob.address)
        expect(balance.toNumber()).to.equal(ids.length)

        // calculate cfee
        let cfee = (new BN(deliveryPrice)).mul(new BN(2)).mul(this.opFee).div(new BN(this.base)); // * 2 means taking fee from both sides
        expect((await this.forward721weth.cfee()).toString()).to.equal(cfee.toString())
    }).timeout(100000)

    it("should deliver correctly for both seller and buyer with margin as weth and asset as erc1155", async() => {
        expect(await this.forward1155weth.margin()).to.equal(this.weth.address)
        let ids = [1, 2, 3, 4, 5];
        let amounts = [100, 200, 300, 400, 500]
        let orderValidPeriod = 600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let now = (await time.latest()).toNumber();
        console.log("now = ", now)
        let deliveryStart = now + nowToDeliverPeriod;
        let deliveryPeriod = 600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let order;
        {
            console.log("before createOrder, seller ether ballance: ", await web3.eth.getBalance(this.alice.address))
            {
                const tx = await this.router.connect(this.alice).createOrder1155For(
                    this.forward1155weth.address,
                    this.alice.address,
                    ids,
                    amounts,
                    [orderValidPeriod,
                    deliveryStart,
                    deliveryPeriod],
                    [deliveryPrice,
                    buyerMargin,
                    sellerMargin],
                    [],
                    deposit,
                    isSeller,
                    {value: sellerMargin}
                );
            }
            console.log("after createOrder, seller ether ballance: ", await web3.eth.getBalance(this.alice.address))
            
            console.log("before takeOrder, buyer ether ballance: ", await web3.eth.getBalance(this.bob.address))
            {
                const tx = await this.router.connect(this.bob).takeOrderFor(this.forward1155weth.address, this.bob.address, 0, {value: buyerMargin});
            }
            console.log("after takeOrder, buyer ether ballance: ", await web3.eth.getBalance(this.bob.address))
        }

        await network.provider.send("evm_increaseTime", [nowToDeliverPeriod])
        await network.provider.send('evm_mine');
        // now into challenge period or delivery period
        order = await this.forward1155weth.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.buyerShare.toString()).to.equal(buyerMargin)
        expect((await this.forward1155weth.checkOrderState(0)).toString()).to.equal("4") // delivering

        // seller delivers: NOTICE: seller should deliver through forward directly
        await this.want1155.connect(this.alice).mintBatch(this.alice.address, ids, amounts)
        await this.want1155.connect(this.alice).setApprovalForAll(this.forward1155weth.address, true)
        {
            const tx = await this.forward1155weth.connect(this.alice).deliverFor(this.alice.address, 0);
        }
        order = await this.forward1155weth.orders(0);
        expect(order.sellerDelivered).to.equal(true);
        
        // buyer delivers and settle
        {
            const tx = await this.router.connect(this.bob).deliverFor(this.forward1155weth.address, this.bob.address, 0, {value: deliveryPrice});
        }

        order = await this.forward1155weth.orders(0);
        expect(order.buyerDelivered).to.equal(true);
        expect(order.state.toString()).to.equal("6"); // settled

        let balances = await this.want1155.balanceOfBatch([this.bob.address, this.bob.address, this.bob.address, this.bob.address, this.bob.address], ids)
        expect(balances[0].toNumber()).to.equal(amounts[0])
        expect(balances[1].toNumber()).to.equal(amounts[1])
        expect(balances[2].toNumber()).to.equal(amounts[2])
        expect(balances[3].toNumber()).to.equal(amounts[3])
        expect(balances[4].toNumber()).to.equal(amounts[4])

        // calculate cfee
        let cfee = (new BN(deliveryPrice)).mul(new BN(2)).mul(this.opFee).div(new BN(this.base)); // * 2 means taking fee from both sides
        expect((await this.forward1155weth.cfee()).toString()).to.equal(cfee.toString())
    }).timeout(100000)
    
})
