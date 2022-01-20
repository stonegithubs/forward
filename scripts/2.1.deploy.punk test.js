
const { ethers, upgrades, network } = require("hardhat");
const utils = require('./utils')
const args = require('../config/args');
const { deploy } = require("@openzeppelin/hardhat-upgrades/dist/utils");
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
        const CryptoPunksMarket = await ethers.getContractFactory("CryptoPunksMarket")

        if (!config[network.name].deployed.hasOwnProperty("punk") || config[network.name].deployed.punk == "") {
            const punk = await CryptoPunksMarket.deploy()
            await punk.deployed()
            console.log('deploy original punk: ', punk.address)
            config[network.name].deployed.punk = punk.address
            utils.saveConfig(config);
        }
        const punk = await CryptoPunksMarket.attach(config[network.name].deployed.punk);
        
        const allPunksAssigned = await punk.allPunksAssigned();
        if (!allPunksAssigned) {
            let total = 100;
            let addresses = []; let indices = [];
            for(let i=0; i < total; i++) {
                addresses.push(signers[2].address);
                indices.push(i);
            }
            let fromI, toI;
            for (let i=0; i <total/50;i++) {
                fromI = 50 * i
                if (fromI + 50 > total) {
                    toI = total
                } else {
                    toI = fromI + 50
                }
                await punk.setInitialOwners(addresses, indices)
            }
    
            await punk.allInitialOwnersAssigned();
        }
        // // d140c6272973bce6a56fd2833e7f45dade84130fb8047d12cbfb94dfb7153118
        // let checkApproveIndices = [0, 1]
        // let spender = signers[1]
        // for (let i=0; i < checkApproveIndices.length; i++) {
        //     // approve punk: check ownership, offerPunkForSaleToAddress
        //     let owner = await punk.connect(deployer).punkIndexToAddress(checkApproveIndices[i]);
        //     if (owner == deployer.address) {
        //         console.log("YES: owner of", checkApproveIndices[i], "is", deployer.address)
        //     } else {
        //         console.log("NO:  owner of", checkApproveIndices[i], "is ", owner)
        //         continue
        //     }
        //     // approve
        //     await punk.connect(deployer).offerPunkForSaleToAddress(checkApproveIndices[i], 0, spender.address)
        //     // check allowance punk 
        //     let res = await punk.punksOfferedForSale(checkApproveIndices[i])
        //     if (res[0] = true && res[4] == spender.address) {
        //         console.log("allowance correct")
        //     }
        //     // transferFrom through buyPunk
        //     await punk.connect(spender).buyPunk(checkApproveIndices[i])
        //     let newOwner = await punk.punkIndexToAddress(checkApproveIndices[i])
        //     if (newOwner == spender) {
        //         console.log("buyPunk as transferFrom success", checkApproveIndices[i])
        //     }
        // }
        

        




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
