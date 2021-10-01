// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
/*
Already support:
CryptoPunks: https://etherscan.io/address/0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb#code
CryptoKitties: https://etherscan.io/address/0x06012c8cf97bead5deae237070f9587f8e7a266d#code
CryptoVoxels: https://etherscan.io/address/0x79986af15539de2db9a5086382daeda917a9cf0c
Axie Infinity Axies: https://etherscan.io/address/0xf5b0a3efb8e8e4c201e2a935f110eaaf3ffecb8d (it does not check selector, so safeTransferFrom is not safe but works fine)
Blockchain Cuties: https://etherscan.io/address/0xd73be539d6b2076bab83ca6ba62dfe189abc6bbe (it does not check selector, so safeTransferFrom is not safe but works fine)
Makersplace v2: https://etherscan.io/address/0x2a46f2ffd99e19a89476e2f62270e0a35bbf0756 (problem same as CryptoVoxels, wrong selector, we can only use transferFrom)
*/
library TransferHelper {

    // Non-standard ERC721 projects:  https://docs.niftex.org/general/supported-nfts
    // implementation refers to: https://github.com/NFTX-project/nftx-protocol-v2/blob/master/contracts/solidity/NFTXVaultUpgradeable.sol#L444
    // TODO: improve implemention to include more non-standard ERC721 impl and change standard to safe-(invoke) way
    function _pushERC721(address assetAddr, address from, address to, uint256 tokenId) internal {
        address kitties = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
        address punks = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
        address voxels = 0x79986aF15539de2db9A5086382daEdA917A9CF0C;
        address makersTokenV2 = 0x2A46f2fFD99e19a89476E2f62270e0a35bBf0756;
        bytes memory data;
        if (assetAddr == kitties) {
            // data = abi.encodeWithSignature("transfer(address,uint256)", to, tokenId); 
            // bytes4(keccak256(bytes('transfer(address,uint256)'))) == 0xa9059cbb
            data = abi.encodeWithSelector(0xa9059cbb, to, tokenId); // save gas
        } else if (assetAddr == punks) {
            // CryptoPunks.
            // data = abi.encodeWithSignature("transferPunk(address,uint256)", to, tokenId);
            data = abi.encodeWithSelector(0x8b72a2ec, to, tokenId); // save gas
        } else if (assetAddr == voxels || assetAddr == makersTokenV2){
            // crypto voxels, wrong selector id, we need to use transferFrom
            // data = abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, tokenId);
            data = abi.encodeWithSelector(0x23b872dd, from, to, tokenId); // save gas
        } else {
            // Default.
            // data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", from, to, tokenId);
            data = abi.encodeWithSelector(0x42842e0e, from, to, tokenId); // save gas
        }
        (bool success, bytes memory result) = address(assetAddr).call(data);
        require(success && result.length == 0);
    }

    function _pullERC721(address assetAddr, address from, address to, uint256 tokenId) internal {
        address kitties = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
        address punks = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
        address voxels = 0x79986aF15539de2db9A5086382daEdA917A9CF0C;
        address makersTokenV2 = 0x2A46f2fFD99e19a89476E2f62270e0a35bBf0756;
        bytes memory data;
        if (assetAddr == kitties) {
            // Cryptokitties.
            // data = abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, tokenId);
            data = abi.encodeWithSelector(0x23b872dd, from, to, tokenId);  // save gas
        } else if (assetAddr == punks) {
            // CryptoPunks.
            // Fix here for frontrun attack. Added in v1.0.2.
            // (bool checkSuccess, bytes memory result) = address(assetAddr).staticcall(abi.encodeWithSignature("punkIndexToAddress(uint256)", tokenId));
            (bool checkSuccess, bytes memory result) = address(assetAddr).staticcall(abi.encodeWithSelector(0x58178168, tokenId)); // save gas
            (address owner) = abi.decode(result, (address));
            require(checkSuccess && owner == from, "pull not owner");
            // data = abi.encodeWithSignature("buyPunk(uint256)", tokenId);
            data = abi.encodeWithSelector(0x8264fe98, tokenId); // save gas
        } else if (assetAddr == voxels || assetAddr == makersTokenV2) {
            // data = abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, tokenId);
            data = abi.encodeWithSelector(0x23b872dd, from, to, tokenId); // save gas
        } else {
            // Default.
            // data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", from, to, tokenId);
            data = abi.encodeWithSelector(0x42842e0e, from, to, tokenId); // save gas
        }
        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success && resultData.length == 0);
    }

    function _approveERC721(address assetAddr, address owner, address spender, uint256 tokenId) internal {
        address kitties = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
        address punks = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
        address voxels = 0x79986aF15539de2db9A5086382daEdA917A9CF0C;
        address makersTokenV2 = 0x2A46f2fFD99e19a89476E2f62270e0a35bBf0756;
        if (assetAddr == kitties) {
            // Cryptokitties.
            // (bool success, bytes memory result) = assetAddr.call(abi.encodeWithSignature("approve(address,uint256)", spender, tokenId));
            (bool success, bytes memory result) = assetAddr.call(abi.encodeWithSelector(0x095ea7b3, spender, tokenId)); // save gas
            require(success && result.length == 0, "approve kitty fail");
        } else if (assetAddr == punks) {
            // // CryptoPunks.
            // (bool checkSuccess, bytes memory ownerResult) = address(assetAddr).staticcall(abi.encodeWithSignature("punkIndexToAddress(uint256)", tokenId));
            (bool checkSuccess, bytes memory ownerResult) = address(assetAddr).staticcall(abi.encodeWithSelector(0x58178168, tokenId)); // save gas
            (address _owner) = abi.decode(ownerResult, (address));
            require(checkSuccess && _owner == owner, "approve punk not owner");
            // (bool success, bytes memory result) = assetAddr.call(abi.encodeWithSignature("offerPunkForSaleToAddress(uint256,uint256,address)", tokenId, 0, spender));
            (bool success, bytes memory result) = assetAddr.call(abi.encodeWithSelector(0xbf31196f, tokenId, 0, spender)); // save gas
            require(success && result.length == 0, "approve punk fail");

        } else if (assetAddr == voxels || assetAddr == makersTokenV2) {
            // (bool success, bytes memory result) = assetAddr.call(abi.encodeWithSignature("approve(address,uint256)", spender, tokenId));
            (bool success, bytes memory result) = assetAddr.call(abi.encodeWithSelector(0x095ea7b3, spender, tokenId)); // save gas
            require(success && result.length == 0, "approve voxels fail");
        } else {
            // Default.
            // (bool checkSuccess, bytes memory approvedResult) = assetAddr.staticcall(abi.encodeWithSignature("isApprovedForAll(address,address)", owner, spender));
            (bool checkSuccess, bytes memory approvedResult) = assetAddr.staticcall(abi.encodeWithSelector(0xe985e9c5, owner, spender)); // save gas
            (bool approvedForAll) = abi.decode(approvedResult, (bool));
            require(checkSuccess, "isAprovedForAll fail");
            if (!approvedForAll) {
                // (bool success, bytes memory result) = assetAddr.call(abi.encodeWithSignature("setApprovalForAll(address,bool)", spender, true));
                (bool success, bytes memory result) = assetAddr.call(abi.encodeWithSelector(0xa22cb465, spender, true)); // save gas
                require(success && result.length == 0, "setApprovalForAll fail");
            }
            
        }

    }

}
