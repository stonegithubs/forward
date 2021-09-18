
# hedgehog.wtf forward contract protocol

This repository contains hedeghog forward contracts which are under development currently. 

Factory is responsible for creating forward721 contract, in which we can create forward order, take order, and deliver the promise or forcely close the order. We will be able to make the very personal deal onchain and stake the margin into the forward contract as a promise to deliver the deal. In case one part doesnot fulfill  his/her previous commitment, his/her margin will be lost and given to the countrary part.

Since we are using Beacon Proxy for factory and pair implementation in order to save much gas and be greatly efficient, we need three factories for three types of forward contracts.


In order to run the test scripts:

```shell
npm install --save-dev
npx hardhat test
```


















































