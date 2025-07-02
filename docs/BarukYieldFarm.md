# BarukYieldFarm

## Yield Farming: Incentivizing Liquidity

Most DeFi protocols struggle with liquidity. Users provide liquidity, but there's no incentive to keep it there. We solve this with a yield farming system that rewards active participation.

## The Multi-Pool Architecture

```solidity
struct Pool {
    address lpToken;
    address rewardToken;
    uint256 rewardPerSecond;
    uint256 lastRewardTime;
    uint256 accRewardPerShare;
    uint256 totalStaked;
}
```

**Why multiple pools?** Different assets have different risk profiles and should earn different rewards. A stablecoin pool might earn 5% APY, while a volatile token pool might earn 20% APY.

## Reward Distribution: The Math

```solidity
uint256 multiplier = block.timestamp - pool.lastRewardTime;
uint256 reward = multiplier * pool.rewardPerSecond;
pool.accRewardPerShare += (reward * 1e12) / pool.totalStaked;
```

**How rewards work:**
1. Each pool has a `rewardPerSecond` rate
2. Rewards accumulate based on time and total staked
3. When you stake/unstake/claim, your rewards are calculated based on your share
4. Your share = `user.amount * pool.accRewardPerShare / 1e12`

## The Authorization System

```solidity
mapping(address => bool) public authorizedLenders;

function setAuthorizedLender(address lender, bool authorized) external onlyGovernance
```

**Why do we need this?** Our lending protocol needs to borrow from the farm's reserves. But we don't want just anyone calling `lendOut`. Only authorized contracts (like our lending protocol) can borrow.

**This is a security feature, not a limitation.** It prevents:
- Unauthorized borrowing
- Protocol manipulation
- Flash loan attacks

## Staking and Unstaking Logic

```solidity
function stake(uint256 poolId, uint256 amount) public {
    Pool storage pool = pools[poolId];
    UserInfo storage user = userInfo[poolId][msg.sender];
    
    updatePool(poolId);
    if (user.amount > 0) {
        uint256 pending = (user.amount * pool.accRewardPerShare / 1e12) - user.rewardDebt;
        if (pending > 0) {
            safeRewardTransfer(msg.sender, pending);
        }
    }
    // ... rest of staking logic
}
```

**Why update rewards before staking?** Because:
- Rewards are calculated based on your staked amount
- If you don't update first, you lose rewards for the time you were staked
- This ensures fair distribution

## Emergency Withdraw

```solidity
function emergencyWithdraw(uint256 poolId) public {
    Pool storage pool = pools[poolId];
    UserInfo storage user = userInfo[poolId][msg.sender];
    
    uint256 amount = user.amount;
    user.amount = 0;
    user.rewardDebt = 0;
    
    pool.lpToken.safeTransfer(msg.sender, amount);
    emit EmergencyWithdraw(msg.sender, poolId, amount);
}
```

**Why emergency withdraw?** Sometimes things go wrong. Users should always be able to get their tokens back, even if the reward system breaks.

## The Lending Integration

```solidity
function lendOut(address token, uint256 amount) external {
    require(authorizedLenders[msg.sender], "Not authorized");
    require(availableReserve[token] >= amount, "Insufficient reserve");
    
    availableReserve[token] -= amount;
    IERC20(token).safeTransfer(msg.sender, amount);
}
```

**This is where the magic happens.** The lending protocol can borrow from the farm's reserves to provide loans. The farm acts as a liquidity backstop for the entire ecosystem.

## Governance Controls

```solidity
function addPool(address lpToken, address rewardToken, uint256 rewardPerSecond) external onlyGovernance
function setRewardPerSecond(uint256 poolId, uint256 rewardPerSecond) external onlyGovernance
```

**Governance can:**
- Add new pools
- Adjust reward rates
- Authorize new lenders
- Emergency pause

**Why governance?** Because market conditions change. Sometimes you need to:
- Increase rewards to attract more liquidity
- Decrease rewards to control inflation
- Add new pools for new assets

## Security Considerations

```solidity
modifier nonReentrant() { ... }
require(amount > 0, "Cannot stake 0");
require(poolId < pools.length, "Pool does not exist");
```

**We protect against:**
- Reentrancy attacks
- Zero amount staking
- Invalid pool access
- Overflow/underflow

The yield farm isn't just about rewards—it's about building a sustainable liquidity ecosystem that supports the entire DeFi protocol.

## Purpose & Rationale
BarukYieldFarm incentivizes liquidity providers by allowing them to stake LP tokens and earn rewards. It is designed for flexibility, security, and composability with the rest of the Baruk protocol.

**Why this design?**
- **Incentivization:** Rewards LPs for providing liquidity, deepening protocol liquidity.
- **Flexibility:** Supports multiple pools and reward tokens.
- **Security:** Uses OpenZeppelin's ReentrancyGuard and explicit checks.

## Key Functions (with Code Examples)

### addPool
```solidity
function addPool(address stakedToken, address rewardToken, uint256 rewardRate) external
```
**Usage Example:**
```solidity
// Governance adds a new pool for LP tokens
farm.addPool(lpToken, rewardToken, 1 ether);
```
**Logic:**
- Only governance can add pools.
- Each pool has its own reward rate and tokens.

### stake
```solidity
function stake(uint256 poolId, uint256 amount) external
```
**Usage Example:**
```solidity
// User stakes 100 LP tokens in pool 0
farm.stake(0, 100 ether);
```
**Logic:**
- Transfers staked tokens from user to farm.
- Updates user and pool balances.
- Emits `Staked` event.

### claimReward
```solidity
function claimReward(uint256 poolId) external
```
**Usage Example:**
```solidity
// User claims rewards from pool 0
farm.claimReward(0);
```
**Math:**
- **Reward calculation:**
  \[
  reward = \frac{userStake \times rewardRate \times timeElapsed}{totalStaked}
  \]
**Why:**
- Ensures fair, time-weighted distribution of rewards.

### Events
```solidity
event PoolAdded(uint256 indexed poolId, address indexed stakedToken, address indexed rewardToken, uint256 rewardRate);
event Staked(address indexed user, uint256 amount);
event Unstaked(address indexed user, uint256 amount);
event RewardClaimed(address indexed user, uint256 amount);
```
**Example:**
> When a user stakes, the `Staked` event is emitted:
```solidity
emit Staked(msg.sender, amount);
```

## Security & Edge Cases
- **Reentrancy:** All state-changing functions are `nonReentrant`.
- **Zero Reward Rate:** Adding a pool with zero reward rate is disallowed.
- **Edge Cases:** Handles zero staking, early unstaking, and pool exhaustion.

## Full Example: Stake and Claim Reward
```solidity
// User approves LP tokens
IERC20(lpToken).approve(address(farm), 100 ether);

// Stake
farm.stake(0, 100 ether);

// Claim reward after some time
vm.roll(block.number + 100);
farm.claimReward(0);
```

## Governance
- **Add/Remove Pools:** Only governance can add or remove pools.
- **Set Reward Rates:** Governance can adjust reward rates for each pool.
- **Authorize Lenders:** Lending contracts must be authorized to call `lendOut`.

## Integration Points
- **AMM:** LP tokens are staked for rewards.
- **Lending:** Lenders can use staked assets as collateral.

## Events & Monitoring
- **PoolAdded, Staked, Unstaked, RewardClaimed, LenderAuthorized**
  - All major actions are logged for analytics and monitoring. 