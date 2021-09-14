
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
        ) {
        
        // console.log("Deploying account:", await deployer.getAddress());
        // console.log(
        //     "Deploying account balance:",
        //     (await deployer.getBalance()).toString(),
        //     "\n"
        // );
        
        // // We get the contract to deploy
        // const MockERC20 = await ethers.getContractFactory(
        //     "MockERC20"
        // );
        // const mockErc20 = await MockERC20.deploy(args.mockerc20[0], args.mockerc20[1], args.mockerc20[2]);
        // await mockErc20.deployed();        
        // console.log("MockERC20: ", mockErc20.address);
        // config[network.name].deployed.mockErc20 = mockErc20.address;
        // utils.saveConfig(config);

        await run("verify:verify", {
            address: config[network.name].deployed.mockErc20,
            contract: "contracts/test/MockERC20.sol:MockERC20",
            constructorArguments: args.mockerc20,
            network: network.name,
          });

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
