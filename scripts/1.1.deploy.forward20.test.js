// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { deploy } = require("@openzeppelin/hardhat-upgrades/dist/utils");
const { ethers, upgrades, network } = require("hardhat");
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
        || network.name == "kovan"
        ) {
        
        console.log("Deploying account:", await deployer.getAddress());
        console.log(
            "Deploying account balance:",
            (await deployer.getBalance()).toString(),
            "\n"
        );
        
        // We get the contract to deploy
        const Token20 = await ethers.getContractFactory("MockERC20")
        const Token721 = await ethers.getContractFactory("MockERC721")
        const Token1155 = await ethers.getContractFactory("MockERC1155")
        const WETH = await ethers.getContractFactory("WETH9")
        const Forward20Imp = await ethers.getContractFactory("Forward20Upgradeable");
        const Forward721Imp = await ethers.getContractFactory("Forward721Upgradeable");
        const Forward1155Imp = await ethers.getContractFactory("Forward1155Upgradeable");
        const Factory20 = await ethers.getContractFactory("Factory20Upgradeable")
        const Factory721 = await ethers.getContractFactory("Factory721Upgradeable")
        const Factory1155 = await ethers.getContractFactory("Factory1155Upgradeable")
        const Router = await ethers.getContractFactory("ForwardEtherRouter")
        
        // load factory
        const factory20 = await Factory20.attach(config[network.name].deployed.factory20);
        const factory721 = await Factory721.attach(config[network.name].deployed.factory721);
        const factory1155 = await Factory1155.attach(config[network.name].deployed.factory1155);
        // load pool
        const forward20daiweth = await Forward20Imp.attach(config[network.name].deployed.forward20daiweth)
        const forward20wethdai = await Forward20Imp.attach(config[network.name].deployed.forward20wethdai)
        const forward721nftdai = await Forward721Imp.attach(config[network.name].deployed.forward721nftdai)
        const forward721nftweth = await Forward721Imp.attach(config[network.name].deployed.forward721nftweth)
        const forward1155sworddai = await Forward1155Imp.attach(config[network.name].deployed.forward1155sworddai)
        const forward1155swordweth = await Forward1155Imp.attach(config[network.name].deployed.forward1155swordweth)

        
        if (false) {
            const Web3 = require('web3');
            const toWei = Web3.utils.toWei

            let tokenIds = toWei("10");
            let orderValidPeriod = 600;
            let nowToDeliverPeriod = orderValidPeriod + 20 * 60;
            let now = (await forward20_0._getBlockTimestamp()).toNumber();
            console.log("now = ", now)
            let deliveryStart = now + nowToDeliverPeriod;
            let deliveryPeriod = 600;
            let deliveryPrice = toWei("0.0001", "ether");
            let buyerMargin = toWei("0.0001", "ether");
            let sellerMargin = toWei("0.0002", "ether");
            let deposit = false;
            let isSeller = true;
            console.log("tokenIds = ", tokenIds.toString());
            console.log("orderValidPeriod = ", orderValidPeriod);
            console.log("deliveryStart = ", deliveryStart);
            console.log("deliveryPeriod = ", deliveryPeriod);
            console.log("deliveryPrice = ", deliveryPrice.toString());
            console.log("buyerMargin = ", buyerMargin.toString());
            console.log("sellerMargin = ", sellerMargin.toString());
            

            const dai = await Dai.attach(config[network.name].deployed.dai);
            await dai.connect(deployer).mint(sellerMargin);
            await dai.connect(deployer).approve(forward20_0.address, sellerMargin)



            const tx = await forward20_0.connect(deployer).createOrderFor(
                deployer.address,
                tokenIds,
                orderValidPeriod,
                deliveryStart,
                deliveryPeriod,
                deliveryPrice,
                buyerMargin,
                sellerMargin,
                deposit,
                isSeller
            );
            console.log("tx is: ", JSON.stringify(tx))
            console.log("gasLimit-----createOrder----: ", tx.gasLimit.toString(), tx.gasLimit.div(baseGasConsumed).toString())
        }

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
