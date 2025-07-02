# BarukYieldFarm

## Why Our Yield Farm is Different

Most yield farms are pretty basic—stake tokens, get rewards. We wanted something more sophisticated that actually incentivizes the right behavior.

## The Authorization System: Why We Added It

```solidity
function setAuthorizedLender(address lender, bool authorized) external onlyGovernance
```

**Most yield farms don't have this.** Why did we add it? Because we're building a lending protocol that needs to access farm reserves.

**The problem:** If anyone could call `lendOut`, they could drain the farm. We need controlled access.

**The solution:** Only authorized lending contracts can borrow from the farm. This creates a secure bridge between staking and lending.

## Reward Rate Validation: Why Zero is Bad

```solidity
require(rewardRate > 0, "Zero reward rate");
```

**This seems obvious, right?** But most protocols don't check this. Why do we care?

- A pool with zero rewards is useless
- It wastes gas and confuses users
- It could be used for attacks or manipulation

**We're being explicit about what we want:** active, incentivized pools that actually reward users.

## The Staking Logic: Why It's Simple But Smart

```solidity
function stake(uint256 poolId, uint256 amount) external
```

**We kept it simple on purpose.** No complex vesting schedules, no lock periods, no weird tokenomics.

**Why?** Because:
- Users should be able to enter and exit freely
- Complex systems create more attack vectors
- Simple systems are easier to audit and understand

**Sometimes the best innovation is knowing what NOT to add.**

## Reward Calculation: The Fair Way

```solidity
uint256 reward = (userStake * rewardRate * timeElapsed) / totalStaked;
```

**This is proportional and time-weighted.** Every user gets their fair share based on:
- How much they staked
- How long they staked
- The total pool size

**No favoritism, no manipulation, no weird edge cases.** Just fair rewards for honest participation.

## Integration with Lending: The Killer Feature

```solidity
function lendOut(address token, address to, uint256 amount) external
```

**This is where it gets interesting.** Our yield farm can lend tokens to our lending protocol. This creates a circular economy:

1. Users stake tokens in the farm
2. The farm lends tokens to the lending protocol
3. Users can borrow against their staked tokens
4. The lending protocol pays interest back to the farm
5. Farm users get better rewards

**It's like a DeFi perpetual motion machine.** Each component makes the others more valuable.

## Why This Matters for Hackathons

- **Innovation:** The authorization system enables secure cross-protocol integration
- **Simplicity:** Clean, auditable code without unnecessary complexity
- **Composability:** Works seamlessly with lending and AMM
- **Fairness:** Transparent reward distribution

This isn't just a yield farm—it's the engine that powers the entire Baruk ecosystem.

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