const { ethers, upgrades } = require('hardhat')
const { expect } = require('chai')
const {
    BN,
    constants,
    expectEvent,
    expectRevert,
} = require('@openzeppelin/test-helpers')

let owner, alice, bob, carl

let factory

describe('Factory', function () {
    before('deploy', async () => {
        signers = await ethers.getSigners()
        owner = signers[0]
        alice = signers[1]
        bob = signers[2]
        feeCollector = signers[3]

        const chainId = (await signers[0].getChainId()).toString()
        console.log('chainId: ', chainId)
        this.dai = alice.address
        this.weth = bob.address

        const Forward721Imp = await ethers.getContractFactory(
            'Forward721Upgradeable'
        )

        const forward721Imp = await Forward721Imp.deploy()
        await forward721Imp.deployed()
        console.log('forward721Imp.address: ', forward721Imp.address)

        const Factory = await ethers.getContractFactory('Factory721Upgradeable')
        factory = await upgrades.deployBeacon(
            Factory,
            [forward721Imp.address, [this.dai], feeCollector.address, 1],
            {
                initializer: '__FactoryUpgradeable__init',
            }
        )
        await factory.deployed()
        console.log('factory.address: ', factory.address)
    })

    it('Should setFee correctly', async () => {
        await factory.connect(owner).setFee(10)
        expect((await factory.fee()).toString()).to.equal('10')
        expect(await factory.ifMarginSupported(this.dai)).to.eq(true)
    })
    it('Should supportMargin and disableMargin correctly', async () => {
        expect((await factory.fee()).toString()).to.equal('10')
        expect(await factory.ifMarginSupported(bob.address)).to.eq(false)
        await factory.connect(owner).supportMargin(bob.address)
        expect(await factory.ifMarginSupported(bob.address)).to.eq(true)
        await factory.connect(owner).disableMargin(bob.address)
        expect(await factory.ifMarginSupported(bob.address)).to.eq(false)
    })

    it('Should be upgradeable for factory', async () => {
        expect(await factory.version()).to.equal('v1.0')
        const TestFactoryUpgrade = await ethers.getContractFactory(
            'TestFactoryUpgrade'
        )

        const upgraded = await upgrades.upgradeBeacon(
            factory.address,
            TestFactoryUpgrade
        )
        console.log('await upgraded.version()', await upgraded.version())
        // expect(await upgraded.version()).to.equal('v1.1')
        // expect((await factory.fee()).toString()).to.equal('10')
        // expect(await factory.version()).to.equal('v1.1')
    })

    it('Should deploy pool correctly', async () => {
        expect((await factory.allPairsLength()).toString()).to.equal('0')
        await expectRevert(
            factory.connect(alice).deployPool(alice.address, 721, this.dai),
            '!poolDeployer'
        )
        await factory.connect(owner).deployPool(alice.address, 721, this.dai)
        expect((await factory.allPairsLength()).toString()).to.equal('1')
        await expectRevert(
            factory.connect(owner).deployPool(alice.address, 721, this.dai),
            'pool exist'
        )
        expect((await factory.allPairsLength()).toString()).to.equal('1')
    })

    // it('Should upgrade all forward impl once upgrade forward', async () => {
    //     await factory.connect(owner).supportMargin(this.weth)
    //     await factory.connect(owner).deployPool(alice.address, 721, this.weth)
    //     expect((await factory.allPairsLength()).toString()).to.equal('2')
    //     let Forward721Imp = await ethers.getContractFactory(
    //         'Forward721Upgradeable'
    //     )
    //     let forward721_1V1_0 = await Forward721Imp.attach(
    //         await factory.allPairs(0)
    //     )
    //     let forward721_2V1_0 = await Forward721Imp.attach(
    //         await factory.allPairs(1)
    //     )
    //     expect((await forward721_1V1_0.version()).toString()).to.equal('v1.0')
    //     expect((await forward721_2V1_0.version()).toString()).to.equal('v1.0')

    //     let factory_implementation = await factory.implementation()
    //     console.log('factory.implementation(): ', factory_implementation)

    //     const Forward721V1_1 = await ethers.getContractFactory(
    //         'TestForward721Upgrade'
    //     )
    //     const forward721v1_1 = await Forward721V1_1.deploy()
    //     await forward721v1_1.deployed()
    //     console.log('forward721v1_1.1.address: ', forward721v1_1.address)

    //     // upgrade all forward contracts logic to v1_1
    //     await factory.upgradeTo(forward721v1_1.address)

    //     expect((await forward721_1V1_0.version()).toString()).to.equal('v1.1')
    //     expect((await forward721_2V1_0.version()).toString()).to.equal('v1.1')
    // })
    // it('Should pause all forward once factory pause the impl', async () => {
    //     expect(await factory.paused()).to.equal(false)
    //     await factory.pause()
    //     expect(await factory.paused()).to.equal(true)

    //     let Forward721Imp = await ethers.getContractFactory(
    //         'TestForward721Upgrade'
    //     )
    //     let forward721_2V1_1 = await Forward721Imp.attach(
    //         await factory.allPairs(1)
    //     )
    //     await expectRevert(forward721_2V1_1.version(), 'paused')

    //     await factory.unpause()
    //     expect(await factory.paused()).to.equal(false)
    //     expect(await forward721_2V1_1.version()).to.equal('v1.1')
    // })
})
