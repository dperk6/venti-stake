//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./libraries/Math.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Ownable.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IERC20.sol";

contract VentiStake is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 private _totalSupply; // Total staked amount
    uint256 private _baseMultiplier = 100; // base multiplier is 100 aka 1.00%
    mapping (address => UserDeposit) private _deposits; // Track all user deposits
    mapping (address => uint256) private _userRewardPaid; // Track all user withdrawals

    struct UserDeposit {
        uint8 lock; // 1 = 1 month; 2 = 3 month; 3 = 6 month
        uint64 timestamp;
        uint184 deposited;
    }

    constructor() {}

    function totalSupply() external view returns (uint256)
    {
        return _totalSupply;
    }

    function baseMultiplier() external view returns (uint256)
    {
        return _baseMultiplier;
    }

    function depositOf(address account) external view returns (UserDeposit memory)
    {
        return _deposits[account];
    }

    function test(uint256 testVal1, uint256 testVal2) external view
    {
        uint256 rewardPaid = 0;
        uint256 timePassed = block.timestamp.sub(testVal1);
        uint256 monthsPassed = Math.floorDiv(timePassed, 2628000);
        uint256 interimTime = timePassed.sub(monthsPassed.mul(2628000));

        console.log(interimTime);

        uint256 pending = uint256(testVal2)
            .mul(
                _baseMultiplier
                .mul(uint256(3))
            ).div(100000).mul(interimTime).div(2628000);

        console.log(pending);

        uint256 monthlyReward = uint256(testVal2)
            .mul(
                _baseMultiplier
                .mul(uint256(3)
            ).mul(monthsPassed)
            ).div(10000).sub(rewardPaid);

        console.log(monthlyReward);
        console.log(monthsPassed);
    }

    function pendingReward(address account) external view returns (uint256)
    {
        UserDeposit memory userDeposit = _deposits[account];
        uint256 timePassed = block.timestamp.sub(userDeposit.timestamp);
        uint256 monthsPassed = Math.floorDiv(timePassed, 2628000);
        uint256 interimTime = timePassed.sub(monthsPassed.mul(2628000));

        uint256 pending = uint256(userDeposit.deposited)
            .mul(
                _baseMultiplier
                .mul(uint256(userDeposit.lock))
            ).mul(10000).mul(interimTime).div(2628000);

        return pending;
    }

    function earned(address account) external view returns (uint256)
    {
        UserDeposit memory userDeposit = _deposits[account];
        uint256 rewardPaid = _userRewardPaid[account];
        uint256 monthsPassed = Math.floorDiv(block.timestamp.sub(userDeposit.timestamp), 2628000);
        if (monthsPassed == 0) return 0;

        uint256 monthlyReward = uint256(userDeposit.deposited)
            .mul(
                _baseMultiplier
                .mul(uint256(userDeposit.lock)
            ).mul(monthsPassed)
            ).div(10000).sub(rewardPaid);

        return monthlyReward;
    }

    function withdrawable(address account) external view returns (bool)
    {
        UserDeposit memory userDeposit = _deposits[account];
        uint256 unlockTime = _getUnlockTime(userDeposit.timestamp, userDeposit.lock);
        
        if (block.timestamp < unlockTime) {
            return false;
        } else {
            return true;
        }
    }

    function _getUnlockTime(uint64 timestamp, uint8 lock) private pure returns (uint256)
    {
        if (lock == 1) {
            // Add one month
            return timestamp + 2628000;
        } else if (lock == 2) {
            // Add three months
            return timestamp + (2628000 * 3);            
        } else {
            // Add six months
            return timestamp + (2628000 * 6);
        }
    }
}