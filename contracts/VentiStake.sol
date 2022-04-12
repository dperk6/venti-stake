//SPDX-License-Identifier: MIT

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

    IERC20 public stakingToken; // Staking token

    uint256 private _totalSupply; // Total staked amount
    uint256 private _totalRewards;  // Total amount for rewards
    uint256 private _baseMultiplier = 1e16; // 1e18 = 100%; 1e16 = 1%
    uint256 private _isActive = 0; // 0 = false, 1 = true
    uint256 private _timeFinished; // Set completed timestamp so we know when rewards ended

    mapping (address => UserDeposit) private _deposits; // Track all user deposits
    mapping (address => uint256) private _userRewardPaid; // Track all user withdrawals

    struct UserDeposit {
        uint8 lock; // 1 = 1 month; 2 = 3 month; 3 = 6 month
        uint64 timestamp;
        uint256 staked;
    }

    constructor() {}

    // ===== VIEW FUNCTIONS ===== //

    /**
     @dev Returns total amount staked
     */
    function totalSupply() external view returns (uint256)
    {
        return _totalSupply;
    }

    function totalRewards() external view returns (uint256)
    {
        return stakingToken.balanceOf(address(this)).sub(_totalSupply);
    }

    function baseMultiplier() external view returns (uint256)
    {
        return _baseMultiplier;
    }

    function depositOf(address account) external view returns (uint256)
    {
        return _deposits[account].staked;
    }

    function isActive() external view returns (bool)
    {
        return _isActive == 1;
    }

    function timeEnded() external view returns (uint256)
    {
        return _timeFinished;
    }

    function pendingReward(address account) public view returns (uint256)
    {
        // If staking rewards are finished, should always return 0
        if (_timeFinished > 0) {
            return 0;
        }

        // Get deposit record for account
        UserDeposit memory userDeposit = _deposits[account];

        // Calculate total time, months, and time delta between
        uint256 timePassed = block.timestamp.sub(userDeposit.timestamp);
        uint256 monthsPassed = Math.floorDiv(timePassed, 2628000);
        uint256 interimTime = timePassed.sub(monthsPassed.mul(2628000));

        // Calculate pending rewards based on prorated time from the current month
        uint256 pending = uint256(userDeposit.staked)
            .mul(
                _baseMultiplier
                .mul(uint256(userDeposit.lock))
            ).div(1e18).mul(interimTime).div(2628000);

        return pending;
    }

    function earned(address account) public view returns (uint256)
    {
        // Get deposit record for account
        UserDeposit memory userDeposit = _deposits[account];
        
        // Get total rewards paid already
        uint256 rewardPaid = _userRewardPaid[account];

        // If a final timestamp is set, use that instead of current timestamp
        uint256 endTime = _timeFinished == 0 ? block.timestamp : _timeFinished;
        uint256 monthsPassed = Math.floorDiv(endTime.sub(userDeposit.timestamp), 2628000);

        // If no months have passed, return 0
        if (monthsPassed == 0) return 0;

        // Calculate total earned - amount already paid
        uint256 monthlyReward = userDeposit.staked
            .mul(
                _baseMultiplier
                .mul(uint256(userDeposit.lock)
            ).mul(monthsPassed)
            ).div(1e18).sub(rewardPaid);

        return monthlyReward;
    }

    function withdrawable(address account) public view returns (bool)
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

    // ===== MUTATIVE FUNCTIONS ===== //

    function deposit(uint256 amount, uint8 lock) external
    {
        // Check if staking is active
        require(_isActive != 0, "Staking inactive");
        require(_timeFinished == 0, "Staking finished"); // Should never get here, as _isActive should be set to false.

        // Transfer token
        stakingToken.transferFrom(msg.sender, address(this), amount);

        // Get current stake; add new amount to total supply
        uint256 currentStake = _deposits[msg.sender].staked;
        _totalSupply = _totalSupply.add(amount);

        // If user's current stake is greater than 0, we need
        // to get earned and pending rewards and add them to stake
        if (currentStake > 0) {
            currentStake = currentStake.add(earned(msg.sender));
            currentStake = currentStake.add(pendingReward(msg.sender));
        }

        // Create new deposit record for user with new lock time
        _deposits[msg.sender] = UserDeposit({
            lock: lock,
            timestamp: uint64(block.timestamp),
            staked: amount.add(currentStake)
        });
    }

    function withdraw(uint256 amount) external
    {
        // Get user deposit info
        UserDeposit memory userDeposit = _deposits[msg.sender];

        // Check if user can withdraw amount
        require(userDeposit.staked > 0, "User has no stake");
        require(withdrawable(msg.sender), "Lock still active");
        require(amount <= userDeposit.staked, "Withdraw amount too high");

        // Get earned rewards and paid rewards
        uint256 earnedRewards = earned(msg.sender);
        uint256 rewardPaid = _userRewardPaid[msg.sender];

        // Calculate amount to withdraw
        uint256 amountToWithdraw = amount.add(earnedRewards);

        // Check if user is withdrawing their total stake
        if (userDeposit.staked.sub(amount) == 0) {
            // If withdrawing full amount we no longer care about paid rewards
            _userRewardPaid[msg.sender] = 0;

            _deposits[msg.sender] = UserDeposit({
                lock: 0,
                timestamp: 0,
                staked: 0
            });
        } else {
            // We track amount of rewards paid for current stakers to subtract from earnings
            _userRewardPaid[msg.sender] = rewardPaid.add(earnedRewards);

            _deposits[msg.sender] = UserDeposit({
                lock: userDeposit.lock,
                timestamp: userDeposit.timestamp,
                staked: userDeposit.staked.sub(amount)
            });
        }

        // Update total staked amount
        _totalSupply = _totalSupply.sub(amount);

        // Transfer tokens to user
        stakingToken.safeTransfer(msg.sender, amountToWithdraw);
    }

    function claimRewards() external
    {
        // Get user's earned rewards
        uint256 amountToWithdraw = earned(msg.sender);
        
        require(amountToWithdraw > 0, "No rewards to withdraw");

        // Add amount to user's withdraw rewards
        _userRewardPaid[msg.sender] = _userRewardPaid[msg.sender].add(amountToWithdraw);


    }

    // ===== TESTING FUNCTIONS ===== //
    // TO BE DELETED //

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
            ).div(1e18).mul(interimTime).div(2628000);

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
}