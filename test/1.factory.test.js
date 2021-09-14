const { ethers, upgrades } = require("hardhat");
const { expect } = require('chai');
const { BN, constants, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

let owner, alice, bob, carl;

let factory;


describe("Factory", function () {
    before("deploy", async() => {        
        signers = await ethers.getSigners();
        owner = signers[0];
        alice = signers[1];
        bob = signers[2];
        feeCollector = signers[3];

        const chainId = (await signers[0].getChainId()).toString()
        console.log("chainId: ", chainId)
        this.dai = alice.address;
        
        const Forward721Imp = await ethers.getContractFactory(
            "Forward721Upgradeable"
        );
        const forward721Imp = await Forward721Imp.deploy();
        await forward721Imp.deployed();
        console.log('forward721Imp.address: ', forward721Imp.address)

        const Factory = await ethers.getContractFactory(
            "HedgehogFactoryUpgradeable"
        );
        factory = await upgrades.deployProxy(
            Factory,
            [forward721Imp.address, [this.dai], feeCollector.address, 1],
            {
                initializer: "initialize"
            }
        );
        await factory.deployed();
        console.log('factory.address: ', factory.address)
    })

    it("Should setFee correctly", async() => {
        await factory.connect(owner).setFee(10);
        expect((await factory.fee()).toString()).to.equal("10");
        expect(await factory.ifTokenSupported(this.dai)).to.eq(true);
    })
    it("Should supportToken and disableToken correctly", async() => {
        expect((await factory.fee()).toString()).to.equal("10");
        expect(await factory.ifTokenSupported(bob.address)).to.eq(false);
        await factory.connect(owner).supportToken(bob.address);
        expect(await factory.ifTokenSupported(bob.address)).to.eq(true);
        await factory.connect(owner).disableToken(bob.address);
        expect(await factory.ifTokenSupported(bob.address)).to.eq(false);
    })

    it("Should be upgradeable for factory", async() => {
        expect(await factory.version()).to.equal("v1.0")
        const TestFactoryUpgrade = await ethers.getContractFactory(
            "TestFactoryUpgrade"
        );

        const upgraded = await upgrades.upgradeProxy(
            factory.address,
            TestFactoryUpgrade
        );
        expect(await upgraded.version()).to.equal("v1.1")
        expect((await factory.fee()).toString()).to.equal("10");
        expect(await factory.version()).to.equal("v1.1")
    })
    
    it("Should deploy pool correctly", async() => {
        expect((await factory.allPairsLength()).toString()).to.equal("0");
        await factory.connect(alice).deployPool(
            alice.address,
            721,
            this.dai
        );
        expect((await factory.allPairsLength()).toString()).to.equal("1");
        await expectRevert(factory.connect(alice).deployPool(
            alice.address,
            721,
            this.dai
            ), 'pool exist',
        );
        expect((await factory.allPairsLength()).toString()).to.equal("1");
    })
    
    
})