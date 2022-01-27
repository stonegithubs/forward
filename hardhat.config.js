require('@openzeppelin/hardhat-upgrades')
require('@nomiclabs/hardhat-etherscan')
require('@nomiclabs/hardhat-truffle5')
require('hardhat-gas-reporter')

/** In order to compile and verify using any specific solcjs version, we can use the following 
     referring to : https://github.com/fvictorio/hardhat-examples/tree/master/custom-solc

const { TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD } = require("hardhat/builtin-tasks/task-names");
const path = require("path");
subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD, async (args, hre, runSuper) => {
  if (args.solcVersion === "0.8.5") {
    const compilerPath = path.join(__dirname, "soljson-v0.8.5-nightly.2021.5.12+commit.98e2b4e5.js");

    return {
      compilerPath,
      isSolcJs: true, // if you are using a native compiler, set this to false
      version: args.solcVersion,
      // this is used as extra information in the build-info files, but other than
      // that is not important
      longVersion: "0.8.5-nightly.2021.5.12+commit.98e2b4e5"
    }
  } else if (args.solcVersion == "0.8.4") {
    const compilerPath = path.join(__dirname, "soljson-0.8.4-c7e474f.js")
    return {
      compilerPath,
      isSolcJs: true,
      version: args.solcVersion,
      longVersion: "0.8.4+commit.c7e474f+manuallysetup"
    }
  }

  // we just use the default subtask if the version is not 0.8.5
  return runSuper();
})
*/

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
    const accounts = await hre.ethers.getSigners()

    for (const account of accounts) {
        console.log(account.address)
    }
})

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

const utils = require('./scripts/utils')
const config = utils.getConfig()

module.exports = {
    networks: {
        ropsten: {
            url: `https://ropsten.infura.io/v3/${config.ropsten.infuraKey}`,
            accounts: [
                `0x${config.ropsten.privateKeys[0]}`,
                `0x${config.ropsten.privateKeys[1]}`,
            ],
        },
        // kovan:  {
        //   url: `https://ropsten.infura.io/v3/${config.kovan.infuraKey}`,
        //   accounts: [`0x${config.ropsten.privateKeys[0]}`, `0x${config.ropsten.privateKeys[1]}`],
        // },
        rinkeby: {
            url: `https://rinkeby.infura.io/v3/${config.rinkeby.infuraKey}`,
            accounts: [
                `0x${config.rinkeby.privateKeys[0]}`,
                `0x${config.rinkeby.privateKeys[1]}`,
                `0x${config.rinkeby.privateKeys[2]}`,
            ],
            // gasPrice: 1.1 * 1000000000, // 1.1 gwei
            // gasLimit: 5000000, //
            gas: 2100000,
            gasPrice: 8000000000,
        },
        mainnet: {
            url: 'http://localhost:8545',
            allowUnlimitedContractSize: true,
            timeout: 2800000,
            //   url: `https://eth-mainnet.alchemyapi.io/v2/${config.ropsten.alchemyApiKey}`,
            //   accounts: [`0x${process.env.DEV_PRIVATE_KEY}`],
        },

        // hardhat: {
        //   mining: {
        //     auto: true,
        //   },
        //   forking: {
        //     url: `https://mainnet.infura.io/v3/${config.mainnet.infuraKey}`, // put your infura key
        //     // blockNumber: 12867134,                                        // putting historical block number requires archive node
        //   },
        // },

        // ropsten:  {
        //   url: `https://eth-ropsten.alchemyapi.io/v2/${config.ropsten.alchemyApiKey}`,
        //   accounts: [`0x${config.ropsten.privateKeys[0]}`, `0x${config.ropsten.privateKeys[1]}`],
        // },

        local: {
            // need to run local node manually
            url: 'http://localhost:8545',
            allowUnlimitedContractSize: true,
            timeout: 2800000,
        },
    },
    etherscan: {
        apiKey: `${config.etherScanApiKey}`,
    },
    mocha: {
        timeout: 200000,
    },
    solidity: {
        compilers: [
            {
                version: '0.8.4',
                settings: {
                    optimizer: {
                        enabled: true, // true for release, false is default for debug and test
                        runs: 200,
                    },
                },
            },
            {
                version: '0.4.25',
            },
        ],
    },
    gasReporter: {
        enabled: `${config.etherScanApiKey}` ? true : false,
        showMethodSig: true,
        rst: true,
        onlyCalledMethods: true,
        src: './contracts',
        // proxyResolver: "implementation()",
        coinmarketcap: `${config.etherScanApiKey}`,
        currency: 'USD',
        // outputFile: `${config.gasReporterFilePath}`,
    },
}
