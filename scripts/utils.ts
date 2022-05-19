import { ethers } from "hardhat";
import { Signer } from "ethers";

const UNISWAP_ABI = [
    "function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts)"
  ];  

const uniswap = new ethers.Contract(
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
    UNISWAP_ABI,
    ethers.provider
);

export const makeSwap = async (signer: Signer, path: string[], value: string) => {
    await uniswap.connect(signer)
        .swapExactETHForTokens(
            0, path, await signer.getAddress(), 9999999999
        , { value: ethers.utils.parseEther(value)});    
}