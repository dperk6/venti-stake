// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers, run } from "hardhat";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const signers = await ethers.getSigners();

  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("21000000000000000000000000");
  await token.deployed();

  await token.connect(signers[0]).transfer(signers[1].address, ethers.utils.parseEther('1000'));
  await token.connect(signers[0]).transfer(signers[2].address, ethers.utils.parseEther('1000'));
  await token.connect(signers[0]).transfer(signers[3].address, ethers.utils.parseEther('1000'));
  await token.connect(signers[0]).transfer(signers[4].address, ethers.utils.parseEther('2000'));

  // We get the contract to deploy
  const Stake = await ethers.getContractFactory("VentiStake");
  
  // Fill in correct token address for prod deploy
  const stake = await Stake.deploy(token.address);

  await stake.deployed();

  await token.connect(signers[0]).transfer(stake.address, ethers.utils.parseEther('1000000'));

  await token.connect(signers[0]).approve(stake.address, ethers.utils.parseEther('1000000'));
  await stake.connect(signers[0]).fundStaking(ethers.utils.parseEther('1000000'));
  await stake.connect(signers[0]).enableStaking();

  console.log("Token deployed to:", token.address);
  console.log("Contract deployed to:", stake.address);
  
  await run("node");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
