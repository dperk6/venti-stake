// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers, run } from "hardhat";
import { makeSwap } from "./utils";

const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const VST = "0xb7C2fcD6d7922eddd2A7A9B0524074A60D5b472C";

async function main() {
    const signers = await ethers.getSigners();
    const Stake = await ethers.getContractFactory('VentiSwapStaking');
    const Token = await ethers.getContractFactory('TestToken');
    const token = await Token.attach('0xb7C2fcD6d7922eddd2A7A9B0524074A60D5b472C');
    const stake = Stake.attach("0x281A39d6db514F159E87FD17275E981d42292b2a");
    await makeSwap(signers[0], [WETH,VST], '1.0');
    await token.approve(stake.address, ethers.constants.MaxUint256);
    await stake.deposit(await token.balanceOf(signers[0].address), 1);
    // Increase by 1 month + 1 second
    await ethers.provider.send("evm_increaseTime", [2628001]);
    await ethers.provider.send('evm_mine', []);
    await run("node");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
