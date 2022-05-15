// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

    const accounts = await ethers.getSigners();
//   console.log('Deployer address:', accounts[0].address);

//   // We get the contract to deploy
//   const Stake = await ethers.getContractFactory("VentiStake");

const stake = await ethers.getContractAt("VentiStake", "0x281A39d6db514F159E87FD17275E981d42292b2a", accounts[0]);
await stake.transferOwnership("0xcf1e5Bd9247b402Ec12e7c7A2CEad1F98ab30067");
  
//   // Fill in correct token address for prod deploy
//   const stake = await Stake.deploy('0xe5f3a2fd1b5841294845963997BBd6F14CC2D822');

//   await stake.deployed();

//   await stake.transferOwnership("0xcf1e5Bd9247b402Ec12e7c7A2CEad1F98ab30067");

//   console.log("Contract deployed to:", stake.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
