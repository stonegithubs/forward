const { ethers, upgrades, network } = require('hardhat')
const {
    BN,
    constants,
    expectEvent,
    expectRevert,
    time,
} = require('@openzeppelin/test-helpers')
const { expect } = require('chai')
const Web3 = require('web3')
const toWei = Web3.utils.toWei
const toBN = Web3.utils.toBN
describe('Forward721 TestCase with marginToken as ERC20', function () {
    before(async () => {
        this.signers = await ethers.getSigners()
        this.alice = this.signers[0]
        this.bob = this.signers[1]
        this.carol = this.signers[2]
        this.signer = this.signers[3]
        this.WETH = await ethers.getContractFactory('WETH9')
        this.Dai = await ethers.getContractFactory('MockERC20')
        this.Potter = await ethers.getContractFactory('Potter')
        this.Forward721Imp = await ethers.getContractFactory(
            'Forward721Upgradeable'
        )
        this.Factory721 = await ethers.getContractFactory(
            'Factory721Upgradeable'
        )

        this.YVault = await ethers.getContractFactory('MockYVault')
        this.FVault = await ethers.getContractFactory('ForwardVaultUpgradeable')
        this.Router = await ethers.getContractFactory('ForwardEtherRouter')
    })
    beforeEach(async () => {
        this.weth = await this.WETH.deploy()
        await this.weth.deployed()

        this.yVault = await this.YVault.deploy(this.weth.address)
        await this.yVault.deployed()

        this.forward721Imp = await this.Forward721Imp.deploy()
        await this.forward721Imp.deployed()

        this.opFee = new BN(250) // 250/10000
        this.factory721 = await upgrades.deployProxy(
            this.Factory721,
            [
                this.forward721Imp.address,
                [this.weth.address],
                this.alice.address,
                this.opFee.toString(),
            ],
            {
                initializer: '__FactoryUpgradeable__init',
            }
        )

        this.min = 8000
        this.base = 10000
        this.tolerance = 500
        this.fVault = await upgrades.deployProxy(
            this.FVault,
            [
                this.weth.address,
                this.yVault.address,
                this.alice.address,
                this.min,
                this.tolerance,
            ],
            {
                initializer: '__ForwardVaultUpgradeable_init',
            }
        )

        this.potter = await this.Potter.deploy(
            'initBaseUri',
            this.signer.address,
            2,
            5555,
            555
        )
        await this.potter.deployed()

        await this.factory721
            .connect(this.alice)
            .deployPool(this.potter.address, 721, this.weth.address)
        this.forward721 = await this.Forward721Imp.attach(
            await this.factory721.allPairs(0)
        )
        this.router = await this.Router.deploy(this.weth.address)
        await this.router.deployed()

        await this.potter.setForward(
            this.forward721.address,
            this.router.address
        )
    })

    it('should deployPool correctly', async () => {
        expect((await this.factory721.allPairsLength()).toString()).to.equal(
            '1'
        )
        expect(
            await this.factory721.getPair(
                this.potter.address,
                this.weth.address
            )
        ).to.equal(this.forward721.address)
    })

    it('should reserve correctly', async () => {
        await expectRevert(
            this.potter.connect(this.alice).reserve(this.alice.address, 3),
            'XRC: can only mint a multiple of the maxBatchSize'
        )
        await this.potter.reserve(this.alice.address, 2)
        expect((await this.potter.totalSupply()).toString()).to.equal('2')
    })
    it('should preSale correctly', async () => {
        expect((await this.potter.status()).toString()).to.equal('0') // pending
        await expectRevert(
            this.potter.connect(this.bob).setStatus(1),
            'Ownable: caller is not the owner'
        )
        await this.potter.connect(this.alice).setStatus(1)
        expect((await this.potter.status()).toString()).to.equal('1') // presale

        const signerWallet = ethers.Wallet.fromMnemonic(
            'radar blur cabbage chef fix engine embark joy scheme fiction master release'
        )
        await this.potter.setSigner(signerWallet.address)
        expect(await this.potter.signer_()).to.equal(signerWallet.address)
        console.log('signerWallet.privateKey = ', signerWallet.privateKey)
        console.log('signerWallet.address = ', signerWallet.address)
        const minter = this.bob
        const sender = minter.address
        const salt = 'salt'

        const digest = ethers.utils.keccak256(
            ethers.utils.defaultAbiCoder.encode(
                ['address', 'address', 'string'],
                [
                    sender /** pre minter address */,
                    this.potter.address /** potter contract address */,
                    salt /** random salt */,
                ]
            )
        )
        // const signerPk = this.signer.signMessage() we don't use this method, to reduce contract gas usage, we will use sign digest directly
        const signingKey = new ethers.utils.SigningKey(signerWallet.privateKey)
        const sig = signingKey.signDigest(digest)
        expect(ethers.utils.recoverAddress(digest, sig)).to.equal(
            signerWallet.address
        )
        const sigHex = ethers.utils.joinSignature(sig)
        expect(ethers.utils.recoverAddress(digest, sigHex)).to.equal(
            signerWallet.address
        )
        expect(await this.potter.verifySig(sender, salt, sigHex)).to.equal(
            signerWallet.address
        )

        await this.potter
            .connect(this.bob)
            .presaleMint(2, 'salt', sigHex, { value: toWei('0.5') })
        expect(
            (await this.potter.balanceOf(this.bob.address)).toString()
        ).to.equal('2')
    })
})

function toWeiBN(obj) {
    return toBN(toWei(obj))
}
function equals(obj1, obj2) {
    let diff = obj1.sub(obj2)
    return diff < new BN(100) // tolerance is 100 wei
}
