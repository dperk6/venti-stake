# VentiSwap Staking Contract

This contract enables staking for VentiSwap token. It gives set reward rates per month based on lockup period determined by user on deposit:

1 month lockup = 1% of stake / month  
3 month lockup = 2% of stake / month  
6 month lockup = 3% of stake / month

## User Functions

### View functions

**stakingToken** -> returns staking token address

**totalSupply** -> returns total amount staked

**totalRewards** -> returns total amount of rewards in contract

**baseMultiplier** -> returns 1 month multiplier normalized to 1e18 (100%)

**balanceOf** -> takes address as param and returns account's staked amount

**getDeposit** -> takes address as param and returns all staking info (lock multiplier, timestamp, and staked amount)

**isActive** -> returns boolean showing if staking is active
timeEnded -> returns timestamp when staking finished (0 if active)

**pendingReward** -> takes account as param and returns pending amount prorated based on time (not yet claimable)

**earned** -> takes account as param and returns earned amount based on months passed (is claimable)

**withdrawable** -> takes account as param and returns boolean showing if user can withdraw their stake

### Mutative functions

**deposit** -> takes amount and lock period. NOTE: Lock 1 = 1 month, Lock 2 = 3 months, Lock 3 = 6 months.

**withdraw** -> takes amount as param and withdraws stake and claims all earned rewards

**claimRewards** -> claims all earned rewards for sender

## Owner functions

**fundStaking** -> takes amount as param and funds staking contract

**closeRewards** -> marks staking as inactive and locks timestamp as the end of rewards

**enableStaking** -> marks staking as active and allows deposits
