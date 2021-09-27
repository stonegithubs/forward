// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers, upgrades } = require("hardhat");
const utils = require('./utils')

async function main() {
    // Hardhat always runs the compile task when running scripts with its command
    // line interface.
    //
    // If this script is run directly using `node` you may want to call compile
    // manually to make sure everything is compiled
    // await hre.run('compile');
    let config = utils.getConfig();

    const signers = await ethers.getSigners();
    const deployer = signers[0]
    console.log("network is ", network.name)
    
    
    

    if (
        network.name == "local"         /*local node*/
        || network.name == 'ropsten'    /*ropsten testnet */
        ) {
        
        console.log("Deploying account:", await deployer.getAddress());
        console.log(
            "Deploying account balance:",
            (await deployer.getBalance()).toString(),
            "\n"
        );
        
        // We get the contract to deploy
        const Dai = await ethers.getContractFactory("MockERC20")
        const Nft = await ethers.getContractFactory("MockERC721")
        const WETH = await ethers.getContractFactory("WETH9")
        const Forward721Imp = await ethers.getContractFactory("Forward721Upgradeable");
        const Factory721 = await ethers.getContractFactory("Factory721Upgradeable")
        const Router = await ethers.getContractFactory("ForwardEtherRouter")

        if ( !config[network.name].deployed.hasOwnProperty("weth") || config[network.name].deployed.weth == "") {
            const weth = await WETH.deploy()
            await weth.deployed();
            console.log('deploy weth: ', weth.address)
            config[network.name].deployed.weth = weth.address
            utils.saveConfig(config);
        }

        if ( !config[network.name].deployed.hasOwnProperty("dai") || config[network.name].deployed.dai == "") {
            const dai = await Dai.deploy("Dai Token", "DAI", 0)
            await dai.deployed();
            console.log('deploy dai: ', dai.address)
            config[network.name].deployed.dai = dai.address
            utils.saveConfig(config);
        }

        if (!config[network.name].deployed.hasOwnProperty("nft") || config[network.name].deployed.nft == "") {
            const nft = await Nft.deploy("First Nft", "FNFT")
            await nft.deployed()
            console.log('deploy nft: ', nft.address)
            config[network.name].deployed.nft = nft.address
            utils.saveConfig(config);
        }

        if (!config[network.name].deployed.hasOwnProperty("router") || config[network.name].deployed.router == "") {
            const router = await Router.deploy(config[network.name].deployed.weth);
            await router.deployed()
            console.log('deploy router: ', router.address)
            config[network.name].deployed.router = router.address
            utils.saveConfig(config);
        }

        if (!config[network.name].deployed.hasOwnProperty("forward721Imp") || config[network.name].deployed.forward721Imp == "") {
            const forward721Imp = await Forward721Imp.deploy();
            await forward721Imp.deployed();
            console.log('deploy forward721Imp: ', forward721Imp.address)
            config[network.name].deployed.forward721Imp = forward721Imp.address
            utils.saveConfig(config);
        }


        if (!config[network.name].deployed.hasOwnProperty("factory721") || config[network.name].deployed.factory721 == "") {
            const factory721 = await upgrades.deployProxy(
                Factory721,
                [
                    config[network.name].deployed.forward721Imp, 
                    [config[network.name].deployed.dai, config[network.name].deployed.weth], 
                    deployer.address, 
                    10/* 10 /10000 */
                ],
                {
                    initializer: "__FactoryUpgradeable__init"
                }
            );
            console.log('deploy factory721: ', factory721.address)
            config[network.name].deployed.factory721 = factory721.address
            utils.saveConfig(config);
        }

        const factory721 = await Factory721.attach(config[network.name].deployed.factory721);
        await factory721.connect(deployer).deployPool(config[network.name].deployed.nft, 721, config[network.name].deployed.dai)
        await factory721.connect(deployer).deployPool(config[network.name].deployed.nft, 721, config[network.name].deployed.weth)

        // const forward721 = await Forward721Imp.attach(config[network.name].deployed.forward721);



    } else {
        throw("not deployed due to wrong network")
    }
    
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => {
        console.log("\nDeployment completed successfully ✓");
        process.exit(0)
    })
    .catch((error) => {
        console.log("\nDeployment failed ✗");
        console.error(error);
        process.exit(1);
    });
