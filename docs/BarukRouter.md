# BarukRouter

## The Router: Making DeFi Accessible

Most DeFi protocols are a pain to use. You need to know exactly which contract to call, handle approvals, manage slippage—it's a mess. The Router fixes this by providing a clean, simple interface for all AMM operations.

## Why We Built a Router

**DeFi should be simple.** Users shouldn't need to understand the difference between `addLiquidity` and `_addLiquidity`. They just want to:
- Add liquidity to a pool
- Swap tokens
- Remove liquidity

The Router handles all the complexity behind a clean interface.

## The Pair Factory Pattern

```solidity
mapping(address => mapping(address => address)) public pairs;
```

**We don't pre-deploy pairs.** Instead, we create them on-demand when someone adds liquidity. This saves gas and keeps the protocol lean.

**How it works:**
1. User calls `addLiquidity(tokenA, tokenB, amountA, amountB)`
2. Router checks if pair exists
3. If not, creates new AMM contract
4. Adds liquidity to the pair
5. Returns pair address and LP tokens

## Slippage Protection

```solidity
function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,  // <-- Slippage protection
    uint256 deadline,       // <-- Time protection
    address to
) public returns (uint256 amountOut)
```

**Two layers of protection:**
- **`minAmountOut`:** Ensures you get at least this much (prevents MEV sandwich attacks)
- **`deadline`:** Ensures your transaction doesn't sit in mempool forever

## Governance Controls

```solidity
address public governance;
bool public paused;

modifier onlyGovernance() { ... }
modifier whenNotPaused() { ... }
```

**We're not anarchists.** The protocol needs governance for:
- Emergency pauses (if something goes wrong)
- Parameter updates (fees, limits, etc.)
- Security upgrades

## Gas Optimization

```solidity
function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB
) public returns (address pair, uint256 liquidity)
```

**We batch operations to save gas:**
- Check/create pair
- Transfer tokens
- Add liquidity
- All in one transaction

## Error Handling

```solidity
require(pairs[tokenA][tokenB] != address(0), "Pair does not exist");
require(amountOut >= minAmountOut, "Insufficient output amount");
require(block.timestamp <= deadline, "Transaction expired");
```

**Clear, actionable errors.** Users need to know exactly what went wrong and how to fix it.

## Events for Transparency

```solidity
event PairCreated(address indexed tokenA, address indexed tokenB, address pair);
event Swap(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
```

**Everything is logged.** This helps with:
- Analytics and tracking
- Debugging issues
- Community transparency

The Router is the user-friendly face of our DeFi protocol. It handles the complexity so users can focus on what matters—their DeFi strategies.

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