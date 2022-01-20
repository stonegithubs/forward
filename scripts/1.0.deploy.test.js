// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers, upgrades, network } = require('hardhat')
const utils = require('./utils')

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');
  let config = utils.getConfig()

  const signers = await ethers.getSigners()
  const deployer = signers[0]
  console.log('network is ', network.name)

  if (
    network.name == 'hardhat' /** hardhat plugin node */ ||
    network.name == 'local' /*local node*/ ||
    network.name == 'ropsten' /*ropsten testnet */ ||
    network.name == 'rinkeby' /*rinkeby testnet */
  ) {
    console.log('Deploying account:', await deployer.getAddress())
    console.log(
      'Deploying account balance:',
      (await deployer.getBalance()).toString(),
      '\n'
    )

    // We get the contract to deploy
    const Token20 = await ethers.getContractFactory('MockERC20')
    const Token721 = await ethers.getContractFactory('MockERC721')
    // const Token1155 = await ethers.getContractFactory("MockERC1155")
    const WETH = await ethers.getContractFactory('WETH9')
    // const Forward20Imp = await ethers.getContractFactory("Forward20Upgradeable");
    const Forward721Imp = await ethers.getContractFactory(
      'Forward721Upgradeable'
    )
    // const Forward1155Imp = await ethers.getContractFactory("Forward1155Upgradeable");
    // const Factory20 = await ethers.getContractFactory("Factory20Upgradeable")
    const Factory721 = await ethers.getContractFactory('Factory721Upgradeable')
    // const Factory1155 = await ethers.getContractFactory("Factory1155Upgradeable")
    const Router = await ethers.getContractFactory('ForwardEtherRouter')

    let height = await web3.eth.getBlockNumber()
    console.log('height: ', height)
    // config[network.name].deployed.height = height

    if (
      !config[network.name].deployed.hasOwnProperty('weth') ||
      config[network.name].deployed.weth == ''
    ) {
      //   config[network.name].deployed.height = await web3.eth.getBlockNumber()
      const weth = await WETH.deploy()
      await weth.deployed()
      console.log('deploy weth: ', weth.address)
      config[network.name].deployed.weth = weth.address
      utils.saveConfig(config)
    }

    if (
      !config[network.name].deployed.hasOwnProperty('dai') ||
      config[network.name].deployed.dai == ''
    ) {
      const dai = await Token20.deploy('Dai Token', 'DAI', 0)
      await dai.deployed()
      console.log('deploy erc20 dai: ', dai.address)
      config[network.name].deployed.dai = dai.address
      utils.saveConfig(config)
    }

    if (
      !config[network.name].deployed.hasOwnProperty('nft') ||
      config[network.name].deployed.nft == ''
    ) {
      console.log('deploying NFT')
      const nft = await Token721.deploy('First Nft', 'FNFT')
      await nft.deployed()
      console.log('deploy erc721 nft: ', nft.address)
      config[network.name].deployed.nft = nft.address
      utils.saveConfig(config)
    }

    // if (
    //   !config[network.name].deployed.hasOwnProperty('sword') ||
    //   config[network.name].deployed.sword == ''
    // ) {
    //   const sword = await Token1155.deploy('sword_uri')
    //   await sword.deployed()
    //   console.log('deploy erc1155 sword: ', sword.address)
    //   config[network.name].deployed.sword = sword.address
    //   utils.saveConfig(config)
    // }

    if (
      !config[network.name].deployed.hasOwnProperty('router') ||
      config[network.name].deployed.router == ''
    ) {
      const router = await Router.deploy(config[network.name].deployed.weth)
      await router.deployed()
      console.log('deploy router: ', router.address)
      config[network.name].deployed.router = router.address
      utils.saveConfig(config)
    }

    // if (
    //   !config[network.name].deployed.hasOwnProperty('forward20Imp') ||
    //   config[network.name].deployed['forward20Imp'] == ''
    // ) {
    //   const forward20Imp = await Forward20Imp.deploy()
    //   await forward20Imp.deployed()
    //   console.log('deploy forward20Imp: ', forward20Imp.address)
    //   config[network.name].deployed.forward20Imp = forward20Imp.address
    //   utils.saveConfig(config)
    // }

    if (
      !config[network.name].deployed.hasOwnProperty('forward721Imp') ||
      config[network.name].deployed.forward721Imp == ''
    ) {
      const forward721Imp = await Forward721Imp.deploy()
      await forward721Imp.deployed()
      console.log('deploy forward721Imp: ', forward721Imp.address)
      config[network.name].deployed.forward721Imp = forward721Imp.address
      utils.saveConfig(config)
    }

    // if (
    //   !config[network.name].deployed.hasOwnProperty('forward1155Imp') ||
    //   config[network.name].deployed.forward1155Imp == ''
    // ) {
    //   const forward1155Imp = await Forward1155Imp.deploy()
    //   await forward1155Imp.deployed()
    //   console.log('deploy forward1155Imp: ', forward1155Imp.address)
    //   config[network.name].deployed.forward1155Imp = forward1155Imp.address
    //   utils.saveConfig(config)
    // }

    // if (
    //   !config[network.name].deployed.hasOwnProperty('factory20') ||
    //   config[network.name].deployed.factory20 == ''
    // ) {
    //   const factory20 = await upgrades.deployProxy(
    //     Factory20,
    //     [
    //       config[network.name].deployed.forward20Imp,
    //       [
    //         config[network.name].deployed.weth,
    //         config[network.name].deployed.dai,
    //       ],
    //       deployer.address,
    //       10 /* 10 /10000 */,
    //     ],
    //     {
    //       initializer: '__FactoryUpgradeable__init',
    //     }
    //   )
    //   console.log('deploy factory20: ', factory20.address)
    //   config[network.name].deployed.factory20 = factory20.address
    //   utils.saveConfig(config)
    // }

    if (
      !config[network.name].deployed.hasOwnProperty('factory721') ||
      config[network.name].deployed.factory721 == ''
    ) {
      const factory721 = await upgrades.deployProxy(
        Factory721,
        [
          config[network.name].deployed.forward721Imp,
          [
            config[network.name].deployed.weth,
            config[network.name].deployed.dai,
          ],
          deployer.address,
          250 /* 10 /10000 */,
        ],
        {
          initializer: '__FactoryUpgradeable__init',
        }
      )
      console.log('deploy factory721: ', factory721.address)
      config[network.name].deployed.factory721 = factory721.address
      utils.saveConfig(config)
    }

    // if (
    //   !config[network.name].deployed.hasOwnProperty('factory1155') ||
    //   config[network.name].deployed.factory1155 == ''
    // ) {
    //   const factory1155 = await upgrades.deployProxy(
    //     Factory1155,
    //     [
    //       config[network.name].deployed.forward1155Imp,
    //       [
    //         config[network.name].deployed.weth,
    //         config[network.name].deployed.dai,
    //       ],
    //       deployer.address,
    //       10 /* 10 /10000 */,
    //     ],
    //     {
    //       initializer: '__FactoryUpgradeable__init',
    //     }
    //   )
    //   console.log('deploy factory1155: ', factory1155.address)
    //   config[network.name].deployed.factory1155 = factory1155.address
    //   utils.saveConfig(config)
    // }

    // const factory20 = await Factory20.attach(
    //   config[network.name].deployed.factory20
    // )
    const factory721 = await Factory721.attach(
      config[network.name].deployed.factory721
    )
    // const factory1155 = await Factory1155.attach(
    //   config[network.name].deployed.factory1155
    // )

    // deploy 20 pool
    // if (
    //   !config[network.name].deployed.hasOwnProperty('forward20daiweth') ||
    //   config[network.name].deployed['forward20daiweth'] == ''
    // ) {
    //   const tx = await factory20
    //     .connect(deployer)
    //     .deployPool(
    //       config[network.name].deployed.dai,
    //       20,
    //       config[network.name].deployed.weth
    //     )
    //   let receipt = await tx.wait()
    //   console.log(
    //     'deploy forward20daiweth(asset:dai, margin:weth): ',
    //     receipt.events[1].args[3]
    //   )
    //   config[network.name].deployed.forward20daiweth = receipt.events[1].args[3]
    //   utils.saveConfig(config)
    // }

    // if (
    //   !config[network.name].deployed.hasOwnProperty('forward20wethdai') ||
    //   config[network.name].deployed['forward20wethdai'] == ''
    // ) {
    //   const tx = await factory20
    //     .connect(deployer)
    //     .deployPool(
    //       config[network.name].deployed.weth,
    //       20,
    //       config[network.name].deployed.dai
    //     )
    //   let receipt = await tx.wait()
    //   console.log(
    //     'deploy forward20wethdai(asset:weth, margin:dai): ',
    //     receipt.events[1].args[3]
    //   )
    //   config[network.name].deployed.forward20wethdai = receipt.events[1].args[3]
    //   utils.saveConfig(config)
    // }
    // deploy 721 pool
    if (
      !config[network.name].deployed.hasOwnProperty('forward721nftdai') ||
      config[network.name].deployed['forward721nftdai'] == ''
    ) {
      const tx = await factory721
        .connect(deployer)
        .deployPool(
          config[network.name].deployed.nft,
          721,
          config[network.name].deployed.dai
        )
      let receipt = await tx.wait()
      console.log(
        'deploy forward721nftdai(asset:nft, margin:dai): ',
        receipt.events[1].args[3]
      )
      config[network.name].deployed.forward721nftdai = receipt.events[1].args[3]
      utils.saveConfig(config)
    }
    if (
      !config[network.name].deployed.hasOwnProperty('forward721nftweth') ||
      config[network.name].deployed['forward721nftweth'] == ''
    ) {
      const tx = await factory721
        .connect(deployer)
        .deployPool(
          config[network.name].deployed.nft,
          721,
          config[network.name].deployed.weth
        )
      let receipt = await tx.wait()
      console.log(
        'deploy forward721nftweth(asset:nft, margin:weth): ',
        receipt.events[1].args[3]
      )
      config[network.name].deployed.forward721nftweth =
        receipt.events[1].args[3]
      utils.saveConfig(config)
    }
    // deploy 1155 pool
    // if (
    //   !config[network.name].deployed.hasOwnProperty('forward1155sworddai') ||
    //   config[network.name].deployed['forward1155sworddai'] == ''
    // ) {
    //   const tx = await factory1155
    //     .connect(deployer)
    //     .deployPool(
    //       config[network.name].deployed.sword,
    //       1155,
    //       config[network.name].deployed.dai
    //     )
    //   let receipt = await tx.wait()
    //   console.log(
    //     'deploy forward1155sworddai(asset:sword, margin:dai): ',
    //     receipt.events[1].args[3]
    //   )
    //   config[network.name].deployed.forward1155sworddai =
    //     receipt.events[1].args[3]
    //   utils.saveConfig(config)
    // }
    // if (
    //   !config[network.name].deployed.hasOwnProperty('forward1155swordweth') ||
    //   config[network.name].deployed['forward1155swordweth'] == ''
    // ) {
    //   const tx = await factory1155
    //     .connect(deployer)
    //     .deployPool(
    //       config[network.name].deployed.sword,
    //       1155,
    //       config[network.name].deployed.weth
    //     )
    //   let receipt = await tx.wait()
    //   console.log(
    //     'deploy forward1155swordweth(asset:sword, margin:weth): ',
    //     receipt.events[1].args[3]
    //   )
    //   config[network.name].deployed.forward1155swordweth =
    //     receipt.events[1].args[3]
    //   utils.saveConfig(config)
    // }
  } else {
    throw 'not deployed due to wrong network'
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => {
    console.log('\nDeployment completed successfully ✓')
    process.exit(0)
  })
  .catch((error) => {
    console.log('\nDeployment failed ✗')
    console.error(error)
    process.exit(1)
  })
