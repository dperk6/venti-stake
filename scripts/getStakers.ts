import { ethers } from "hardhat";
import { parse } from "csv-parse";
import { BigNumber } from "ethers";
import { stringify } from 'csv-stringify';
import fs from 'fs';

interface IStaker {
    address: string;
    amount: string;
    timestamp: string;
    term: string;
}

async function main() {
    const Stake = await ethers.getContractFactory('VentiStake');
    const stake = Stake.attach("0x2cA80c5A3eF3B39274CE19dEb2F94Aa16718ACaa");

    const process = async (): Promise<IStaker[]> => {
        const addresses: IStaker[] = [];
        const parseAddresses = fs.createReadStream(__dirname+'/ventistakers.csv').pipe(parse());

        for await (let item of parseAddresses) {
            const depositData = await stake.getDeposit(item[0]);
            addresses.push({
                address: item[0],
                amount: depositData.staked.toString(),
                timestamp: depositData.timestamp.toString(),
                term: depositData.lock.toString()
            });
        }

        return addresses;
    }

    const list = await process();

    stringify(list, async (err: any, output: any) => {
        fs.promises.writeFile(__dirname + '/full.csv', output);
    });

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});