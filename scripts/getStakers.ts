import { ethers } from "hardhat";
import { parse } from "csv-parse";
import { BigNumber } from "ethers";
import { stringify } from 'csv-stringify';
import fs from 'fs';
import { getAddress } from "ethers/lib/utils";

interface IStaker {
    address: string;
    amount: string;
    timestamp: string;
    term: string;
}

const parseAddresses = [
    '0x7d435446213fb32fbcb8a1ebf9ce6c44f35e715f',
    '0x80ff59d3518ca8954c5c2a642fc3d553486a9bbd',
    '0x9efb5693496ca75f5db23c5505997c1f2f2456a7',
    '0x2dcb1b6b0fb446ac70ed0dbbe88d949d3586a8ce',
    '0xa2c7948ade41665503cbc1a06bb0af4da4934c5e',
    '0x94b9b40c487756b5dc3b78fa10c52ff9c6fc5da7',
    '0xf42f081ac661887dfff58063d451236661173ce7',
    '0x23547d6a18e3a9ee9196e15f8383189b3f208893',
    '0x1da8d7f70f61505e185e67f5975c93d1b1eb75dd',
    '0xffd908da661e52d2d245916ef1ccc5d8b2e918dd',
    '0x2771867e092dd7db262fa34fa5a2ba7090f3e939',
    '0x60afa2c15f771cdfabd3c95b4e8dad9d5e852baf'
]

async function main() {
    const Stake = await ethers.getContractFactory('VentiStake');
    const stake = Stake.attach("0x2cA80c5A3eF3B39274CE19dEb2F94Aa16718ACaa");

    const process = async (): Promise<IStaker[]> => {
        const addresses: IStaker[] = [];
        // const parseAddresses = fs.createReadStream(__dirname+'/update.csv').pipe(parse());

        for (let i = 0; i < parseAddresses.length; i++)
        {
            const depositData = await stake.getDeposit(parseAddresses[i]);
            addresses.push({
                address: parseAddresses[i],
                amount: depositData.staked.toString(),
                timestamp: depositData.timestamp.toString(),
                term: depositData.lock.toString()
            });
        }

        return addresses;
    }

    const list = await process();

    stringify(list, async (err: any, output: any) => {
        fs.promises.writeFile(__dirname + '/full-update.csv', output);
    });

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});