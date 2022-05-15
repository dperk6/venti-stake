// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import { parse } from "csv-parse";
import fs from "fs";

interface IStaker {
  account: string;
  staked: string;
  timestamp: string;
  lock: string;
}

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const accounts = await ethers.getSigners();
  console.log("Deployer address:", accounts[0].address);

  // We get the contract to deploy
  const Stake = await ethers.getContractFactory("VentiStake");

  // Fill in correct token address for prod deploy
  const stake = await Stake.deploy(
    "0xb7C2fcD6d7922eddd2A7A9B0524074A60D5b472C"
  );

  await stake.deployed();

  const process = async (): Promise<IStaker[]> => {
    const addresses: IStaker[] = [];
    const parseAddresses = fs
      .createReadStream(__dirname + "/full.csv")
      .pipe(parse());

    for await (let item of parseAddresses) {
      addresses.push({
        account: item[0],
        staked: item[1],
        timestamp: item[2],
        lock: item[3],
      });
    }

    return addresses;
  };

  const list = await process();

  await stake.stakeOnBehalfOfAll(list);

  await stake.transferOwnership("0xcf1e5bd9247b402ec12e7c7a2cead1f98ab30067");

  console.log("Contract deployed to:", stake.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
