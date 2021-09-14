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
        const Forward721Imp = await ethers.getContractFactory(
            "Forward721Upgradeable"
        );
        const forward721Imp = await Forward721Imp.deploy();
        await forward721Imp.deployed();
        console.log('forward721 implementation: ', forward721Imp.address)
        config[network.name].deployed = {
            "forward721Imp": forward721Imp.address
        }
        utils.saveConfig(config);

        const Factory = await ethers.getContractFactory(
            "HedgehogFactoryUpgradeable"
        );
        factory = await upgrades.deployProxy(
            Factory,
            [forward721Imp.address, [config[network.name].dai.address], deployer.address, 10],
            {
                initializer: "initialize"
            }
        );
        console.log("HedgehogFactoryUpgradeable: ", factory.address);
        config[network.name].deployed.factory = factory.address;
        utils.saveConfig(config);

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
