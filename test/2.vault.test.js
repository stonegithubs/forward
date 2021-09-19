const { ethers, upgrades } = require("hardhat");
const { expect } = require('chai');
const { BN, constants, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const Web3 = require('web3');

const toWei = Web3.utils.toWei
describe("Vault", function () {
    before("deploy", async() => {
        
        signers = await ethers.getSigners();
        this.owner = signers[0];
        this.alice = signers[1];
        this.bob = signers[2];
        

        console.log("chainId: ", (await signers[0].getChainId()).toString())

        
        const MockERC20 = await ethers.getContractFactory(
            "MockERC20"
        );
        this.mockERC20 = await MockERC20.connect(this.alice).deploy("Token1", "T1", 10000);
        await this.mockERC20.deployed();
        console.log('mockERC20.address: ', this.mockERC20.address)

        const MockYVault = await ethers.getContractFactory(
            "MockYVault"
        );
        this.mockYVault = await MockYVault.deploy(this.mockERC20.address);
        await this.mockYVault.deployed();
        console.log('mockYVault.address: ', this.mockYVault.address)


        const ForwardVaultUpgradeable = await ethers.getContractFactory(
            "ForwardVaultUpgradeable"
        );
        this.fVault = await upgrades.deployProxy(
            ForwardVaultUpgradeable,
            [this.mockERC20.address, this.mockYVault.address, this.owner.address, 8000, 500],
            {
                initializer: "__ForwardVaultUpgradeable_init"
            }
        );
        await this.fVault.deployed();
        console.log('fVault.address: ', this.fVault.address)

    })

    it("MockYVault Should work correctly", async() => {
        expect(await this.mockERC20.name()).to.equal("Token1")
        await this.mockERC20.connect(this.alice).approve(this.mockYVault.address, toWei("100", "ether"));
        expect((await this.mockERC20.allowance(this.alice.address, this.mockYVault.address)).toString()).to.equal(toWei("100", "ether"))
        
        await this.mockYVault.connect(this.alice).deposit(toWei("100", "ether"));
        let aliceShares = (await this.mockYVault.balanceOf(this.alice.address)).toString();
        expect(aliceShares).to.equal(toWei("100", "ether"));
        expect((await this.mockYVault.getPricePerFullShare()).toString()).to.equal(toWei("1", "ether"))
        await this.mockERC20.connect(this.alice).transfer(this.mockYVault.address, toWei("1", "ether"));
        expect((await this.mockYVault.getPricePerFullShare()).toString()).to.equal(toWei("1.01", "ether"))
        await this.mockYVault.connect(this.alice).withdraw(aliceShares)
        aliceShares = (await this.mockYVault.balanceOf(this.alice.address)).toString();
        expect(aliceShares).to.equal("0")
    })
    it("fVault Should work correctly", async() => {
        // deposit some want token into yVault to prevent err from yVault.getPricePerFullShare()
        await this.mockERC20.connect(this.alice).approve(this.mockYVault.address, toWei("1", "ether"))
        await this.mockYVault.connect(this.alice).deposit(toWei("1", "ether"))

        expect(await this.fVault.name()).to.equal("hoglet forward vault Token1")
        expect(await this.fVault.symbol()).to.equal("hfv T1")
        expect((await this.fVault.balance()).toString()).to.equal("0")
        await expectRevert(
            this.fVault.connect(this.alice).setMinTolerance(10001, 500),
            "!governance"
        )
        await expectRevert(
            this.fVault.connect(this.owner).setMinTolerance(10001, 500),
            "!min"
        )
        await expectRevert(
            this.fVault.connect(this.owner).setMinTolerance(8000, 10000),
            "!tolerance"
        )
        await this.fVault.connect(this.owner).setMinTolerance(8000, 500);
        expect((await this.fVault.min()).toString()).to.equal("8000")
        expect((await this.fVault.tolerance()).toString()).to.equal("500")

        await this.fVault.connect(this.owner).setGovernance(this.alice.address)
        expect(await this.fVault.governance()).to.equal(this.alice.address)
        await this.fVault.connect(this.alice).setGovernance(this.owner.address)
        expect(await this.fVault.governance()).to.equal(this.owner.address)

        await this.mockERC20.connect(this.alice).approve(this.fVault.address, toWei("1", "ether"))
        await this.fVault.connect(this.alice).deposit(toWei("1", "ether"))
        expect((await this.fVault.balanceOf(this.alice.address)).toString()).to.equal(toWei("1", "ether"))
        expect((await this.fVault.getPricePerFullShare()).toString()).to.equal(toWei("1", "ether"))
        

        expect(await this.fVault.version()).to.equal("v1.0")
        const TestVaultUpgrade = await ethers.getContractFactory(
            "TestVaultUpgrade"
        );
        await upgrades.upgradeProxy(
            this.fVault.address,
            TestVaultUpgrade
        );
        expect((await this.fVault.balanceOf(this.alice.address)).toString()).to.equal(toWei("1", "ether"))
        expect(await this.fVault.version()).to.equal("v1.1")

        await this.fVault.connect(this.alice).withdraw(
            await this.fVault.balanceOf(this.alice.address)
        )
        expect((await this.fVault.totalSupply()).toString()).to.equal("0")
    })
    
})