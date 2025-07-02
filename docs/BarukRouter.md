# BarukRouter

## Why We Built a Router (And Why It's Different)

Most DeFi protocols make you interact directly with their core contracts. That's fine for developers, but terrible for users. We built a router that actually makes sense.

## The Router Pattern: Why It Matters

```solidity
function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB
) external returns (address pair, uint256 liquidity)
```

**What's different here?** Most routers just forward calls to the AMM. Ours does more:
- Handles token transfers and approvals automatically
- Creates pairs if they don't exist
- Mints LP tokens directly to the user (not the router)

**Why not just call the AMM directly?** Because users shouldn't have to:
- Figure out which AMM contract to call
- Handle their own token approvals
- Deal with pair creation logic
- Worry about slippage and deadlines

## Flash Swaps: The Secret Weapon

```solidity
function flashSwap(
    address tokenA,
    address tokenB,
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
) external
```

**Flash swaps are where the magic happens.** You can:
- Borrow tokens without collateral
- Execute arbitrage strategies
- Build complex DeFi primitives
- All in one atomic transaction

**Why did we add this?** Because we want developers to build cool stuff on top of our protocol. Flash swaps enable the kind of composability that makes DeFi interesting.

## Deadline Protection: Why We Care

```solidity
require(block.timestamp <= deadline, "Transaction expired");
```

**MEV attacks are real.** Without deadline protection, your transaction can sit in the mempool and get sandwiched. We force users to think about timing, which protects them from:
- Front-running
- Sandwich attacks
- Stale transactions

## Governance: Why We Can Pause

```solidity
function pause() external onlyGovernance
```

**Sometimes you need to hit the emergency brake.** We can pause the router if:
- There's a critical bug
- The market is going crazy
- We need to upgrade something

**Why is this important?** Because DeFi is still experimental. Having an emergency pause is responsible, not centralized.

## The Integration Magic

Our router doesn't just work with our AMM—it's designed to work with:
- Yield farming (stake LP tokens immediately)
- Lending protocols (use LP tokens as collateral)
- Limit orders (execute via router)
- Any future DeFi primitive we build

**The router is the glue that holds everything together.** It's not just a convenience layer—it's the entry point to the entire Baruk ecosystem.

## Why This Matters

- **User Experience:** No one wants to interact with raw smart contracts
- **Security:** Centralized approval and deadline handling
- **Composability:** Flash swaps enable complex strategies
- **Flexibility:** Works with any DeFi protocol that follows standards

This router isn't just a wrapper—it's the foundation for building the next generation of DeFi applications.

## Purpose & Rationale
BarukRouter is the user-facing entry point for liquidity provision and swaps. It abstracts away the complexity of interacting directly with the AMM, ensuring safe, efficient, and user-friendly operations.

**Why this design?**
- **User Experience:** Simplifies liquidity and swap flows for end users.
- **Safety:** Handles token approvals, slippage, and deadline checks.
- **Composability:** Integrates with AMM, YieldFarm, and LimitOrder modules.

---

## Key Functions (with Code Examples)

### addLiquidity
```solidity
function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB
) external returns (address pair, uint256 liquidity)
```
**Usage Example:**
```solidity
// User adds liquidity to a new or existing pool
(address pair, uint256 liquidity) = router.addLiquidity(token0, token1, 100 ether, 200 ether);
```
**Logic:**
- Transfers tokens from user to router, then to AMM.
- Approves AMM to pull tokens, then calls AMM's addLiquidity.
- Emits `LiquidityAdded` event.

### removeLiquidity
```solidity
function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity
) external returns (uint256 amountA, uint256 amountB)
```
**Usage Example:**
```solidity
(uint256 amountA, uint256 amountB) = router.removeLiquidity(token0, token1, liquidity);
```
**Logic:**
- Calls AMM's removeLiquidity, returns tokens to user.
- Emits `LiquidityRemoved` event.

### swap
```solidity
function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    uint256 deadline,
    address recipient
) external returns (uint256 amountOut)
```
**Usage Example:**
```solidity
// User swaps 10 TK0 for TK1, expecting at least 9.8 TK1 out
uint256 out = router.swap(token0, token1, 10 ether, 9.8 ether, block.timestamp + 600, msg.sender);
```
**Logic:**
- Transfers tokens from user to AMM, calls AMM's publicSwap.
- Checks deadline and minAmountOut for slippage protection.
- Emits `Swap` event.

### Events
```solidity
event LiquidityAdded(address indexed provider, address indexed pair, uint256 amount0, uint256 amount1, uint256 liquidity);
event LiquidityRemoved(address indexed provider, address indexed pair, uint256 amount0, uint256 amount1, uint256 liquidity);
event Swap(address indexed user, address indexed pair, uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut);
```
**Example:**
> When a user adds liquidity, the `LiquidityAdded` event is emitted:
```solidity
emit LiquidityAdded(msg.sender, pair, amountA, amountB, liquidity);
```

---

## Security & Edge Cases
- **Reentrancy:** All state-changing functions are `nonReentrant`.
- **Slippage & Deadline:** Users specify min/max amounts and deadlines to avoid MEV and sandwich attacks.
- **Pair Existence:** Checks for valid pairs before operations.

---

## Full Example: Add Liquidity and Swap
```solidity
// User approves tokens
IERC20(token0).approve(address(router), 100 ether);
IERC20(token1).approve(address(router), 200 ether);

// Add liquidity
(address pair, uint256 liquidity) = router.addLiquidity(token0, token1, 100 ether, 200 ether);

// Swap
IERC20(token0).approve(address(router), 10 ether);
uint256 out = router.swap(token0, token1, 10 ether, 9.8 ether, block.timestamp + 600, msg.sender);
```

---

## Governance
- **Pause/Unpause:** Governance can pause all router operations in emergencies.
- **Governance Transfer:** Secure transfer of governance rights.

---

## Integration Points
- **AMM:** All liquidity and swap operations route through the AMM.
- **YieldFarm:** LP tokens can be staked after minting.
- **LimitOrder:** Limit orders are executed via the router.

---

## Events & Monitoring
- **LiquidityAdded, LiquidityRemoved, Swap, FlashSwap, Paused, Unpaused, GovernanceTransferred**
  - All major actions are logged for analytics and monitoring. 