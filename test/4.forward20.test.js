const { ethers, upgrades, network } = require("hardhat");
const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { expect } = require("chai");
const Web3 = require('web3');
const toWei = Web3.utils.toWei

describe("Forward20 TestCase with marginToken", function() {
    before(async() => {
        this.signers = await ethers.getSigners()
        this.alice = this.signers[0]
        this.bob = this.signers[1]
        this.carol = this.signers[2]

        this.WETH = await ethers.getContractFactory("WETH9")
        this.Dai = await ethers.getContractFactory("MockERC20")
        this.Forward20Imp = await ethers.getContractFactory("Forward20Upgradeable")
        this.Factory20 = await ethers.getContractFactory("Factory20Upgradeable")

        this.YVault = await ethers.getContractFactory("MockYVault")
        this.FVault = await ethers.getContractFactory("ForwardVaultUpgradeable")

    })
    beforeEach(async() => {
        this.weth = await this.WETH.deploy();
        await this.weth.deployed();
        
        // as margin
        this.dai = await this.Dai.deploy("Dai Token", "DAI", 0)
        await this.dai.deployed()
        
        // as the want token, like nft token in forward20
        this.want = await this.Dai.deploy("Want Token", "WANT", 0)
        await this.want.deployed();

        this.yVault = await this.YVault.deploy(this.dai.address)
        await this.yVault.deployed()

        this.forward20Imp = await this.Forward20Imp.deploy()
        await this.forward20Imp.deployed()

        this.opFee = new BN(1); // 1/10000
        this.factory20 = await upgrades.deployProxy(
            this.Factory20,
            [this.forward20Imp.address, [this.dai.address], this.alice.address, this.opFee.toString()],
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
        
        const tx = await this.factory20.connect(this.alice).deployPool(this.want.address, 20, this.dai.address)
        console.log("gasLimit-----factory20.deployPool----: ", tx.gasLimit.toString())
        this.forward20 = await this.Forward20Imp.attach(await this.factory20.allPairs(0));
    })

    it("should take buyer's margin if only seller deliverred correctly", async() => {
        let baseGasConsumed;
        {
            const tx = await this.dai.connect(this.alice).mint(1);
            console.log("ERC20 mint tx is: ", JSON.stringify(tx))
            console.log("gasLimit-----ERC20.mint----: ", tx.gasLimit.toString())
        }
        {
            const tx = await this.dai.connect(this.alice).transfer(this.alice.address, 1);
            console.log("ERC20 transfer tx is: ", JSON.stringify(tx))
            console.log("gasLimit-----ERC20.transfer----: ", tx.gasLimit.toString())
            baseGasConsumed = tx.gasLimit;
        }

        let amounts = toWei("10");
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
            expect((await this.forward20.checkOrderState(0)).toString()).to.equal("0") // inactive
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward20.address, sellerMargin)
            {
                const tx = await this.forward20.connect(this.alice).createOrderFor(
                    this.alice.address,
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
                console.log("tx is: ", JSON.stringify(tx))
                console.log("gasLimit-----createOrder----: ", tx.gasLimit.toString(), tx.gasLimit.div(baseGasConsumed).toString())
            }
            expect((await this.forward20.checkOrderState(0)).toString()).to.equal("1") // active
            await this.dai.connect(this.bob).mint(buyerMargin);
            await this.dai.connect(this.bob).approve(this.forward20.address, buyerMargin);
            {
                const tx = await this.forward20.connect(this.bob).takeOrderFor(this.bob.address, 0);
                console.log("takerOrder tx is: ", JSON.stringify(tx))
                console.log("gasLimit-----takeOrder----: ", tx.gasLimit.toString(), tx.gasLimit.div(baseGasConsumed).toString())
            }
            expect((await this.forward20.checkOrderState(0)).toString()).to.equal("2") // filled
        }
        
        await network.provider.send("evm_increaseTime", [nowToDeliverPeriod])
        await network.provider.send('evm_mine');
        // now into challenge period or delivery period
        order = await this.forward20.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        console.log("deliveryStart = ", deliveryStart)
        console.log("order.validTill = ", order.validTill.toString())
        console.log("order.deliverStart = ", order.deliverStart.toString())
        console.log("order.expireStart = ", order.expireStart.toString())
        console.log("now = ", (await time.latest()).toString())
        expect((await this.forward20.checkOrderState(0)).toString()).to.equal("4") // delivering

        // seller delivers
        await this.want.connect(this.alice).mint(deliveryPrice)
        await this.want.connect(this.alice).approve(this.forward20.address, deliveryPrice)
        {
            const tx = await this.forward20.connect(this.alice).deliverFor(this.alice.address, 0);
            console.log("deliver tx1 is: ", JSON.stringify(tx))
            console.log("gasLimit-----deliver----: ", tx.gasLimit.toString(), tx.gasLimit.div(baseGasConsumed).toString())
        }
        order = await this.forward20.orders(0);
        expect(order.sellerDelivered).to.equal(true);
        
        // buyer delivers and settle
        await this.dai.connect(this.bob).mint(deliveryPrice);
        await this.dai.connect(this.bob).approve(this.forward20.address, deliveryPrice)
        {
            const tx = await this.forward20.connect(this.bob).deliverFor(this.bob.address, 0);
            console.log("deliver tx2 is: ", JSON.stringify(tx))
            console.log("gasLimit-----deliver and settle----: ", tx.gasLimit.toString(), tx.gasLimit.div(baseGasConsumed).toString())
        }

        order = await this.forward20.orders(0);
        expect(order.buyerDelivered).to.equal(true);
        expect((await this.forward20.checkOrderState(0)).toString()).to.equal("6"); // settled
        // calculate cfee
        let cfee = (new BN(deliveryPrice)).mul(new BN(2)).mul(this.opFee).div(new BN(this.base)); // * 2 means taking fee from both sides
        // console.log("cfee       : ", cfee.toString())
        // console.log("actual cfee: ", (await this.forward20.cfee()).toString())
        expect((await this.forward20.cfee()).toString()).to.equal(cfee.toString())

        
    }).timeout(100000)
    
})
