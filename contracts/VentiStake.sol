//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./libraries/Math.sol";
import "./libraries/Ownable.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IERC20.sol";

// solhint-disable not-rely-on-time
contract VentiStake is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken; // Staking token

    uint256 private _totalSupply; // Total staked amount
    uint256 private _totalRewards;  // Total amount for rewards
    uint256 private _baseMultiplier = 1e16; // 1e18 = 100%; 1e16 = 1%
    uint256 private _isActive = 0; // 0 = false, 1 = true
    uint256 private _timeFinished; // Set completed timestamp so we know when rewards ended
    uint256 private _reentrant;

    mapping (address => UserDeposit) private _deposits; // Track all user deposits
    mapping (address => uint256) private _userRewardPaid; // Track all user withdrawals

    struct UserDeposit {
        uint8 lock; // 1 = 1 month; 2 = 3 month; 3 = 6 month
        uint64 timestamp;
        uint256 staked;
    }

    constructor(IERC20 stakingToken_) {
        stakingToken = stakingToken_;
    }

    // ===== MODIFIERS ===== //

    /**
     * @dev Reentrancy protection
     */
    modifier nonReentrant()
    {
        require(_reentrant == 0, "Reentrancy not allowed");
        _reentrant = 1;
        _;
        _reentrant = 0;
    }

    // ===== VIEW FUNCTIONS ===== //

    /**
     * @dev Check total amount staked
     *
     * @return totalSupply the total amount staked
     */
    function totalSupply() external view returns (uint256)
    {
        return _totalSupply;
    }

    /**
     * @dev Check total rewards amount
     *
     * @notice this assumes that staking token is the same as reward token
     *
     * @return totalRewards the total balance of contract - amount staked
     */
    function totalRewards() external view returns (uint256)
    {
        return stakingToken.balanceOf(address(this)) - _totalSupply;
    }

    /**
     * @dev Check base multiplier of contract
     *
     * @notice Normalized to 1e18 = 100%. Contract currently uses a 1x, 2x, and 3x multiplier
     * based on how long the user locks their stake for (in UserDeposit struct).
     * Therefore max baseMultiplier would be <= 333e15 (33.3%).
     *
     * @return baseMultiplier 1e18 normalized percentage to start 
     */
    function baseMultiplier() external view returns (uint256)
    {
        return _baseMultiplier;
    }

    /**
     * @dev Checks amount staked for account.
     *
     * @param account the user account to look up.
     *
     * @return staked the total amount staked from account.
     */
    function balanceOf(address account) external view returns (uint256)
    {
        return _deposits[account].staked;
    }

    /**
     * @dev Checks all user deposit data for account.
     *
     * @param account the user account to look up.
     *
     * @return userDeposit the entire deposit data.
     */
    function getDeposit(address account) external view returns (UserDeposit memory)
    {
        return _deposits[account];
    }

    /**
     * @dev Checks if staking contract is active.
     *
     * @notice _isActive is stored as uint where 0 = false; 1 = true.
     *
     * @return isActive boolean true if 1; false if not.
     */
    function isActive() external view returns (bool)
    {
        return _isActive == 1;
    }

    /**
     * @dev Checks when staking finished.
     *
     * @notice if 0, staking is still active.
     *
     * @return timeFinished the block timestamp of when staking completed.
     */
    function timeEnded() external view returns (uint256)
    {
        return _timeFinished;
    }

    /**
     * @dev Checks pending rewards currently accumulating for month.
     *
     * @notice These rewards are prorated for the current period (month).
     * Users cannot withdraw rewards until a full month has passed.
     * If a user makes an additional deposit mid-month, these pending rewards
     * will be added to their new staked amount, and lock time reset.
     *
     * @param account the user account to use for calculation.
     *
     * @return pending the pending reward for the current period.
     */
    function pendingReward(address account) public view returns (uint256)
    {
        // If staking rewards are finished, should always return 0
        if (_timeFinished > 0) {
            return 0;
        }

        // Get deposit record for account
        UserDeposit memory userDeposit = _deposits[account];

        // Calculate total time, months, and time delta between
        uint256 timePassed = block.timestamp - userDeposit.timestamp;
        uint256 monthsPassed = Math.floorDiv(timePassed, 2628000);
        uint256 interimTime = timePassed - (monthsPassed * 2628000);

        // Calculate pending rewards based on prorated time from the current month
        uint256 pending = userDeposit.staked * (_baseMultiplier * uint256(userDeposit.lock)) / 1e18 * interimTime / 2628000;

        return pending;
    }

    /**
     * @dev Checks current earned rewards for account.
     *
     * @notice These rewards are calculated by the number of full months
     * passed since deposit, based on the multiplier set by the user based on
     * lockup time (i.e. 1x for 1 month, 2x for 3 months, 3x for 6 months).
     * This function subtracts withdrawn rewards from the calculation so if
     * total rewards are 100 coins, but 50 are withdrawn,
     * it should return 50.
     *
     * @param account the user account to use for calculation.
     *
     * @return totalReward the total rewards the user has earned.
     */
    function earned(address account) public view returns (uint256)
    {
        // Get deposit record for account
        UserDeposit memory userDeposit = _deposits[account];
        
        // Get total rewards paid already
        uint256 rewardPaid = _userRewardPaid[account];

        // If a final timestamp is set, use that instead of current timestamp
        uint256 endTime = _timeFinished == 0 ? block.timestamp : _timeFinished;
        uint256 monthsPassed = Math.floorDiv(endTime - userDeposit.timestamp, 2628000);

        // If no months have passed, return 0
        if (monthsPassed == 0) return 0;

        // Calculate total earned - amount already paid
        uint256 totalReward = userDeposit.staked * ((_baseMultiplier * uint256(userDeposit.lock)) * monthsPassed) / 1e18 - rewardPaid;

        return totalReward;
    }

    /**
     * @dev Check if user can withdraw their stake.
     *
     * @notice uses the user's lock chosen on deposit, multiplied
     * by the amount of seconds in a month.
     *
     * @param account the user account to check.
     *
     * @return canWithdraw boolean value determining if user can withdraw stake.
     */
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

    /**
     * @dev Check if current time past lock time.
     *
     * @param timestamp the user's initial lock time.
     * @param lock the lock multiplier chosen (1 = 1 month, 2 = 3 month, 3 = 6 month).
     *
     * @return unlockTime the timestamp after which a user can withdraw.
     */
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

    /**
     * @dev Deposit and stake funds
     *
     * @param amount the amount of tokens to stake
     * @param lock the lock multiplier (1 = 1 month, 2 = 3 month, 3 = 6 month).
     */
    function deposit(uint256 amount, uint8 lock) external nonReentrant
    {
        // Check if staking is active
        require(_isActive != 0, "Staking inactive");
        require(_timeFinished == 0, "Staking finished"); // Should never get here, as _isActive should be set to false.
        require(lock > 0 && lock < 4, "Lock must be 1, 2, or 3");

        // Transfer token
        stakingToken.transferFrom(msg.sender, address(this), amount);

        // Get current stake; add new amount to total supply
        uint256 currentStake = _deposits[msg.sender].staked;
        _totalSupply += amount;

        // If user's current stake is greater than 0, we need to get
        // earned and pending rewards and add them to stake and total
        if (currentStake > 0) {
            uint256 earnedAmount = earned(msg.sender);
            uint256 pendingAmount = pendingReward(msg.sender);
            _totalSupply += earnedAmount + pendingAmount;
            currentStake += earnedAmount + pendingAmount;
        }

        // Create new deposit record for user with new lock time
        _deposits[msg.sender] = UserDeposit({
            lock: lock,
            timestamp: uint64(block.timestamp),
            staked: amount + currentStake
        });

        emit Deposited(msg.sender, amount);
    }

    /**
     * @dev Withdraws a user's stake.
     *
     * @param amount the amount to withdraw.
     *
     * @notice must be past unlock time.
     */
    function withdraw(uint256 amount) external nonReentrant
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
        uint256 amountToWithdraw = amount + earnedRewards;

        // Check if user is withdrawing their total stake
        if (userDeposit.staked - amount == 0) {
            // If withdrawing full amount we no longer care about paid rewards
            _userRewardPaid[msg.sender] = 0;

            _deposits[msg.sender] = UserDeposit({
                lock: 0,
                timestamp: 0,
                staked: 0
            });
        } else {
            // We track amount of rewards paid for current stakers to subtract from earnings
            _userRewardPaid[msg.sender] = rewardPaid + earnedRewards;

            _deposits[msg.sender] = UserDeposit({
                lock: userDeposit.lock,
                timestamp: userDeposit.timestamp,
                staked: userDeposit.staked - amount
            });
        }

        // Update total staked amount
        _totalSupply = _totalSupply - amount;

        // Transfer tokens to user
        stakingToken.safeTransfer(msg.sender, amountToWithdraw);

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @dev Claims earned rewards.
     */
    function claimRewards() external nonReentrant
    {
        // Get user's earned rewards
        uint256 amountToWithdraw = earned(msg.sender);
        
        require(amountToWithdraw > 0, "No rewards to withdraw");

        // Add amount to user's withdraw rewards
        _userRewardPaid[msg.sender] = _userRewardPaid[msg.sender] + amountToWithdraw;

        stakingToken.transfer(msg.sender, amountToWithdraw);

        emit RewardsClaimed(amountToWithdraw);
    }

    /**
     * @dev Funds rewards for contract
     *
     * @param amount the amount of tokens to fund
     */
    function fundStaking(uint256 amount) external onlyOwner
    {
        require(amount > 0, "Amount cannot be 0");

        _totalRewards = _totalRewards + amount;

        stakingToken.transferFrom(msg.sender, address(this), amount);

        emit StakingFunded(amount);
    }

    /**
     * @dev Closes reward period
     *
     * @notice This is a one-way function. Once staking is closed, it
     * cannot be re-enabled. Use cautiously.
     */
    function closeRewards() external onlyOwner
    {
        require(_isActive == 1, "Contract already inactive");
        _isActive = 0;
        _timeFinished = block.timestamp;
        
        emit StakingEnded(block.timestamp);
    }

    /**
     * @dev Enables staking
     */
    function enableStaking() external onlyOwner
    {
        require(_isActive == 0, "Staking already active");
        _isActive = 1;

        emit StakingEnabled();
    }

    // ===== EVENTS ===== //

    event StakingFunded(uint256 amount);
    event StakingEnabled();
    event StakingEnded(uint256 timestamp);
    event RewardsClaimed(uint256 amount);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
}