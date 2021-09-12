require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");


// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

const utils = require('./scripts/utils')
const config = utils.getConfig();
module.exports = {
  
  networks: {
    ropsten:  {
      url: `https://eth-ropsten.alchemyapi.io/v2/${config.ropsten.alchemyApiKey}`,
      accounts: [`0x${config.ropsten.privateKeys[0]}`, `0x${config.ropsten.privateKeys[1]}`],
    },

    // mainnet: {
    //   url: `https://eth-mainnet.alchemyapi.io/v2/${config.ropsten.alchemyApiKey}`,
    //   accounts: [`0x${process.env.DEV_PRIVATE_KEY}`],
    // },
    
    // ropsten_fork: {
    //   mining: {
    //     auto: true,
    //   },
    //   forking: {
    //     url: `https://eth-ropsten.alchemyapi.io/v2/${config.ropsten.alchemyApiKey}`,
    //     // blockNumber: 12772572,
    //   },
    // },
    
  },
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true, // true for release, false is default for debug and test
        runs: 1000,
      },
    },
  },
};
