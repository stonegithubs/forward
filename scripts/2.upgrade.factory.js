
const { ethers, upgrades, network } = require("hardhat");
const utils = require('./utils')
const args = require('../config/args')
async function main() {

    let config = utils.getConfig();

    const signers = await ethers.getSigners();
    const deployer = signers[0]
    
    console.log("network is ", network.name)
    

    if (
        network.name == "local"         /*local node*/
        || network.name == 'ropsten'    /*ropsten testnet */
        || network.name == "rinkeby"
        ) {
        
        console.log("Deploying account:", await deployer.getAddress());
        console.log(
            "Deploying account balance:",
            (await deployer.getBalance()).toString(),
            "\n"
        );
        
        // We get the contract to deploy
        const Factory20 = await ethers.getContractFactory("Factory20Upgradeable")
        const Factory721 = await ethers.getContractFactory("Factory721Upgradeable")
        const Factory1155 = await ethers.getContractFactory("Factory1155Upgradeable")

        const upgraded20 = await upgrades.upgradeProxy(
            config.rinkeby.deployed.factory20,
            Factory20
        );
        const upgraded721 = await upgrades.upgradeProxy(
            config.rinkeby.deployed.factory721,
            Factory721
        );
        const upgraded1155 = await upgrades.upgradeProxy(
            config.rinkeby.deployed.factory1155,
            Factory1155
        );
        

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
