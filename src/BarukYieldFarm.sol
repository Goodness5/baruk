// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ISeiOracle.sol";

contract BarukYieldFarm {
    IERC20 public immutable lpToken;
    address public governance;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    bool public paused;
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }
    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }

    constructor(address _lpToken) {
        lpToken = IERC20(_lpToken);
        governance = msg.sender;
    }

    // Multi-pool support
    struct Pool {
        IERC20 stakedToken;
        IERC20 rewardToken;
        uint256 rewardRate; // reward per block
        uint256 lastUpdateBlock;
        uint256 rewardPerTokenStored;
        uint256 totalStaked;
    }
    Pool[] public pools;
    // user => poolId => amount
    mapping(uint256 => mapping(address => uint256)) public staked;
    mapping(uint256 => mapping(address => uint256)) public userRewardPerTokenPaid;
    mapping(uint256 => mapping(address => uint256)) public accumulatedRewards;

    event PoolAdded(uint256 indexed poolId, address stakedToken, address rewardToken, uint256 rewardRate);

    ISeiOracle constant ORACLE = ISeiOracle(0x0000000000000000000000000000000000001008);
    uint64 public constant PRICE_LOOKBACK_SECONDS = 60;
    uint64 public constant PRICE_STALENESS_THRESHOLD = 60;

    // Dynamic mapping from token address to denom string
    mapping(address => string) public tokenDenoms;
    event TokenDenomSet(address indexed token, string denom);

    // Governance function to set token-denom mapping
    function setTokenDenom(address token, string calldata denom) external onlyGovernance {
        tokenDenoms[token] = denom;
        emit TokenDenomSet(token, denom);
    }

    // Dynamic TWAP fetcher using mapping
    function getTokenTwap(address token) public view returns (uint256 price, int64 oracleLastUpdate) {
        string memory denom = tokenDenoms[token];
        require(bytes(denom).length > 0, "No denom set");
        (price, oracleLastUpdate) = getTwap(denom);
        require(price > 0, "No price");
        require(block.timestamp - uint64(oracleLastUpdate) <= PRICE_STALENESS_THRESHOLD, "Stale price");
    }

    function getTwap(string memory denom) public view returns (uint256 price, int64 lastUpdateTimestamp) {
        ISeiOracle.OracleTwap[] memory twaps = ORACLE.getOracleTwaps(PRICE_LOOKBACK_SECONDS);
        for (uint i = 0; i < twaps.length; i++) {
            if (keccak256(abi.encodePacked(twaps[i].denom)) == keccak256(abi.encodePacked(denom))) {
                price = parseStringToUint(twaps[i].twap);
                lastUpdateTimestamp = twaps[i].lookbackSeconds;
                return (price, lastUpdateTimestamp);
            }
        }
        return (0, 0);
    }

    function parseStringToUint(string memory s) internal pure returns (uint256 result) {
        bytes memory b = bytes(s);
        for (uint i = 0; i < b.length; i++) {
            if (b[i] >= 0x30 && b[i] <= 0x39) {
                result = result * 10 + (uint8(b[i]) - 48);
            }
        }
    }

    // Add a new staking pool (governance only)
    function addPool(address stakedToken, address rewardToken, uint256 rewardRate) external onlyGovernance {
        require(stakedToken != address(0), "Zero staked token");
        require(rewardToken != address(0), "Zero reward token");
        require(rewardRate > 0, "Zero reward rate");
        pools.push(Pool({
            stakedToken: IERC20(stakedToken),
            rewardToken: IERC20(rewardToken),
            rewardRate: rewardRate,
            lastUpdateBlock: block.number,
            rewardPerTokenStored: 0,
            totalStaked: 0
        }));
        emit PoolAdded(pools.length - 1, stakedToken, rewardToken, rewardRate);
    }

    // Update reward for user in a pool
    modifier updateReward(uint256 poolId, address account) {
        Pool storage pool = pools[poolId];
        pool.rewardPerTokenStored = rewardPerToken(poolId);
        pool.lastUpdateBlock = block.number;
        if (account != address(0)) {
            accumulatedRewards[poolId][account] = earned(poolId, account);
            userRewardPerTokenPaid[poolId][account] = pool.rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken(uint256 poolId) public view returns (uint256) {
        Pool storage pool = pools[poolId];
        if (pool.totalStaked == 0) return pool.rewardPerTokenStored;
        return pool.rewardPerTokenStored + (pool.rewardRate * (block.number - pool.lastUpdateBlock) * 1e18 / pool.totalStaked);
    }

    // Boost and lockup logic
    struct Lockup {
        uint256 amount;
        uint256 unlockBlock;
        uint256 boostMultiplier; // e.g., 120 = 1.2x
    }
    mapping(uint256 => mapping(address => Lockup)) public lockups; // poolId => user => Lockup
    event Locked(address indexed user, uint256 poolId, uint256 amount, uint256 unlockBlock, uint256 boostMultiplier);
    event Unlocked(address indexed user, uint256 poolId, uint256 amount);

    // Lock stake for boost
    function lockStake(uint256 poolId, uint256 amount, uint256 lockBlocks, uint256 boostMultiplier) public updateReward(poolId, msg.sender) {
        require(poolId < pools.length, "Invalid poolId");
        require(amount > 0 && staked[poolId][msg.sender] >= amount, "Insufficient staked");
        require(lockBlocks > 0, "Zero lock period");
        staked[poolId][msg.sender] -= amount;
        lockups[poolId][msg.sender].amount += amount;
        lockups[poolId][msg.sender].unlockBlock = block.number + lockBlocks;
        lockups[poolId][msg.sender].boostMultiplier = boostMultiplier;
        emit Locked(msg.sender, poolId, amount, lockups[poolId][msg.sender].unlockBlock, boostMultiplier);
    }
    // Unlock after lockup
    function unlockStake(uint256 poolId) public updateReward(poolId, msg.sender) {
        Lockup storage l = lockups[poolId][msg.sender];
        require(l.amount > 0, "No locked stake");
        require(block.number >= l.unlockBlock, "Still locked");
        staked[poolId][msg.sender] += l.amount;
        emit Unlocked(msg.sender, poolId, l.amount);
        l.amount = 0;
        l.unlockBlock = 0;
        l.boostMultiplier = 0;
    }
    // Override earned to include boost
    function earned(uint256 poolId, address account) public view returns (uint256) {
        uint256 base = (staked[poolId][account] * (rewardPerToken(poolId) - userRewardPerTokenPaid[poolId][account]) / 1e18) + accumulatedRewards[poolId][account];
        Lockup storage l = lockups[poolId][account];
        if (l.amount > 0) {
            uint256 lockedReward = l.amount * (rewardPerToken(poolId) - userRewardPerTokenPaid[poolId][account]) / 1e18;
            lockedReward = lockedReward * l.boostMultiplier / 100;
            base += lockedReward;
        }
        return base;
    }

    function stake(uint256 poolId, uint256 amount) public updateReward(poolId, msg.sender) {
        require(amount > 0, "Zero amount");
        Pool storage pool = pools[poolId];
        pool.stakedToken.transferFrom(msg.sender, address(this), amount);
        staked[poolId][msg.sender] += amount;
        pool.totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 poolId, uint256 amount) public updateReward(poolId, msg.sender) {
        require(poolId < pools.length, "Invalid poolId");
        require(amount > 0 && staked[poolId][msg.sender] >= amount, "Insufficient staked");
        Pool storage pool = pools[poolId];
        staked[poolId][msg.sender] -= amount;
        pool.totalStaked -= amount;
        pool.stakedToken.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    // Protocol fee and treasury
    uint256 public protocolFeeBps = 5; // 0.05% default
    address public protocolTreasury;
    uint256 public protocolFeesAccrued;
    event ProtocolFeeSet(uint256 newFeeBps, address newTreasury);
    event ProtocolFeeAccrued(address indexed treasury, uint256 amount);
    event ProtocolFeeClaimed(address indexed treasury, uint256 amount);

    // Governance function to set protocol fee and treasury
    function setProtocolFee(uint256 newFeeBps, address newTreasury) external onlyGovernance {
        require(newFeeBps <= 100, "Fee too high");
        protocolFeeBps = newFeeBps;
        protocolTreasury = newTreasury;
        emit ProtocolFeeSet(newFeeBps, newTreasury);
    }

    // Protocol can claim accrued fees
    function claimProtocolFees() external {
        require(msg.sender == protocolTreasury, "Not treasury");
        uint256 amount = protocolFeesAccrued;
        require(amount > 0, "No fees");
        protocolFeesAccrued = 0;
        pools[0].rewardToken.transfer(protocolTreasury, amount); // For demo, use pool 0's reward token
        emit ProtocolFeeClaimed(protocolTreasury, amount);
    }

    // Update claimReward to take protocol fee
    function claimReward(uint256 poolId) public updateReward(poolId, msg.sender) {
        uint256 reward = accumulatedRewards[poolId][msg.sender];
        require(reward > 0, "No reward");
        uint256 protocolFee = (reward * protocolFeeBps) / 10000;
        protocolFeesAccrued += protocolFee;
        emit ProtocolFeeAccrued(protocolTreasury, protocolFee);
        uint256 rewardAfterFee = reward - protocolFee;
        accumulatedRewards[poolId][msg.sender] = 0;
        pools[poolId].rewardToken.transfer(msg.sender, rewardAfterFee);
        emit RewardClaimed(msg.sender, rewardAfterFee);
    }

    // View function for lending: available reserve of a token (sum of all pools for that token)
    function availableReserve(address token) external view returns (uint256 totalReserve) {
        for (uint256 i = 0; i < pools.length; i++) {
            if (address(pools[i].stakedToken) == token) {
                totalReserve += pools[i].totalStaked;
            }
        }
    }

    // Integration hook: called by lending contract to use reserves (governance only, for security)
    function lendOut(address token, address to, uint256 amount) external onlyAuthorizedLender {
        IERC20(token).transfer(to, amount);
    }

    event AnalyticsStake(address indexed user, uint256 poolId, uint256 amount, uint256 blockNumber);
    event AnalyticsUnstake(address indexed user, uint256 poolId, uint256 amount, uint256 blockNumber);
    event AnalyticsClaimReward(address indexed user, uint256 poolId, uint256 amount, uint256 blockNumber);
    event AnalyticsLock(address indexed user, uint256 poolId, uint256 amount, uint256 unlockBlock, uint256 boostMultiplier, uint256 blockNumber);
    event AnalyticsUnlock(address indexed user, uint256 poolId, uint256 amount, uint256 blockNumber);
    event AnalyticsPoolAdded(uint256 indexed poolId, address stakedToken, address rewardToken, uint256 rewardRate, uint256 blockNumber);

    // Batch operations
    event BatchStake(address indexed user, uint256 count);
    event BatchUnstake(address indexed user, uint256 count);
    event BatchClaimReward(address indexed user, uint256 count);
    event BatchLockStake(address indexed user, uint256 count);
    event BatchUnlockStake(address indexed user, uint256 count);

    function batchStake(uint256[] calldata poolIds, uint256[] calldata amounts) external {
        require(poolIds.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < poolIds.length; i++) {
            stake(poolIds[i], amounts[i]);
        }
        emit BatchStake(msg.sender, poolIds.length);
    }
    function batchUnstake(uint256[] calldata poolIds, uint256[] calldata amounts) external {
        require(poolIds.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < poolIds.length; i++) {
            unstake(poolIds[i], amounts[i]);
        }
        emit BatchUnstake(msg.sender, poolIds.length);
    }
    function batchClaimReward(uint256[] calldata poolIds) external {
        for (uint256 i = 0; i < poolIds.length; i++) {
            claimReward(poolIds[i]);
        }
        emit BatchClaimReward(msg.sender, poolIds.length);
    }
    function batchLockStake(uint256[] calldata poolIds, uint256[] calldata amounts, uint256[] calldata lockBlocks, uint256[] calldata boostMultipliers) external {
        require(poolIds.length == amounts.length && amounts.length == lockBlocks.length && lockBlocks.length == boostMultipliers.length, "Length mismatch");
        for (uint256 i = 0; i < poolIds.length; i++) {
            lockStake(poolIds[i], amounts[i], lockBlocks[i], boostMultipliers[i]);
        }
        emit BatchLockStake(msg.sender, poolIds.length);
    }
    function batchUnlockStake(uint256[] calldata poolIds) external {
        for (uint256 i = 0; i < poolIds.length; i++) {
            unlockStake(poolIds[i]);
        }
        emit BatchUnlockStake(msg.sender, poolIds.length);
    }


    function setGovernance(address newGovernance) external onlyGovernance {
        require(newGovernance != address(0), "Zero address");
        emit GovernanceTransferred(governance, newGovernance);
        governance = newGovernance;
    }
    function pause() external onlyGovernance {
        require(!paused, "Already paused");
        paused = true;
        emit Paused(msg.sender);
    }
    function unpause() external onlyGovernance {
        require(paused, "Not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    mapping(address => bool) public isAuthorizedLender;

    modifier onlyAuthorizedLender() {
        require(isAuthorizedLender[msg.sender], "Not authorized");
        _;
    }

    function setAuthorizedLender(address lender, bool authorized) external onlyGovernance {
        isAuthorizedLender[lender] = authorized;
    }
} 