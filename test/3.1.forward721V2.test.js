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
        this.Forward721Imp = await ethers.getContractFactory("Forward721UpgradeableV2")
        this.Factory721 = await ethers.getContractFactory("Factory721Upgradeable")

        this.YVault = await ethers.getContractFactory("MockYVault")
        this.FVault = await ethers.getContractFactory("ForwardVaultUpgradeable")

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
        this.factory721 = await upgrades.deployProxy(
            this.Factory721,
            [this.forward721Imp.address, [this.dai.address], this.alice.address, this.opFee.toString()],
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
        
        await this.factory721.connect(this.alice).deployPool(this.nft.address, 721, this.dai.address)
        this.forward721 = await this.Forward721Imp.attach(await this.factory721.allPairs(0));
    })

    it("should deployPool correctly", async() => {
        expect((await this.factory721.allPairsLength()).toString()).to.equal("1");
        expect(await this.factory721.getPair(this.nft.address, this.dai.address)).to.equal(this.forward721.address)
    })
    
    
    it("should createOrder correctly", async()=> {
        let tokenIds = [0, 1];
        let orderValidPeriod = 7 * 24 * 3600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let deliveryPeriod = 12 * 3600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let now = await time.latest();

        let deliverStart = now.addn(nowToDeliverPeriod);
        await this.dai.connect(this.alice).mint(sellerMargin);
        await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
        await this.forward721.connect(this.alice).createOrderFor(
            this.alice.address,
            tokenIds,
            [orderValidPeriod,
            deliverStart.toString(),
            deliveryPeriod],
            [deliveryPrice,
            buyerMargin,
            sellerMargin],
            [],
            deposit,
            isSeller
        );

        now = await time.latest();
        validTill = now.addn(orderValidPeriod);
        
        let expireStart = deliverStart.addn(deliveryPeriod);

        let order = await this.forward721.orders(0);
        // console.log("order is ", JSON.stringify(order))
        // console.log("order.buyer is ", order.buyer)
        expect(order.buyer).to.equal(constants.ZERO_ADDRESS)
        expect(order.buyerMargin.toString()).to.equal(buyerMargin)
        // expect(order.buyerShare.toString()).to.equal("0")
        expect(order.seller).to.equal(this.alice.address)
        expect(order.sellerMargin.toString()).to.equal(sellerMargin)
        // expect(order.sellerShare.toString()).to.equal(sellerMargin)
        expect(order.validTill.toString()).to.equal(validTill.toString())
        expect(order.deliveryPrice.toString()).to.equal(deliveryPrice)
        expect(order.deliverStart.toString()).to.equal(deliverStart.toString())
        expect(order.state.toString()).to.equal("1") // active
        expect(order.sellerDelivered).to.equal(deposit && isSeller);
        expect(order.buyerDelivered).to.equal(deposit && !isSeller);
        
        expect((await this.forward721.ordersLength()).toString()).to.equal("1")
    })
    
    it("should NOT take order", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 7 * 24 * 3600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let deliveryPeriod = 12 * 3600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let now = await time.latest();
        
        {
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
            await this.forward721.connect(this.alice).createOrderFor(
                this.alice.address,
                tokenIds,
                [orderValidPeriod,
                now.toNumber() + nowToDeliverPeriod,
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller
            );
        }

        await expectRevert(
            this.forward721.connect(this.bob).takeOrderFor(this.bob.address, 1),
            "!active"
        );

        await network.provider.send("evm_increaseTime", [orderValidPeriod + 100])
        await network.provider.send('evm_mine');
        await expectRevert(
            this.forward721.connect(this.bob).takeOrderFor(this.alice.address, 0),
            "!active"
        );
        expect((await this.forward721.checkOrderState(0)).toString()).to.equal("3") // dead

    })
    it("should take order correctly", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 7 * 24 * 3600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let deliveryPeriod = 12 * 3600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let now = await time.latest();
        
        {
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
            await this.forward721.connect(this.alice).createOrderFor(
                this.alice.address,
                tokenIds,
                [orderValidPeriod,
                now.toNumber() + nowToDeliverPeriod,
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller
            );
        }
        await this.dai.connect(this.bob).mint(buyerMargin);
        expect((await this.dai.balanceOf(this.bob.address)).toString()).to.equal(buyerMargin);
        await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
        expect((await this.dai.allowance(this.bob.address, this.forward721.address)).toString()).to.equal(buyerMargin);
        await this.forward721.connect(this.bob).takeOrderFor(this.bob.address, 0);
        let order = await this.forward721.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.state.toString()).to.equal("2") // order filled
    })
    it("should deliver correctly for both seller and buyer", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 7 * 24 * 3600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let deliveryPeriod = 12 * 3600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let now = await time.latest();
        let order;
        {
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
            await this.forward721.connect(this.alice).createOrderFor(
                this.alice.address,
                tokenIds,
                [orderValidPeriod,
                now.toNumber() + nowToDeliverPeriod,
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller
            );
            await this.dai.connect(this.bob).mint(buyerMargin);
            await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
            await this.forward721.connect(this.bob).takeOrderFor(this.bob.address, 0);
        }

        await network.provider.send("evm_increaseTime", [nowToDeliverPeriod])
        await network.provider.send('evm_mine');
        // now into challenge period or delivery period
        order = await this.forward721.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect((await this.forward721.checkOrderState(0)).toString()).to.equal("4") // delivering

        // seller delivers
        for (let i = 0; i < tokenIds.length; i++) {
            await this.nft.connect(this.alice).mint(this.alice.address, tokenIds[i]);
            await this.nft.connect(this.alice).approve(this.forward721.address, tokenIds[i]);
        }
        await this.forward721.connect(this.alice).deliverFor(this.alice.address, 0);
        order = await this.forward721.orders(0);
        expect(order.sellerDelivered).to.equal(true);
        
        // buyer delivers and settle
        await this.dai.connect(this.bob).mint(deliveryPrice);
        await this.dai.connect(this.bob).approve(this.forward721.address, deliveryPrice)
        await this.forward721.connect(this.bob).deliverFor(this.bob.address, 0);
        
        order = await this.forward721.orders(0);
        expect(order.buyerDelivered).to.equal(true);
        expect(order.state.toString()).to.equal("6"); // settled
        // calculate cfee
        let cfee = (new BN(deliveryPrice)).mul(new BN(2)).mul(this.opFee).divn(new BN(this.base)); // * 2 means taking fee from both sides
        // console.log("cfee       : ", cfee.toString())
        // console.log("actual cfee: ", (await this.forward721.cfee()).toString())
        expect((await this.forward721.cfee()).toString()).to.equal(cfee.toString())
        
    })
    it("should take seller's margin if only buyer deliverred correctly", async() => {
        let tokenIds = [0, 1];
        let orderValidPeriod = 7 * 24 * 3600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let deliveryPeriod = 12 * 3600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let now = await time.latest();
        let order;
        {
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
            await this.forward721.connect(this.alice).createOrderFor(
                this.alice.address,
                tokenIds,
                [orderValidPeriod,
                now.toNumber() + nowToDeliverPeriod,
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller
            );
            await this.dai.connect(this.bob).mint(buyerMargin);
            await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
            await this.forward721.connect(this.bob).takeOrderFor(this.bob.address, 0);
            
            
            // buyer delivers 
            await network.provider.send("evm_increaseTime", [nowToDeliverPeriod])
            await this.dai.connect(this.bob).mint(deliveryPrice);
            await this.dai.connect(this.bob).approve(this.forward721.address, deliveryPrice)
            await this.forward721.connect(this.bob).deliverFor(this.bob.address, 0);
        }

        await network.provider.send("evm_increaseTime", [deliveryPeriod])
        await network.provider.send('evm_mine');
        // now into settling period, yet seller not deliver
        order = await this.forward721.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.buyerDelivered).to.equal(true)
        expect(order.sellerDelivered).to.equal(false)
        expect((await this.forward721.checkOrderState(0)).toString()).to.equal("5") // expired and unsettled 
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
        let orderValidPeriod = 7 * 24 * 3600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let deliveryPeriod = 12 * 3600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let now = await time.latest();
        let order;
        {
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
            await this.forward721.connect(this.alice).createOrderFor(
                this.alice.address,
                tokenIds,
                [orderValidPeriod,
                now.toNumber() + nowToDeliverPeriod,
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller
            );
            await this.dai.connect(this.bob).mint(buyerMargin);
            await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
            await this.forward721.connect(this.bob).takeOrderFor(this.bob.address, 0);

            await network.provider.send("evm_increaseTime", [nowToDeliverPeriod])
            await network.provider.send('evm_mine');
            
            // seller delivers
            for (let i = 0; i < tokenIds.length; i++) {
                await this.nft.connect(this.alice).mint(this.alice.address, tokenIds[i]);
                await this.nft.connect(this.alice).approve(this.forward721.address, tokenIds[i]);
            }
            await this.forward721.connect(this.alice).deliverFor(this.alice.address, 0);
            order = await this.forward721.orders(0);
            expect(order.sellerDelivered).to.equal(true);
        }

        // now into settling period, yet buyer not deliver
        await network.provider.send("evm_increaseTime", [deliveryPeriod])
        await network.provider.send('evm_mine');
        
        order = await this.forward721.orders(0);
        expect(order.buyer).to.equal(this.bob.address)
        expect(order.buyerDelivered).to.equal(false)
        expect(order.sellerDelivered).to.equal(true)
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
        let orderValidPeriod = 7 * 24 * 3600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let deliveryPeriod = 12 * 3600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let now = await time.latest();
        let order;
        {
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
            await this.forward721.connect(this.alice).createOrderFor(
                this.alice.address,
                tokenIds,
                [orderValidPeriod,
                now.toNumber() + nowToDeliverPeriod,
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller
            );
            await this.dai.connect(this.bob).mint(buyerMargin);
            await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
            await this.forward721.connect(this.bob).takeOrderFor(this.bob.address, 0);

            await network.provider.send("evm_increaseTime", [nowToDeliverPeriod])
            await network.provider.send('evm_mine');
            // now into challenge period or delivery period

            // seller delivers
            for (let i = 0; i < tokenIds.length; i++) {
                await this.nft.connect(this.alice).mint(this.alice.address, tokenIds[i]);
                await this.nft.connect(this.alice).approve(this.forward721.address, tokenIds[i]);
            }
            await this.forward721.connect(this.alice).deliverFor(this.alice.address, 0);
            // buyer-bob should have 1 + 123 - 0.0123 - 123 = 0.9877
            // seller-alice should have 2 + 123 - 0.0123 = 124.9877
            // forward should have 0.0246
            // supply should be 3+123 = 125

            // buyer delivers and settle
            await this.dai.connect(this.bob).mint(deliveryPrice);
            await this.dai.connect(this.bob).approve(this.forward721.address, deliveryPrice)
            await this.forward721.connect(this.bob).deliverFor(this.bob.address, 0);
        }
        let cfee0 = await this.forward721.cfee();
        await expectRevert(this.factory721.connect(this.bob).collectFee(this.alice.address, [0]), "Ownable: caller is not the owner") 
        await this.factory721.connect(this.alice).collectFee(this.carol.address, ['0'])
        expect((await this.dai.balanceOf(this.carol.address)).toString()).to.equal(cfee0.toString());
    })
    it("Should invoke factory.withdrawOther successfully", async() => {
        let dai1 = await this.Dai.deploy("Dai Token", "DAI", 0)
        await dai1.deployed()
        await dai1.connect(this.alice).mint(100);
        dai1.connect(this.alice).transfer(this.forward721.address, 100)
        await expectRevert(
            this.factory721.connect(this.bob).withdrawOther(0, dai1.address, this.carol.address),
            "!auth"
        );
        await this.factory721.connect(this.alice).withdrawOther(0, dai1.address, this.carol.address);
        expect((await dai1.balanceOf(this.carol.address)).toString()).to.equal("100")
    })
    it("Should invoke factory.pausePools and unpausePools correctly", async()=> {
        await expectRevert(this.factory721.connect(this.bob).pausePools([0]), "Ownable: caller is not the owner")
        await this.factory721.connect(this.alice).pausePools([0])
        
        let tokenIds = [0, 1];
        let orderValidPeriod = 7 * 24 * 3600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let deliveryPeriod = 12 * 3600;
        let deliveryPrice = toWei("123", "ether");
        let buyerMargin = toWei("1", "ether");
        let sellerMargin = toWei("2", "ether");
        let deposit = false;
        let isSeller = true;
        let validTill;
        let now = await time.latest();
        let order;
        
        await expectRevert(
            this.forward721.connect(this.alice).createOrderFor(
                this.alice.address,
                tokenIds,
                [orderValidPeriod,
                now.toNumber() + nowToDeliverPeriod,
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller
            ),
            "paused"
        );

        await this.factory721.connect(this.alice).unpausePools([0])
        expect((await this.forward721.ordersLength()).toString()).to.equal("0")
        {
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
            const tx = await this.forward721.connect(this.alice).createOrderFor(
                this.alice.address,
                tokenIds,
                [orderValidPeriod,
                now.toNumber() + nowToDeliverPeriod,
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller
            );
            console.log("gasLimit-----createOrder----: ", tx.gasLimit.toString()) // 37.2.8k better than archeNetwork
        }
        expect((await this.forward721.ordersLength()).toString()).to.equal("1")    
    })
    it("Should takeOrder, deliver, settle correctly if hVault is enabled", async() => {
        {
            await expectRevert(this.forward721.connect(this.bob).setForwardVault(this.fVault.address), "!factory") 
            await this.factory721.connect(this.alice).setForwardVault(0, this.fVault.address)
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
        let orderValidPeriod = 7 * 24 * 3600;
        let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
        let deliveryPeriod = 12 * 3600;
        let deliveryPrice = toWei("100", "ether");
        let buyerMargin = toWei("10", "ether");
        let sellerMargin = toWei("20", "ether");
        let deposit = false;
        let isSeller = true;
        let now = await time.latest();
        {
            // yVault(b:101, t:100), hVault(shares:0, balance:0, totalsupply:0)
            await this.dai.connect(this.alice).mint(sellerMargin);
            await this.dai.connect(this.alice).approve(this.forward721.address, sellerMargin)
            await this.forward721.connect(this.alice).createOrderFor(
                this.alice.address,
                tokenIds,
                [orderValidPeriod,
                now.toNumber() + nowToDeliverPeriod,
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller
            );
            // add profits to yVault
            let yVaultPrice;
            let yVaultSupply;
            let hVaultSharesInY;
            let fVaultSupply;
            let fVaultPrice;
            {
                let order = await this.forward721.orders(0);
                expect(order.sellerShare.toString()).to.equal(sellerMargin)
                await this.fVault.rebase();
                // yVault(b:101+20*0.8=117, t:117*100/101), hVault(shares:117*100/101-100, b:20, t:20)
                await this.dai.connect(this.alice).mint(toWei("1"))
                await this.dai.connect(this.alice).transfer(this.yVault.address, toWei("1"))
                // yVault(b:118, t:117*100/101), hVault(s:117*100/101-100, b:h.s/y.b*y.t + 4, t:20)
                yVaultSupply = toWeiBN("117").mul(toWeiBN("100")).div(toWeiBN("101"))
                yVaultPrice = toWeiBN("118").mul(toWeiBN("101")).mul(toWeiBN("1")).div(toWeiBN("117")).div(toWeiBN("100"))
                expect((await this.yVault.getPricePerFullShare()).toString()).to.equal(yVaultPrice.toString())
                hVaultSharesInY = toWeiBN("117").mul(toWeiBN("100")).div(toWeiBN("101")).sub(toWeiBN("100"))
                expect((await this.yVault.balanceOf(this.fVault.address)).toString()).to.equal(hVaultSharesInY.toString())
                fVaultPrice = hVaultSharesInY.mul(yVaultPrice).div(toWeiBN("1")).add(toWeiBN("4")).mul(toWeiBN("1")).div(toWeiBN("20"))
                expect((await this.fVault.getPricePerFullShare()).toString()).to.equal(fVaultPrice.toString())
                expect((await this.forward721.getPricePerFullShare()).toString()).to.equal(fVaultPrice.toString())
                fVaultSupply = toBN((await this.fVault.totalSupply()).toString())
            }
            // buyer take order
            let buyerShare;
            {
                await this.dai.connect(this.bob).mint(buyerMargin);
                await this.dai.connect(this.bob).approve(this.forward721.address, buyerMargin);
                await this.forward721.connect(this.bob).takeOrderFor(this.bob.address, 0);
                let hVaultBal = fVaultSupply.mul(fVaultPrice).div(toWeiBN("1"))
                buyerShare = toBN(buyerMargin).mul(fVaultSupply).div(hVaultBal)
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