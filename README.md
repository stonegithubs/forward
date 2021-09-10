
# Basic Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, a sample script that deploys that contract, and an example of a task implementation, which simply lists the available accounts.

Try running some of the following tasks:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
node scripts/sample-script.js
npx hardhat help
```



1. 将20 721 1155分三类Forward合约，每种token对应一本Forward合约，如A_721 B_721将为两本Forward合约

2. 因为对赌用户要质押保证金，所以每类合约的writer可以选择质押nft或不质押，

3. 结算货币 native, usdc/usdt

4. forward Expiration: self-defination, 

5. 保证金挖矿

6. forward的清算只有两种状态，



Uni/Sushi中，当liquidity不发生变化时，价格x与数量y的关系为x*y=const；当liquidity发生变化时，x与y的变化与liquidity变化成是等比的。

当前nft token化的产品如unicly, niftex, nftx, nft20等均采用xy=k的公式，可以直接使用uniswap/sushiswap的基础设施。但直接使用xy=k有两个问题，一是nft token化的share在uni或sushi平台中交易时，本身注定有一部分流动性是极小概率被交易，主要原因为x趋于极小值时，y的变化量过大(这一点在uni/sushi中本身就存在))；二是被token化的某个nft，某类nft或是某个nft集合本身的价值有限，不可与ETH/USDT这类的交易对类比，因为当ETH/USDT交易对的深度足够大时即x和y很大时，其滑点是有限的，而token化的nft交易对更适合xy=k中的某一段曲线。故此我们提出hAMM即half-AMM-half-VAMM。

假设x1为nft token化后被用于创建流动性池的erc20 token数量，y1为这些token的价值，当liquidity提供者A创建交易对时，我们定义x=rx1, y=ry1，其中r为池子创建时定义的数值，正常来讲大于1，平台默认为5。池子创建成功后，与Uni/Sushi交易池相比，我们的池子为r^2*x1*y1=k，其中x1的变化区间为[(r-1)x1, k/((r-1)y1)]，y1的变化区间为[(r-1)y1, k/((r-1)x1)]，这样做的好处是：1)所有的流动性都可以被完全交易，不存在有些流动性注定无法被交易的问题; 2)不存在x或y处于很大或很小值时，出现的滑点过大的问题。
当liquidity提供者B提供或减小流动性时，交易池中虚拟与实际的可交易的x与y等比例变化，举例来说，
cryptoPunk token化的池子中x1 = 100, y1 = 100, r = 5,即hAMM中虚拟与实际token比例为4:1。
liquidity provider A的LP数量为500，其初始注入的x与ytoken数量分别为100.
市场交易一段时间(池子中少了20个x1token，多了25个y1token)后，x = 480, y = 520.83, 

此时liquidity provider B持有x1 token 4.8，他需要同时提供相对应的y1 token 5.2083,此时k值由250000变为(480+4.8*5)(520.83+5.2083*5)即1,578,630, B将获得的LP token数量为500*4.8*5/480=25。此时lp总量为525,
新的x1变化区间为

此时liquidity provider A移除流动性500个lp，则
A移除的x1token数量为500/525*84.8=80.76
y1token数量为500/525*(120.83 + 5.2083) = 120.036
x = 25/525*(480+4.8*5) = 24
y = 25/525*(520.83+5.2083*5) = 26.0415

























































