const { ethers, upgrades } = require("hardhat");
const { BN, constants, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { expect } = require("chai");
const Web3 = require('web3');
const toWei = Web3.utils.toWei

describe("Forward721", function() {
    before(async() => {
        this.signers = await ethers.getSigners()
        this.alice = this.signers[0]
        this.bob = this.signers[1]
        this.carol = this.signers[2]

        this.Dai = await ethers.getContractFactory("MockERC20")
        this.Nft = await ethers.getContractFactory("MockERC721")
        this.Forward721Imp = await ethers.getContractFactory("Forward721Upgradeable")
        this.Factory = await ethers.getContractFactory("HedgehogFactoryUpgradeable")

        this.YVault = await ethers.getContractFactory("MockYVault")
        this.HVault = await ethers.getContractFactory("HForwardVaultUpgradeable")

    })
    beforeEach(async() => {
        this.dai = await this.Dai.deploy()
        await this.dai.deployed()
        this.nft = await this.Nft.deploy()
        await this.nft.deployed()
        this.yVault = await this.YVault.deploy(this.dai.address)
        await this.yVault.deployed()

        this.forward721Imp = await this.Forward721Imp.deploy()
        await this.forward721Imp.deployed()

        this.factory = await upgrades.deployProxy(
            this.Factory,
            [this.forward721Imp.address, [this.dai.address], this.alice.address, 1],
            {
                initializer: "initialize"
            }
        );
        this.hVault = await upgrades.deployProxy(
            this.HVault,
            [this.dai.address, this.yVault.address, this.alice.address, 8000, 500],
            {
                initializer: "__HForwardVault_init"
            }
        );
    })

    
})