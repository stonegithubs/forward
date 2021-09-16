const { ethers, upgrades, network } = require("hardhat");
const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { expect } = require("chai");
const Web3 = require('web3');
const toWei = Web3.utils.toWei

describe("Forward721 TestCase with marginToken as Ether", function() {
    before(async() => {
        this.signers = await ethers.getSigners()
        this.alice = this.signers[0]
        this.bob = this.signers[1]
        this.carol = this.signers[2]
        this.eth = constants.ZERO_ADDRESS;

        this.WETH = await ethers.getContractFactory("WETH9")
        this.Dai = await ethers.getContractFactory("MockERC20")
        this.Nft = await ethers.getContractFactory("MockERC721")
        this.Forward721Imp = await ethers.getContractFactory("Forward721Upgradeable")
        this.Factory = await ethers.getContractFactory("HedgehogFactoryUpgradeable")

        this.YVault = await ethers.getContractFactory("MockYVault")
        this.HVault = await ethers.getContractFactory("HForwardVaultUpgradeable")

    })
    beforeEach(async() => {
        this.weth = await this.WETH.deploy();
        await this.weth.deployed();
        
        this.dai = await this.Dai.deploy("Dai Token", "DAI", 0)
        await this.dai.deployed()
        
        this.nft = await this.Nft.deploy("First Nft", "FNFT")
        await this.nft.deployed()

        this.yVault = await this.YVault.deploy(this.dai.address)
        await this.yVault.deployed()

        this.forward721Imp = await this.Forward721Imp.deploy()
        await this.forward721Imp.deployed()

        this.opFee = new BN(1); // 1/10000
        this.factory = await upgrades.deployProxy(
            this.Factory,
            [this.forward721Imp.address, [this.dai.address], this.alice.address, this.opFee.toString(), this.weth.address],
            {
                initializer: "__FactoryUpgradeable__init"
            }
        );

        this.min = 8000
        this.base = 10000
        this.tolerance = 500
        this.hVault = await upgrades.deployProxy(
            this.HVault,
            [this.dai.address, this.yVault.address, this.alice.address, this.min, this.tolerance],
            {
                initializer: "__HForwardVault_init"
            }
        );
        
        await this.factory.connect(this.alice).deployPool(this.nft.address, 721, this.eth)
        this.forward721 = await this.Forward721Imp.attach(await this.factory.allPairs(0));
    })

    // it("should take buyer's margin if only seller deliverred correctly", async() => {
    //     let tokenIds = [0, 1];
    //     let orderValidPeriod = 10 * 60;
    //     let deliveryPrice = toWei("123", "ether");
    //     let deliveryPeriod = 20 * 60;
    //     let challengePeriod = 10 * 60;
    //     let buyerMargin = toWei("1", "ether");
    //     let sellerMargin = toWei("2", "ether");
    //     let deposit = false;
    //     let isSeller = true;
    //     let validTill;
    //     let now = await time.latest();
        
    //     await this.dai.connect(this.alice).mint(sellerMargin);
    //     await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
    //         await this.forward721.connect(this.alice).createOrder(
    //             tokenIds,
    //             10 * 60,
    //             deliveryPrice,
    //             deliveryPeriod,
    //             challengePeriod,
    //             [],
    //             buyerMargin,
    //             sellerMargin,
    //             deposit,
    //             isSeller
    //         );
    //         await this.dai.connect(this.bob).mint(buyerMargin);
    //         await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
    //         await this.forward721.connect(this.bob).takeOrder(0);

    //         await network.provider.send("evm_increaseTime", [orderValidPeriod + deliveryPeriod])
    //         await network.provider.send('evm_mine');
            
    //         // seller delivers
    //         for (let i = 0; i < tokenIds.length; i++) {
    //             await this.nft.connect(this.alice).mint(this.alice.address, tokenIds[i]);
    //             await this.nft.connect(this.alice).approve(this.forward721.address, tokenIds[i]);
    //         }
    //         await this.forward721.connect(this.alice).deliver(0);
    //         order = await this.forward721.orders(0);
    //         expect(order.sellerDelivery).to.equal(true);
    //     }

    //     // now into settling period, yet buyer not deliver
    //     await network.provider.send("evm_increaseTime", [challengePeriod])
    //     await network.provider.send('evm_mine');
        
    //     order = await this.forward721.orders(0);
    //     expect(order.buyer).to.equal(this.bob.address)
    //     expect(order.buyerShare.toString()).to.equal(buyerMargin)
    //     expect(order.buyerDelivery).to.equal(false)
    //     expect(order.sellerDelivery).to.equal(true)
    //     expect((await this.forward721.checkOrderState(0)).toString()).to.equal("5") // challenging
    //     let oldCfee = await this.forward721.cfee();
    //     await this.forward721.connect(this.carol).settle(0)
    //     let newCfee = await this.forward721.cfee();

    //     // calculate cfee
    //     let cfee = (new BN(buyerMargin)).mul(this.opFee).divn(new BN(10000));
    //     // console.log("cfee       : ", cfee.toString())
    //     // console.log("actual cfee: ", (newCfee.sub(oldCfee)).toString())
    //     expect((newCfee.sub(oldCfee)).toString()).to.equal(cfee.toString())
    // })
    
})