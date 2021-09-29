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
        const Dai = await ethers.getContractFactory("MockERC20")
        const WETH = await ethers.getContractFactory("WETH9")
        const Forward20Imp = await ethers.getContractFactory("Forward20Upgradeable");
        const Factory20 = await ethers.getContractFactory("Factory20Upgradeable")
        const Router = await ethers.getContractFactory("ForwardEtherRouter")
        const Forward20 = await ethers.getContractFactory("Forward20Upgradeable")

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

        if (!config[network.name].deployed.hasOwnProperty("router") || config[network.name].deployed.router == "") {
            const router = await Router.deploy(config[network.name].deployed.weth);
            await router.deployed()
            console.log('deploy router: ', router.address)
            config[network.name].deployed.router = router.address
            utils.saveConfig(config);
        }

        if (!config[network.name].deployed.hasOwnProperty("forward20Imp") || config[network.name].deployed.forward20Imp == "") {
            const forward20Imp = await Forward20Imp.deploy();
            await forward20Imp.deployed();
            console.log('deploy forward20Imp: ', forward20Imp.address)
            config[network.name].deployed.forward20Imp = forward20Imp.address
            utils.saveConfig(config);
        }


        if (!config[network.name].deployed.hasOwnProperty("factory20") || config[network.name].deployed.factory20 == "") {
            const factory20 = await upgrades.deployProxy(
                Factory20,
                [
                    config[network.name].deployed.forward20Imp, 
                    [config[network.name].deployed.dai, config[network.name].deployed.weth], 
                    deployer.address, 
                    10/* 10 /10000 */
                ],
                {
                    initializer: "__FactoryUpgradeable__init"
                }
            );
            console.log('deploy factory20: ', factory20.address)
            config[network.name].deployed.factory20 = factory20.address
            utils.saveConfig(config);
        }
        
        const factory20 = await Factory20.attach(config[network.name].deployed.factory20);
        
        
        // const tx = await factory20.connect(deployer).deployPool(config[network.name].deployed.weth, 20, config[network.name].deployed.dai)
        // // console.log("gasLimit-----factory20.deployPool----: ", tx.gasLimit.toString())

        // // await factory20.connect(deployer).deployPool(config[network.name].deployed.dai, 20, config[network.name].deployed.weth)
        // // await factory20.connect(deployer).deployPool(config[network.name].deployed.dai, 20, config[network.name].deployed.weth)


        const forward20_0 = await Forward20.attach(await factory20.allPairs(0))
        const orderLen = await forward20_0.ordersLength();
        console.log("ordre length = ", orderLen.toString())
        if (orderLen.toNumber() > 0) {
            return;
        }

        {
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
