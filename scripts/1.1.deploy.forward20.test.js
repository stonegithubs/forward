// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { deploy } = require("@openzeppelin/hardhat-upgrades/dist/utils");
const { time } = require("@openzeppelin/test-helpers");
const { ethers, upgrades, network, web3 } = require("hardhat");
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
    const alice = signers[0]
    const bob = signers[1]
    console.log("network is ", network.name)
    console.log("network is ", network.config.gasLimit)
    
    
    

    if (
        network.name == "local"         /*local node*/
        || network.name == 'ropsten'    /*ropsten testnet */
        || network.name == "kovan"
        || network.name == 'rinkeby'    /*ropsten testnet */
        ) {
        
        console.log("Deploying account:", await alice.getAddress());
        console.log(
            "Deploying account balance:",
            (await alice.getBalance()).toString(),
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
        
        // console.log("sleeping start")
        // await sleep(10)
        // console.log("sleeping done")
        
        // console.log("sleeping start")
        // await sleep(10)
        // console.log("sleeping done")

        // console.log("sleeping start")
        // await sleep(10)
        // console.log("sleeping done")
        // return


        const Web3 = require('web3');
        const toWei = Web3.utils.toWei
        const dai = await Token20.attach(config[network.name].deployed.dai);
        const nft = await Token721.attach(config[network.name].deployed.nft);
        // create order 
        let orderId = (await forward721nftdai.ordersLength()).toNumber() + 1
        orderId = 5;
        console.log("orderId = ", orderId)
        const tokenIds = [0+orderId, 10000+orderId];
        const deliveryPrice = toWei("0.0000001", "ether");

        let tx;
        if ((await forward721nftdai.checkOrderState(orderId)).toString() == "0") { // not active
            let height = await web3.eth.getBlockNumber();
            let block = await web3.eth.getBlock(height);
            let now = block.timestamp
            console.log("now = ", now)
            console.log("now = ", (await time.latest()).toNumber())
            console.log("now = ", (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp)
            // return
            let unitDuration = 60; // seconds
            let orderValidPeriod = 3 * unitDuration;
            let nowToDeliverPeriod = orderValidPeriod + 3 * unitDuration;
            // return
            let deliverStart = now + nowToDeliverPeriod;
            let deliveryPeriod = 3 * unitDuration;
            let buyerMargin =   toWei("0.00000001", "ether");
            let sellerMargin =  toWei("0.00000001", "ether");
            let deposit = false;
            let isSeller = true;
            let validTill;
            let order;
            
            tx = await dai.connect(alice).mint(sellerMargin, {gasLimit: network.config.gasLimit});
            // await tx.wait();
            tx = await dai.connect(alice).approve(forward721nftdai.address, sellerMargin, {gasLimit: network.config.gasLimit})
            // await tx.wait();
            tx = await forward721nftdai.connect(alice).createOrderFor(
                alice.address,
                tokenIds,
                [orderValidPeriod,
                deliverStart.toString(),
                deliveryPeriod],
                [deliveryPrice,
                buyerMargin,
                sellerMargin],
                [],
                deposit,
                isSeller,
                {gasLimit: network.config.gasLimit}
            );
            let receipt = await tx.wait();
            console.log("receipt is: ", JSON.stringify(receipt))
            console.log("gasUsed-----createOrder 721----: ", receipt.gasUsed.toString())
            console.log("now = ", (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp)
        }
        if ((await forward721nftdai.checkOrderState(orderId)).toString() == "1"){ // active
            let buyerMargin = (await forward721nftdai.orders(orderId)).buyerMargin;
            tx = await dai.connect(bob).mint(buyerMargin, {gasLimit: network.config.gasLimit});
            // await tx.wait();
            tx = await dai.connect(bob).approve(forward721nftdai.address, buyerMargin, {gasLimit: network.config.gasLimit})
            // await tx.wait();
            tx = await forward721nftdai.connect(bob).takeOrderFor(bob.address, orderId, {gasLimit: network.config.gasLimit});
            // await tx.wait();
        }
        if ((await forward721nftdai.checkOrderState(orderId)).toString() == "4"){ // delivery
            let order = await forward721nftdai.orders(orderId);
            let deliverStart = order.deliverStart
            let now = (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp
            console.log("deliver start at: ", deliverStart)
            console.log("now             : ", now)
            // seller deliver
            for (let i = 0; i < tokenIds.length; i++) {
                tx = await nft.connect(alice).mint(alice.address, tokenIds[i], {gasLimit: network.config.gasLimit});
                // await tx.wait();
                tx = await nft.connect(alice).approve(forward721nftdai.address, tokenIds[i], {gasLimit: network.config.gasLimit});
                // await tx.wait();
            }
            console.log("now             : ", now)
            now = (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp
            if (deliverStart > now) {
                console.log("starting sleep for", deliverStart - now, "seconds....")
                await sleep(deliverStart - now)
                console.log("sleeping done")
            }
            tx = await forward721nftdai.connect(alice).deliverFor(alice.address, orderId, {gasLimit: network.config.gasLimit});
            // await tx.wait();
            // buyer deliver, meanwhile settle it
            tx = await dai.connect(bob).mint(deliveryPrice, {gasLimit: network.config.gasLimit});
            // await tx.wait();
            tx = await dai.connect(bob).approve(forward721nftdai.address, deliveryPrice, {gasLimit: network.config.gasLimit})
            // await tx.wait();
            tx = await forward721nftdai.connect(bob).deliverFor(bob.address, orderId, {gasLimit: network.config.gasLimit});
            // await tx.wait();
        }

    } else {
        throw("not deployed due to wrong network")
    }
    
}

const sleep = (seconds) => {
    return new Promise(resolve => setTimeout(resolve, 1000 * seconds))
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
