const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const WETH = artifacts.require("WETH9")
const Dai = artifacts.require("MockERC20")
const Forward20Imp = artifacts.require("Forward20Upgradeable")
const Factory20 =  artifacts.require("Factory20Upgradeable")

const YVault =  artifacts.require("MockYVault")
const FVault = artifacts.require("ForwardVaultUpgradeable")


const toWei = web3.utils.toWei

contract('Forward20Test', (accounts) => {
    beforeEach(async () => {
        this.alice = accounts[0]
        this.bob = accounts[1]
        this.carol = accounts[2]




        
        this.weth = await WETH.deploy();
        await this.weth.deployed();
        
        // as margin
        this.dai = await Dai.deploy("Dai Token", "DAI", 0)
        await this.dai.deployed()
        
        // as the want token, like nft token in forward20
        this.want = await Dai.deploy("Want Token", "WANT", 0)
        await this.want.deployed();

        this.yVault = await YVault.deploy(this.dai.address)
        await this.yVault.deployed()

        this.forward20Imp = await Forward20Imp.deploy()
        await this.forward20Imp.deployed()

        this.opFee = new BN(1); // 1/10000


        this.factory20 = await deployProxy(
            Factory20,
            [this.forward20Imp.address, [this.dai.address], this.alice.address, this.opFee.toString()],
            {
                initializer: "__FactoryUpgradeable__init"
            }
        );
        const tx = await this.factory20.connect(this.alice).deployPool(this.want.address, 20, this.dai.address)
        // console.log("gasLimit-----factory20.deployPool----: ", tx.gasLimit.toString())
    });

    it('should be Comptroller', async () => {
        
    });

    
    

});