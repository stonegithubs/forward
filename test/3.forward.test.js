const { ethers, upgrades, network } = require("hardhat");
const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { expect } = require("chai");
const Web3 = require('web3');
const toWei = Web3.utils.toWei
const toBN = Web3.utils.toBN
describe("Forward721 TestCase with marginToken as ERC20", function() {
    before(async() => {
        this.signers = await ethers.getSigners()
        this.alice = this.signers[0]
        this.bob = this.signers[1]
        this.carol = this.signers[2]

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
        
        await this.factory.connect(this.alice).deployPool(this.nft.address, 721, this.dai.address)
        this.forward721 = await this.Forward721Imp.attach(await this.factory.allPairs(0));
    })

    it("should deployPool correctly", async() => {
        expect((await this.factory.allPairsLength()).toString()).to.equal("1");
        expect(await this.factory.getPair(this.nft.address, this.dai.address)).to.equal(this.forward721.address)
    })
    
    
    it("should createOrder correctly", async()=> {
        let tokenIds = [0, 1];
        let orderValidPeriod = 10 * 60;
        let deliveryPrice = toWei("123", "ether");
        let deliveryPeriod = 20 * 60;
        let challengePeriod = 10 * 60;
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let now = await time.latest();
        
        await this.dai.connect(this.alice).mint(sellerMargin);
        await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
        await this.forward721.connect(this.alice).createOrder(
            tokenIds,
            orderValidPeriod,
            deliveryPrice,
            deliveryPeriod,
            challengePeriod,
            [],
            buyerMargin,
            sellerMargin,
            deposit,
            isSeller
        );

        now = await time.latest();
        validTill = now.addn(orderValidPeriod);
        let deliveryTime = validTill.addn(deliveryPeriod);
        let challengeTime = deliveryTime.addn(challengePeriod);

        let order = await this.forward721.orders(0);
        // console.log("order is ", JSON.stringify(order))
        // console.log("order.buyer is ", order.buyer)
        expect(order.buyer).to.equal(constants.ZERO_ADDRESS)
        expect(order.buyerMargin.toString()).to.equal(buyerMargin)
        expect(order.buyerShare.toString()).to.equal("0")
        expect(order.seller).to.equal(this.alice.address)
        expect(order.sellerMargin.toString()).to.equal(sellerMargin)
        expect(order.sellerShare.toString()).to.equal(sellerMargin)
        expect(order.validTill.toString()).to.equal(validTill.toString())
        expect(order.deliveryPrice.toString()).to.equal(deliveryPrice)
        expect(order.deliveryTime.toString()).to.equal(deliveryTime.toString())
        expect(order.challengeTime.toString()).to.equal(challengeTime.toString())
        expect(order.state.toString()).to.equal("1") // active
        expect(order.sellerDelivery).to.equal(deposit && isSeller);
        expect(order.buyerDelivery).to.equal(deposit && !isSeller);
        
        expect((await this.forward721.ordersLength()).toString()).to.equal("1")
    })
    
    it("should NOT take order", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 10 * 60;
        let deliveryPrice = toWei("123", "ether");
        let deliveryPeriod = 20 * 60;
        let challengePeriod = 10 * 60;
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let now = await time.latest();
        
        {
            await this.dai.connect(this.alice).mint(toWei("2", "ether"));
            await this.dai.connect(this.alice).approve(this.forward721.address, toWei("2", "ether"))
            await this.forward721.connect(this.alice).createOrder(
                tokenIds,
                10 * 60,
                deliveryPrice,
                deliveryPeriod,
                challengePeriod,
                [],
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            );
        }

        await expectRevert(
            this.forward721.connect(this.bob).takeOrder(1),
            "!orderId"
        );

        await network.provider.send("evm_increaseTime", [orderValidPeriod + 100])
        await network.provider.send('evm_mine');
        await expectRevert(
            this.forward721.connect(this.bob).takeOrder(0),
            "!valid & !active"
        );
        expect((await this.forward721.checkOrderState(0)).toString()).to.equal("2") // dead

    })
    it("should take order correctly", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 10 * 60;
        let deliveryPrice = toWei("123", "ether");
        let deliveryPeriod = 20 * 60;
        let challengePeriod = 10 * 60;
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        
        {
            await this.dai.connect(this.alice).mint(toWei("2", "ether"));
            await this.dai.connect(this.alice).approve(this.forward721.address, toWei("2", "ether"))
            await this.forward721.connect(this.alice).createOrder(
                tokenIds,
                10 * 60,
                deliveryPrice,
                deliveryPeriod,
                challengePeriod,
                [],
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            );
        }
        await this.dai.connect(this.bob).mint(buyerMargin);
        expect((await this.dai.balanceOf(this.bob.address)).toString()).to.equal(buyerMargin);
        await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
        expect((await this.dai.allowance(this.bob.address, this.forward721.address)).toString()).to.equal(buyerMargin);
        await this.forward721.connect(this.bob).takeOrder(0);
        let order = await this.forward721.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.buyerShare.toString()).to.equal(buyerMargin)
        expect(order.state.toString()).to.equal("3") // order filled
    })
    it("should deliver correctly for both seller and buyer", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 10 * 60;
        let deliveryPrice = toWei("123", "ether");
        let deliveryPeriod = 20 * 60;
        let challengePeriod = 10 * 60;
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let order;
        {
            await this.dai.connect(this.alice).mint(toWei("2", "ether"));
            await this.dai.connect(this.alice).approve(this.forward721.address, toWei("2", "ether"))
            await this.forward721.connect(this.alice).createOrder(
                tokenIds,
                10 * 60,
                deliveryPrice,
                deliveryPeriod,
                challengePeriod,
                [],
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            );
            await this.dai.connect(this.bob).mint(buyerMargin);
            await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
            await this.forward721.connect(this.bob).takeOrder(0);
        }

        await network.provider.send("evm_increaseTime", [orderValidPeriod + deliveryPeriod])
        await network.provider.send('evm_mine');
        // now into challenge period or delivery period
        order = await this.forward721.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.buyerShare.toString()).to.equal(buyerMargin)
        expect((await this.forward721.checkOrderState(0)).toString()).to.equal("4") // challenging

        // seller delivers
        for (let i = 0; i < tokenIds.length; i++) {
            await this.nft.connect(this.alice).mint(this.alice.address, tokenIds[i]);
            await this.nft.connect(this.alice).approve(this.forward721.address, tokenIds[i]);
        }
        await this.forward721.connect(this.alice).deliver(0);
        order = await this.forward721.orders(0);
        expect(order.sellerDelivery).to.equal(true);
        
        // buyer delivers and settle
        await this.dai.connect(this.bob).mint(deliveryPrice);
        await this.dai.connect(this.bob).approve(this.forward721.address, deliveryPrice)
        await this.forward721.connect(this.bob).deliver(0);
        
        order = await this.forward721.orders(0);
        expect(order.buyerDelivery).to.equal(true);
        expect(order.state.toString()).to.equal("6"); // settled
        // calculate cfee
        let cfee = (new BN(deliveryPrice)).mul(new BN(2)).mul(this.opFee).divn(new BN(this.base)); // * 2 means taking fee from both sides
        // console.log("cfee       : ", cfee.toString())
        // console.log("actual cfee: ", (await this.forward721.cfee()).toString())
        expect((await this.forward721.cfee()).toString()).to.equal(cfee.toString())
        
    })
    it("should take seller's margin if only buyer deliverred correctly", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 10 * 60;
        let deliveryPrice = toWei("123", "ether");
        let deliveryPeriod = 20 * 60;
        let challengePeriod = 10 * 60;
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let order;
        {
            await this.dai.connect(this.alice).mint(toWei("2", "ether"));
            await this.dai.connect(this.alice).approve(this.forward721.address, toWei("2", "ether"))
            await this.forward721.connect(this.alice).createOrder(
                tokenIds,
                10 * 60,
                deliveryPrice,
                deliveryPeriod,
                challengePeriod,
                [],
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            );
            await this.dai.connect(this.bob).mint(buyerMargin);
            await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
            await this.forward721.connect(this.bob).takeOrder(0);
            
            
            // buyer delivers 
            await network.provider.send("evm_increaseTime", [orderValidPeriod + deliveryPeriod])
            await this.dai.connect(this.bob).mint(deliveryPrice);
            await this.dai.connect(this.bob).approve(this.forward721.address, deliveryPrice)
            await this.forward721.connect(this.bob).deliver(0);
        }

        await network.provider.send("evm_increaseTime", [challengePeriod])
        await network.provider.send('evm_mine');
        // now into settling period, yet seller not deliver
        order = await this.forward721.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.buyerShare.toString()).to.equal(buyerMargin)
        expect(order.buyerDelivery).to.equal(true)
        expect(order.sellerDelivery).to.equal(false)
        expect((await this.forward721.checkOrderState(0)).toString()).to.equal("5") // unsettled 
        let oldCfee = await this.forward721.cfee();
        await this.forward721.connect(this.carol).settle(0)
        let newCfee = await this.forward721.cfee();

        // calculate cfee
        let cfee = (new BN(sellerMargin)).mul(this.opFee).divn(new BN(this.base));
        // console.log("cfee       : ", cfee.toString())
        // console.log("actual cfee: ", (newCfee.sub(oldCfee)).toString())
        expect(newCfee.sub(oldCfee).toString()).to.equal(cfee.toString())
    })
    it("should take buyer's margin if only seller deliverred correctly", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 10 * 60;
        let deliveryPrice = toWei("123", "ether");
        let deliveryPeriod = 20 * 60;
        let challengePeriod = 10 * 60;
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let order;
        {
            await this.dai.connect(this.alice).mint(toWei("2", "ether"));
            await this.dai.connect(this.alice).approve(this.forward721.address, toWei("2", "ether"))
            await this.forward721.connect(this.alice).createOrder(
                tokenIds,
                10 * 60,
                deliveryPrice,
                deliveryPeriod,
                challengePeriod,
                [],
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            );
            await this.dai.connect(this.bob).mint(buyerMargin);
            await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
            await this.forward721.connect(this.bob).takeOrder(0);

            await network.provider.send("evm_increaseTime", [orderValidPeriod + deliveryPeriod])
            await network.provider.send('evm_mine');
            
            // seller delivers
            for (let i = 0; i < tokenIds.length; i++) {
                await this.nft.connect(this.alice).mint(this.alice.address, tokenIds[i]);
                await this.nft.connect(this.alice).approve(this.forward721.address, tokenIds[i]);
            }
            await this.forward721.connect(this.alice).deliver(0);
            order = await this.forward721.orders(0);
            expect(order.sellerDelivery).to.equal(true);
        }

        // now into settling period, yet buyer not deliver
        await network.provider.send("evm_increaseTime", [challengePeriod])
        await network.provider.send('evm_mine');
        
        order = await this.forward721.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.buyerShare.toString()).to.equal(buyerMargin)
        expect(order.buyerDelivery).to.equal(false)
        expect(order.sellerDelivery).to.equal(true)
        expect((await this.forward721.checkOrderState(0)).toString()).to.equal("5") // challenging
        let oldCfee = await this.forward721.cfee();
        await this.forward721.connect(this.carol).settle(0)
        let newCfee = await this.forward721.cfee();

        // calculate cfee
        let cfee = (new BN(buyerMargin)).mul(this.opFee).divn(new BN(this.base));
        // console.log("cfee       : ", cfee.toString())
        // console.log("actual cfee: ", (newCfee.sub(oldCfee)).toString())
        expect((newCfee.sub(oldCfee)).toString()).to.equal(cfee.toString())
    })
    it("Should invoke factory.collectFee correctly", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 10 * 60;
        let deliveryPrice = toWei("123", "ether");
        let deliveryPeriod = 20 * 60;
        let challengePeriod = 10 * 60;
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let order;
        {
            await this.dai.connect(this.alice).mint(toWei("2", "ether"));
            await this.dai.connect(this.alice).approve(this.forward721.address, toWei("2", "ether"))
            await this.forward721.connect(this.alice).createOrder(
                tokenIds,
                10 * 60,
                deliveryPrice,
                deliveryPeriod,
                challengePeriod,
                [],
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            );
            await this.dai.connect(this.bob).mint(buyerMargin);
            await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
            await this.forward721.connect(this.bob).takeOrder(0);

            await network.provider.send("evm_increaseTime", [orderValidPeriod + deliveryPeriod])
            await network.provider.send('evm_mine');
            // now into challenge period or delivery period

            // seller delivers
            for (let i = 0; i < tokenIds.length; i++) {
                await this.nft.connect(this.alice).mint(this.alice.address, tokenIds[i]);
                await this.nft.connect(this.alice).approve(this.forward721.address, tokenIds[i]);
            }
            await this.forward721.connect(this.alice).deliver(0);
            // buyer-bob should have 1 + 123 - 0.0123 - 123 = 0.9877
            // seller-alice should have 2 + 123 - 0.0123 = 124.9877
            // forward should have 0.0246
            // supply should be 3+123 = 125

            // buyer delivers and settle
            await this.dai.connect(this.bob).mint(deliveryPrice);
            await this.dai.connect(this.bob).approve(this.forward721.address, deliveryPrice)
            await this.forward721.connect(this.bob).deliver(0);
        }
        let cfee0 = await this.forward721.cfee();
        await expectRevert(this.factory.connect(this.bob).collectFee(this.alice.address, [0]), "Ownable: caller is not the owner") 
        await this.factory.connect(this.alice).collectFee(this.carol.address, ['0'])
        expect((await this.dai.balanceOf(this.carol.address)).toString()).to.equal(cfee0.toString());
    })
    it("Should invoke factory.withdrawOther successfully", async() => {
        let dai1 = await this.Dai.deploy("Dai Token", "DAI", 0)
        await dai1.deployed()
        await dai1.connect(this.alice).mint(100);
        dai1.connect(this.alice).transfer(this.forward721.address, 100)
        await expectRevert(
            this.factory.connect(this.bob).withdrawOther(0, dai1.address, this.carol.address),
            "!auth"
        );
        await this.factory.connect(this.alice).withdrawOther(0, dai1.address, this.carol.address);
        expect((await dai1.balanceOf(this.carol.address)).toString()).to.equal("100")
    })
    it("Should invoke factory.pausePools and unpausePools correctly", async()=> {
        await expectRevert(this.factory.connect(this.bob).pausePools([0]), "Ownable: caller is not the owner")
        await this.factory.connect(this.alice).pausePools([0])
        
        let tokenIds = [0, 1];
        let orderValidPeriod = 10 * 60;
        let deliveryPrice = toWei("123", "ether");
        let deliveryPeriod = 20 * 60;
        let challengePeriod = 10 * 60;
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        
        await expectRevert(
            this.forward721.connect(this.alice).createOrder(
                tokenIds,
                10 * 60,
                deliveryPrice,
                deliveryPeriod,
                challengePeriod,
                [],
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            ),
            "paused"
        );

        await this.factory.connect(this.alice).unpausePools([0])
        expect((await this.forward721.ordersLength()).toString()).to.equal("0")
        {
            await this.dai.connect(this.alice).mint(toWei("2", "ether"));
            await this.dai.connect(this.alice).approve(this.forward721.address, toWei("2", "ether"))
            const tx = await this.forward721.connect(this.alice).createOrder(
                tokenIds,
                10 * 60,
                deliveryPrice,
                deliveryPeriod,
                challengePeriod,
                [],
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            );
            console.log("gasLimit-----createOrder----: ", tx.gasLimit.toString()) // 37.2.8k better than archeNetwork
        }
        expect((await this.forward721.ordersLength()).toString()).to.equal("1")    
    })
    it("Should takeOrder, deliver, settle correctly if hVault is enabled", async() => {
        {
            await expectRevert(this.forward721.connect(this.bob).setForwardVault(this.hVault.address), "Ownable: caller is not the owner") 
            await this.factory.connect(this.alice).setForwardVault(0, this.hVault.address)
            // to avoid yVault's raising error from getPricePerFullShare due to dividing by zero, we deposit to yVault
            await this.dai.connect(this.alice).mint(toWei("100"))
            await this.dai.connect(this.alice).approve(this.yVault.address, toWei("100"))
            await this.yVault.deposit(toWei("100"))
            // yVault(b:100, t:100)
            expect((await this.yVault.getPricePerFullShare()).toString()).to.equal(toWei("1", "ether"))
            await this.dai.connect(this.alice).mint(toWei("1"))
            await this.dai.connect(this.alice).transfer(this.yVault.address, toWei("1"))
            expect((await this.yVault.getPricePerFullShare()).toString()).to.equal(toWei("1.01", "ether"))
            // yVault(b:101, t:100)
        }

        let tokenIds = [0, 1];
        let orderValidPeriod = 10 * 60;
        let deliveryPrice = toWei("100", "ether");
        let deliveryPeriod = 20 * 60;
        let challengePeriod = 10 * 60;
        let buyerMargin = toWei("10", "ether");
        let sellerMargin = toWei("20", "ether");
        let deposit = false;
        let isSeller = true;
        {
            // yVault(b:101, t:100), hVault(shares:0, balance:0, totalsupply:0)
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
            await this.forward721.connect(this.alice).createOrder(
                tokenIds,
                orderValidPeriod,
                deliveryPrice,
                deliveryPeriod,
                challengePeriod,
                [],
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            );
            // add profits to yVault
            let yVaultPrice;
            let yVaultSupply;
            let hVaultSharesInY;
            let hVaultSupply;
            let hVaultPrice;
            {
                let order = await this.forward721.orders(0);
                expect(order.sellerShare.toString()).to.equal(sellerMargin)
                await this.hVault.rebase();
                // yVault(b:101+20*0.8=117, t:117*100/101), hVault(shares:117*100/101-100, b:20, t:20)
                await this.dai.connect(this.alice).mint(toWei("1"))
                await this.dai.connect(this.alice).transfer(this.yVault.address, toWei("1"))
                // yVault(b:118, t:117*100/101), hVault(s:117*100/101-100, b:h.s/y.b*y.t + 4, t:20)
                yVaultSupply = toWeiBN("117").mul(toWeiBN("100")).div(toWeiBN("101"))
                yVaultPrice = toWeiBN("118").mul(toWeiBN("101")).mul(toWeiBN("1")).div(toWeiBN("117")).div(toWeiBN("100"))
                expect((await this.yVault.getPricePerFullShare()).toString()).to.equal(yVaultPrice.toString())
                hVaultSharesInY = toWeiBN("117").mul(toWeiBN("100")).div(toWeiBN("101")).sub(toWeiBN("100"))
                expect((await this.yVault.balanceOf(this.hVault.address)).toString()).to.equal(hVaultSharesInY.toString())
                hVaultPrice = hVaultSharesInY.mul(yVaultPrice).div(toWeiBN("1")).add(toWeiBN("4")).mul(toWeiBN("1")).div(toWeiBN("20"))
                expect((await this.hVault.getPricePerFullShare()).toString()).to.equal(hVaultPrice.toString())
                expect((await this.forward721.getPricePerFullShare()).toString()).to.equal(hVaultPrice.toString())
                hVaultSupply = toBN((await this.hVault.totalSupply()).toString())
            }
            // buyer take order
            let buyerShare;
            {
                await this.dai.connect(this.bob).mint(buyerMargin);
                await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
                await this.forward721.connect(this.bob).takeOrder(0);
                let hVaultBal = hVaultSupply.mul(hVaultPrice).div(toWeiBN("1"))
                buyerShare = toBN(buyerMargin).mul(hVaultSupply).div(hVaultBal)
                expect(equals(toBN((await this.forward721.orders(0)).buyerShare.toString()), buyerShare)).to.equal(true)

            }
            // Too complex to continue the mathamatic calculation....!

        }
    })
})

function toWeiBN(obj) {
    return toBN(toWei(obj))
}
function equals(obj1, obj2) {
    let diff = obj1.sub(obj2);
    return diff < new BN(100); // tolerance is 100 wei
}