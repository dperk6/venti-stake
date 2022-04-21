import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { TestToken, VentiStake } from "../typechain";

describe("VentiStake", function () {
  let token: TestToken;
  let signers: SignerWithAddress[];
  let ventiStake: VentiStake;

  beforeEach(async function () {
    signers = await ethers.getSigners();
    
    const VentiStake = await ethers.getContractFactory("VentiStake");
    const Token = await ethers.getContractFactory("TestToken");
    token = await Token.deploy("21000000000000000000000000");
    await token.deployed();

    ventiStake = await VentiStake.deploy(token.address);
    await ventiStake.deployed();

    await token.connect(signers[0]).transfer(signers[1].address, ethers.utils.parseEther('1000'));
    await token.connect(signers[0]).transfer(signers[2].address, ethers.utils.parseEther('1000'));
    await token.connect(signers[0]).transfer(signers[3].address, ethers.utils.parseEther('1000'));
    await token.connect(signers[0]).transfer(signers[4].address, ethers.utils.parseEther('2000'));

    await token.connect(signers[0]).approve(ventiStake.address, ethers.utils.parseEther('9999999999999'));
    await ventiStake.connect(signers[0]).fundStaking(ethers.utils.parseEther('10000000'));
    await ventiStake.connect(signers[0]).enableStaking();
  });

  it("Allow staking, claiming, and withdraw for multiple users", async function () {

    expect(await ventiStake.isActive()).to.equal(true);
    expect(Number(ethers.utils.formatEther(await token.balanceOf(ventiStake.address)))).to.equal(10000000);

    await ethers.provider.send('evm_mine', []);

    await token.connect(signers[1]).approve(ventiStake.address, ethers.utils.parseEther('1000'));
    await token.connect(signers[2]).approve(ventiStake.address, ethers.utils.parseEther('1000'));
    await token.connect(signers[3]).approve(ventiStake.address, ethers.utils.parseEther('1000'));
    await token.connect(signers[4]).approve(ventiStake.address, ethers.utils.parseEther('2000'));
    await ventiStake.connect(signers[1]).deposit(ethers.utils.parseEther('1000'), 1);
    await ventiStake.connect(signers[2]).deposit(ethers.utils.parseEther('1000'), 2);
    await ventiStake.connect(signers[3]).deposit(ethers.utils.parseEther('1000'), 3);
    await ventiStake.connect(signers[4]).deposit(ethers.utils.parseEther('1000'), 1);

    await ethers.provider.send('evm_mine', []);

    const totalStaked = await ventiStake.totalSupply().then((res: BigNumber) => ethers.utils.formatEther(res.toString()));
    const totalRewards = await ventiStake.totalRewards().then((res: BigNumber) => res);
    expect(Number(totalStaked)).to.equal(4000);
    expect(Number(ethers.utils.formatEther(totalRewards.toString()))).to.equal(10000000);

    // Should not be withdrawable yet
    expect(await ventiStake.withdrawable(signers[1].address)).to.equal(false);
    expect(await ventiStake.withdrawable(signers[2].address)).to.equal(false);
    expect(await ventiStake.withdrawable(signers[3].address)).to.equal(false);

    // Increase by 1 month + 1 second
    await ethers.provider.send("evm_increaseTime", [2628001]);
    await ethers.provider.send('evm_mine', []);

    const signer4Pending = Number(await ventiStake.pendingReward(signers[4].address).then((res: BigNumber) => ethers.utils.formatEther(res.toString())));
    const signer4Earned = Number(await ventiStake.earned(signers[4].address).then((res: BigNumber) => ethers.utils.formatEther(res.toString())));

    // Signer 4 will stake additional tokens for another 1 month lock
    await ventiStake.connect(signers[4]).deposit(ethers.utils.parseEther('1000'), 1);

    const signer4Staked = Number(await ventiStake.balanceOf(signers[4].address).then((res: BigNumber) => ethers.utils.formatEther(res.toString())));
    
    // Signer 4's stake should equal to total amount staked (2000) and include both pending and earned rewards
    expect(signer4Staked).to.greaterThan(2000 + signer4Pending + signer4Earned);
    expect(signer4Staked).to.lessThan(2011);

    // Signer 1 should be withdrawable, rest not
    expect(await ventiStake.withdrawable(signers[1].address)).to.equal(true);
    expect(await ventiStake.withdrawable(signers[2].address)).to.equal(false);
    expect(await ventiStake.withdrawable(signers[3].address)).to.equal(false);
    expect(await ventiStake.withdrawable(signers[4].address)).to.equal(false);

    // Signer 1 should have earned rewards of 1% of 1000
    // Signer 2 should have earned rewards of 2% of 1000
    // Signer 3 should have earned rewards of 3% of 1000
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[1].address)))).to.equal(10);
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[2].address)))).to.equal(20);
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[3].address)))).to.equal(30);

    // Claim rewards for each address
    await ventiStake.connect(signers[1]).claimRewards();
    await ventiStake.connect(signers[2]).claimRewards();
    await ventiStake.connect(signers[3]).claimRewards();

    await ethers.provider.send('evm_mine', []);

    // All earned rewards should now be 0
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[1].address)))).to.equal(0);
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[2].address)))).to.equal(0);
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[3].address)))).to.equal(0);

    // Increase by 2 months + 1 second
    await ethers.provider.send("evm_increaseTime", [2628000 * 2 + 1]);
    await ethers.provider.send('evm_mine', []);

    // Signer 1 and 2 should be withdrawable
    expect(await ventiStake.withdrawable(signers[1].address)).to.equal(true);
    expect(await ventiStake.withdrawable(signers[2].address)).to.equal(true);
    expect(await ventiStake.withdrawable(signers[3].address)).to.equal(false);

    // Additional 2 months of rewards at 1%, 2%, and 3% per month respectively
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[1].address)))).to.equal(20);
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[2].address)))).to.equal(40);
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[3].address)))).to.equal(60);

    await ventiStake.connect(signers[1]).withdraw(ethers.utils.parseEther('1000'));
    await ventiStake.connect(signers[2]).withdraw(ethers.utils.parseEther('1000'));
    // Signer 4 will be slightly more than 2010 due to re-staking pending
    const signer4Deposit = await ventiStake.getDeposit(signers[4].address);
    await ventiStake.connect(signers[4]).withdraw(signer4Deposit.staked.toString());

    await ethers.provider.send('evm_mine', []);

    // Signers 1 and 2 should have received original stake + rewards
    expect(Number(ethers.utils.formatEther(await token.balanceOf(signers[1].address)))).to.equal(1030);
    expect(Number(ethers.utils.formatEther(await token.balanceOf(signers[2].address)))).to.equal(1060);

    // Increase by 3 months + 1 second
    await ethers.provider.send("evm_increaseTime", [2628000 * 3 + 1]);
    await ethers.provider.send('evm_mine', []);

    // Signer 3 should now be withdrawable
    expect(await ventiStake.withdrawable(signers[3].address)).to.equal(true);

    // Increase by 6 months + 1 second
    await ethers.provider.send("evm_increaseTime", [2628000 * 6 + 1]);
    await ethers.provider.send('evm_mine', []);

    // End staking after 1 year
    await ventiStake.connect(signers[0]).closeRewards();

    // Increase by 6 months + 1 second
    await ethers.provider.send("evm_increaseTime", [2628000 * 6 + 1]);
    await ethers.provider.send('evm_mine', []);

    // 1 year and 6 months have passed, but rewards ended 6 months ago
    // After 1 year staked, signer 3 should earn 3% per month on 1000 tokens = 30 * 12 = 360 tokens
    // Signer 3 already claimed 30 tokens, so should equal 360 - 30 = 330
    expect(Number(ethers.utils.formatEther(await ventiStake.earned(signers[3].address)))).to.equal(330);

    await ventiStake.connect(signers[3]).withdraw(ethers.utils.parseEther('1000'));

    // Signer 3 should have withdrawn all rewards (including first claim) = 360 tokens + 1000 initial stake
    expect(Number(ethers.utils.formatEther(await token.balanceOf(signers[3].address)))).to.equal(1360);

    // Should be no stakes left in contract
    expect(Number(ethers.utils.formatEther(await ventiStake.totalSupply()))).to.equal(0);

    // Get owner balance
    const ownerBalance = await ethers.provider.getBalance(signers[0].address).then((res: BigNumber) => ethers.utils.formatEther(res.toString()));

    await signers[5].sendTransaction({
      to: ventiStake.address,
      value: ethers.utils.parseEther('1.0')
    });

    // Get updated owner balance
    const newOwnerBalance = await ethers.provider.getBalance(signers[0].address).then((res: BigNumber) => ethers.utils.formatEther(res.toString()));

    // Ensure fallback functions are working so any ETH
    // sent to contract is sent to owner address
    expect(Number(ownerBalance) + 1).to.equal(Number(newOwnerBalance));

    // Ensure owner can withdraw leftover reward tokens
    const ownerTokenBalance = await token.balanceOf(signers[0].address);
    const totalRewardsInContract = await ventiStake.totalRewards();
    await ventiStake.connect(signers[0]).withdrawRewardTokens();
    expect(await token.balanceOf(signers[0].address)).to.equal(ownerTokenBalance.add(totalRewardsInContract));
  });

  it("Should test the withdrawal pattern", async function() {
    await token.connect(signers[1]).approve(ventiStake.address, ethers.utils.parseEther('1000'));
    await ventiStake.connect(signers[1]).deposit(ethers.utils.parseEther('1000'), 1);

    // Increase by 2 months + 1 second
    await ethers.provider.send("evm_increaseTime", [2628000 * 2 + 1]);
    await ethers.provider.send('evm_mine', []);
    
    // Check that token balance after withdrawing is withdrawn amount + earned rewards
    const earnedRewards = await ventiStake.earned(signers[1].address);
    const preBalance = await token.balanceOf(signers[1].address);
    await ventiStake.connect(signers[1]).withdraw(ethers.utils.parseEther('500'));
    const postBalance = await token.balanceOf(signers[1].address);
    expect(postBalance.sub(preBalance)).to.equal(earnedRewards.add(BigNumber.from(ethers.utils.parseEther('500'))));

    // Verify that withdraw calculated successfully
    expect(await ventiStake.balanceOf(signers[1].address)).to.equal(BigNumber.from(ethers.utils.parseEther('500')));

    // Verify that earned rewards are 0
    expect(await ventiStake.earned(signers[1].address)).to.equal(0);

    // Increase by 1 month + 1 second
    await ethers.provider.send("evm_increaseTime", [2628002]);
    await ethers.provider.send('evm_mine', []);
    
    // Check it's marginally greater than 1% to account for dust
    expect(Number((ethers.utils.formatEther(await ventiStake.earned(signers[1].address))))).to.greaterThan(5);
    expect(Number((ethers.utils.formatEther(await ventiStake.earned(signers[1].address))))).to.lessThan(5.001);

    await ventiStake.connect(signers[1]).withdraw(await ventiStake.balanceOf(signers[1].address));

    expect(await ventiStake.totalSupply()).to.equal(0);
  });
});
