const { ethers, upgrades, network } = require("hardhat");
const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { expect } = require("chai");
const Web3 = require('web3');
const toWei = Web3.utils.toWei

describe("Forward1155 TestCase with marginToken", function() {
    before(async() => {
        this.signers = await ethers.getSigners()
        this.alice = this.signers[0]
        this.bob = this.signers[1]
        this.carol = this.signers[2]

        this.WETH = await ethers.getContractFactory("WETH9")
        this.Dai = await ethers.getContractFactory("MockERC20")
        this.Forward20Imp = await ethers.getContractFactory("Forward20Upgradeable")
        this.Forward1155Imp = await ethers.getContractFactory("Forward1155Upgradeable")
        this.Factory1155 = await ethers.getContractFactory("Factory1155Upgradeable")
        this.Token1155 = await ethers.getContractFactory("MockERC1155")

        this.YVault = await ethers.getContractFactory("MockYVault")
        this.FVault = await ethers.getContractFactory("ForwardVaultUpgradeable")

    })
    beforeEach(async() => {
        this.weth = await this.WETH.deploy();
        await this.weth.deployed();
        
        // as margin
        this.dai = await this.Dai.deploy("Dai Token", "DAI", 0)
        await this.dai.deployed()
        
        // as the want token, like nft token in forward721
        this.want = await this.Token1155.deploy("uri")
        await this.want.deployed();

        this.yVault = await this.YVault.deploy(this.dai.address)
        await this.yVault.deployed()

        this.forward1155Imp = await this.Forward1155Imp.deploy()
        await this.forward1155Imp.deployed()

        this.opFee = new BN(1); // 1/10000
        this.Factory1155 = await upgrades.deployProxy(
            this.Factory1155,
            [this.forward1155Imp.address, [this.dai.address], this.alice.address, this.opFee.toString()],
            {
                initializer: "__FactoryUpgradeable__init"
            }
        );

        this.min = 8000
        this.base = 10000
        this.tolerance = 500
        this.fVault = await upgrades.deployProxy(
            this.FVault,
            [this.dai.address, this.yVault.address, this.alice.address, this.min, this.tolerance],
            {
                initializer: "__ForwardVaultUpgradeable_init"
            }
        );
        
        const tx = await this.Factory1155.connect(this.alice).deployPool(this.want.address, 1155, this.dai.address)
        console.log("gasLimit-----Factory1155.deployPool----: ", tx.gasLimit.toString())
        this.forward1155 = await this.Forward1155Imp.attach(await this.Factory1155.allPairs(0));
    })

    it("should deliver correctly for both seller and buyer", async() => {
        let ids = [0, 1, 2]
        let amounts = [toWei("10"), toWei("1"), toWei("5")];
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
        expect((await this.forward1155.checkOrderState(0)).toString()).to.equal("0") // inactive
        await this.dai.connect(this.alice).mint(sellerMargin);
        await this.dai.connect(this.alice).approve(this.forward1155.address, sellerMargin)
        await this.forward1155.connect(this.alice).createOrderFor(
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
            isSeller
        );
        expect((await this.forward1155.checkOrderState(0)).toString()).to.equal("1") // active
        await this.dai.connect(this.bob).mint(buyerMargin);
        await this.dai.connect(this.bob).approve(this.forward1155.address, buyerMargin);
        
        await this.forward1155.connect(this.bob).takeOrderFor(this.bob.address, 0);
        expect((await this.forward1155.checkOrderState(0)).toString()).to.equal("2") // filled
        
        await network.provider.send("evm_increaseTime", [nowToDeliverPeriod])
        await network.provider.send('evm_mine');
        // now into challenge period or delivery period
        order = await this.forward1155.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect((await this.forward1155.checkOrderState(0)).toString()).to.equal("4") // delivering

        // seller delivers
        await this.want.connect(this.alice).mintBatch(this.alice.address, ids, amounts)
        await this.want.connect(this.alice).setApprovalForAll(this.forward1155.address, true)
        await this.forward1155.connect(this.alice).deliverFor(this.alice.address, 0);
        order = await this.forward1155.orders(0);
        expect(order.sellerDelivered).to.equal(true);
        
        // buyer delivers and settle
        await this.dai.connect(this.bob).mint(deliveryPrice);
        await this.dai.connect(this.bob).approve(this.forward1155.address, deliveryPrice)
        await this.forward1155.connect(this.bob).deliverFor(this.bob.address, 0);
        let balances = await this.want.balanceOfBatch([this.bob.address, this.bob.address, this.bob.address], ids)
        expect(balances[0].toString()).to.equal(amounts[0])
        expect(balances[1].toString()).to.equal(amounts[1])
        expect(balances[2].toString()).to.equal(amounts[2])

        order = await this.forward1155.orders(0);
        expect(order.buyerDelivered).to.equal(true);
        expect((await this.forward1155.checkOrderState(0)).toString()).to.equal("6"); // settled
        // calculate cfee
        let cfee = (new BN(deliveryPrice)).mul(new BN(2)).mul(this.opFee).div(new BN(this.base)); // * 2 means taking fee from both sides
        expect((await this.forward1155.cfee()).toString()).to.equal(cfee.toString())

        
    }).timeout(100000)
    
})
