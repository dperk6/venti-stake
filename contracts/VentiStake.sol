//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./libraries/Math.sol";
import "./libraries/Ownable.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IERC20.sol";

// solhint-disable not-rely-on-time, avoid-low-level-calls
contract VentiStake is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken; // Staking token

    uint256 private _totalSupply; // Total staked amount
    uint256 private _totalRewards;  // Total amount for rewards
    uint256 private _stakeRequired = 100e18; // Minimum stake amount

    // Set standard contract data in ContractData struct
    ContractData private _data = ContractData({
        isActive: 0,
        reentrant: 1,
        timeFinished: 0,
        baseMultiplier: 1e16
    });

    mapping (address => UserDeposit) private _deposits; // Track all user deposits
    mapping (address => uint256) private _userRewardPaid; // Track all user claims

    // Store global contract data in packed struct
    struct ContractData {
        uint8 isActive;
        uint8 reentrant;
        uint64 timeFinished;
        uint64 baseMultiplier;
    }

    // Store user deposit data in packed struct
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
        require(_data.reentrant == 1, "Reentrancy not allowed");
        _data.reentrant = 2;
        _;
        _data.reentrant = 1;
    }

    // ===== PAYABLE DEFAULTS ====== //

    fallback() external payable {
        owner().call{value: msg.value}("");
    }

    receive() external payable {
        owner().call{value: msg.value}("");
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
        return _totalRewards;
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
        return _data.baseMultiplier;
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
        return _data.isActive == 1;
    }

    /**
     * @dev Check current minimum stake amount
     *
     * @return minimum the min stake amount
     */
    function getMinimumStake() external view returns (uint256)
    {
        return _stakeRequired;
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
        return _data.timeFinished;
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
        if (_data.timeFinished > 0) {
            return 0;
        }

        // Get deposit record for account
        UserDeposit memory userDeposit = _deposits[account];

        if (userDeposit.staked == 0) {
            return 0;
        }

        // Calculate total time, months, and time delta between
        uint256 timePassed = block.timestamp - userDeposit.timestamp;
        uint256 monthsPassed = timePassed > 0 ? Math.floorDiv(timePassed, 2628000) : 0;
        uint256 interimTime = timePassed - (monthsPassed * 2628000);

        // Calculate pending rewards based on prorated time from the current month
        uint256 pending = userDeposit.staked * (_data.baseMultiplier * uint256(userDeposit.lock)) / 1e18 * interimTime / 2628000;
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
        uint256 endTime = _data.timeFinished == 0 ? block.timestamp : _data.timeFinished;
        uint256 monthsPassed = Math.floorDiv(endTime - userDeposit.timestamp, 2628000);

        // If no months have passed, return 0
        if (monthsPassed == 0) return 0;

        // Calculate total earned - amount already paid
        uint256 totalReward = userDeposit.staked * ((_data.baseMultiplier * userDeposit.lock) * monthsPassed) / 1e18 - rewardPaid;
        
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
     *
     * @notice Users cannot change lock periods if adding additional stake
     */
    function deposit(uint256 amount, uint8 lock) external payable nonReentrant
    {
        // Check if staking is active
        require(_data.isActive != 0, "Staking inactive");
        require(lock > 0 && lock < 4, "Lock must be 1, 2, or 3");
        require(amount > 0, "Amount cannot be 0");

        // Get existing user deposit. All 0s if non-existent
        UserDeposit storage userDeposit = _deposits[msg.sender];

        require(userDeposit.staked + amount >= _stakeRequired, "Need to meet minimum stake");

        // Transfer token
        stakingToken.transferFrom(msg.sender, address(this), amount);

        // If user's current stake is greater than 0, we need to get
        // earned and pending rewards and add them to stake and total
        if (userDeposit.staked > 0) {
            uint256 earnedAmount = earned(msg.sender);
            uint256 pendingAmount = pendingReward(msg.sender);
            uint256 combinedAmount = earnedAmount + pendingAmount;

            // Update user's claimed amount
            _userRewardPaid[msg.sender] += combinedAmount;

            // Update total rewards by subtracting earned/pending amounts
            _totalRewards -= combinedAmount;

            // Update total supply and current stake
            _totalSupply += amount + combinedAmount;

            // Save new deposit data
            userDeposit.staked += amount + combinedAmount;
            userDeposit.timestamp = uint64(block.timestamp);

            if (lock > userDeposit.lock || block.timestamp > _getUnlockTime(userDeposit.timestamp, userDeposit.lock)) {
                userDeposit.lock = lock;
            }
        } else {
            // Create new deposit record for user with new lock time
            userDeposit.lock = lock;
            userDeposit.timestamp = uint64(block.timestamp);
            userDeposit.staked = amount;

            // Add new amount to total supply
            _totalSupply += amount;
        }

        emit Deposited(msg.sender, amount);
    }

    /**
     * @dev Withdraws a user's stake.
     *
     * @param amount the amount to withdraw.
     *
     * @notice must be past unlock time.
     */
    function withdraw(uint256 amount) external payable nonReentrant
    {
        // Get user deposit info in storage
        UserDeposit storage userDeposit = _deposits[msg.sender];

        // Check if user can withdraw amount
        require(userDeposit.staked > 0, "User has no stake");
        require(withdrawable(msg.sender), "Lock still active");
        require(amount <= userDeposit.staked, "Withdraw amount too high");

        // Get earned rewards and paid rewards
        uint256 earnedRewards = earned(msg.sender);

        // Calculate amount to withdraw
        uint256 amountToWithdraw = amount + earnedRewards;

        // Check if user is withdrawing their total stake
        if (userDeposit.staked == amount) {
            // If withdrawing full amount we no longer care about paid rewards
            _userRewardPaid[msg.sender] = 0;
            // We only need to set staked to 0 because it is the only
            // value checked on future deposits
            userDeposit.staked = 0;
        } else {
            uint256 monthsForStaking;
            if (userDeposit.lock == 1) {
                monthsForStaking = 1;
            } else if (userDeposit.lock == 2) {
                monthsForStaking = 3;
            } else if (userDeposit.lock == 3) {
                monthsForStaking = 6;
            }
            // Remove amount from staked
            userDeposit.staked -= amount;
            // Start fresh
            _userRewardPaid[msg.sender] = 0;
            // Set new timestamp to 1, 3, or 6 months prior so users can still withdraw
            // from original stake time but rewards essentially restart
            userDeposit.timestamp = uint64(block.timestamp - (2628001 * monthsForStaking));
            _userRewardPaid[msg.sender] = earned(msg.sender);
        }

        // Update total staked amount and rewards amount
        _totalSupply -= amount;
        _totalRewards -= earnedRewards;

        // Transfer tokens to user
        stakingToken.safeTransfer(msg.sender, amountToWithdraw);

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @dev Emergency withdrawal in case rewards have been pulled
     *
     * @notice Only available after staking is closed and
     * all reward tokens have been withdrawn.
     */
    function emergencyWithdrawal() external payable
    {
        require(_data.isActive == 0, "Staking must be closed");
        require(_data.timeFinished > 0, "Staking must be closed");
        require(_totalRewards == 0, "Use normal withdraw");

        // Get user deposit info
        uint256 amountToWithdraw = _deposits[msg.sender].staked;
        require(amountToWithdraw > 0, "No stake to withdraw");

        // Reset all data
        _userRewardPaid[msg.sender] = 0;
        _deposits[msg.sender].staked = 0;

        // Update total staked amount
        _totalSupply -= amountToWithdraw;

        // Transfer tokens to user
        stakingToken.safeTransfer(msg.sender, amountToWithdraw);

        emit Withdrawal(msg.sender, amountToWithdraw);
    }

    /**
     * @dev Claims earned rewards.
     */
    function claimRewards() external payable nonReentrant
    {
        // Get user's earned rewards
        uint256 amountToWithdraw = earned(msg.sender);
        
        require(amountToWithdraw > 0, "No rewards to withdraw");
        require(amountToWithdraw <= _totalRewards, "Not enough rewards in contract");

        // Add amount to user's withdraw rewards
        _userRewardPaid[msg.sender] += amountToWithdraw;

        // Update total rewards
        _totalRewards -= amountToWithdraw;

        stakingToken.safeTransfer(msg.sender, amountToWithdraw);

        emit RewardsClaimed(amountToWithdraw);
    }

    /**
     * @dev Update minimum stake amount
     *
     * @param minimum the new minimum stake account
     */
    function updateMinimum(uint256 minimum) external payable onlyOwner
    {
        _stakeRequired = minimum;
        
        emit MinimumUpdated(minimum);
    }

    /**
     * @dev Funds rewards for contract
     *
     * @param amount the amount of tokens to fund
     */
    function fundStaking(uint256 amount) external payable onlyOwner
    {
        require(amount > 0, "Amount cannot be 0");

        _totalRewards += amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit StakingFunded(amount);
    }

    /**
     * @dev Withdraws rewards tokens
     *
     * @notice Requires rewards to be closed. This
     * function is intended to pull leftover tokens
     * once all users have claimed rewards.
     */
    function withdrawRewardTokens() external payable onlyOwner
    {
        require(_data.timeFinished > 0, "Staking must be complete");

        uint256 amountToWithdraw = _totalRewards;
        _totalRewards = 0;

        stakingToken.safeTransfer(owner(), amountToWithdraw);
    }

    /**
     * @dev Closes reward period
     *
     * @notice This is a one-way function. Once staking is closed, it
     * cannot be re-enabled. Use cautiously.
     */
    function closeRewards() external payable onlyOwner
    {
        require(_data.isActive == 1, "Contract already inactive");
        _data.isActive = 0;
        _data.timeFinished = uint64(block.timestamp);
        
        emit StakingEnded(block.timestamp);
    }

    /**
     * @dev Enables staking
     */
    function enableStaking() external payable onlyOwner
    {
        require(_data.isActive == 0, "Staking already active");
        _data.isActive = 1;

        emit StakingEnabled();
    }

    // ===== EVENTS ===== //

    event StakingFunded(uint256 amount);
    event StakingEnabled();
    event StakingEnded(uint256 timestamp);
    event RewardsClaimed(uint256 amount);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
    event MinimumUpdated(uint256 newMinimum);
}