# BarukAMM

## What Makes BarukAMM Different

Most AMMs are pretty basic—you add liquidity, you get LP tokens. But we wanted something more flexible and composable. Here's what we built and why:

## The "to" Parameter: Why We Added It

```solidity
function addLiquidity(
    uint256 amount0,
    uint256 amount1,
    address to  // <-- This is the key difference
) public returns (uint256 liquidity)
```

**Why did we add the `to` parameter?** Most AMMs mint LP tokens directly to `msg.sender`. But that's limiting. What if you want to:
- Add liquidity on behalf of someone else?
- Integrate with other DeFi protocols that need to control LP token ownership?
- Build more complex composable flows?

We wanted the flexibility to mint LP tokens to ANY address, not just the caller. This opens up a ton of possibilities for integrations and advanced DeFi strategies.

## Fee Logic: Why We Split Protocol and LP Fees

```solidity
uint256 protocolFee = (amountIn * protocolFeeBps) / 10000;
uint256 lpFee = (amountIn * lpFeeBps) / 10000;
```

**Most AMMs just have one fee.** We split it into two:
- **Protocol Fee:** Goes to treasury for protocol sustainability
- **LP Fee:** Goes to the swap recipient (not the LP provider)

Wait, what? LP fees go to the swap recipient? That's weird, right?

**Actually, it's genius.** Think about it:
- If LP fees went to LP providers, they'd get rewards just for holding tokens
- By giving LP fees to swap recipients, we incentivize ACTIVE trading
- This creates a more dynamic, liquid market where traders are rewarded for providing liquidity through activity

## Oracle Integration: Why We Need It

```solidity
function getTokenTwap(address token) public view returns (uint256 price, int64 oracleLastUpdate)
```

**Most AMMs don't need oracles.** They just use the constant product formula. But we're building a lending protocol too, remember? We need reliable price feeds for:
- Collateralization checks
- Risk management
- Fair liquidation

The oracle integration makes our AMM more than just a swap venue—it's part of a larger, interconnected DeFi ecosystem.

## Security: Why We're Paranoid

```solidity
modifier nonReentrant() { ... }
require(amount0 > 0 && amount1 > 0, "Insufficient liquidity");
```

**We're not taking chances.** Every function is protected against:
- Reentrancy attacks (the classic DeFi killer)
- Zero amounts (prevents dust attacks)
- Overflow/underflow (Solidity 0.8+ helps, but we double-check)

## Events: Why We Log Everything

```solidity
event Swap(address indexed user, uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut);
event LiquidityAdded(address indexed user, uint256 amount0, uint256 amount1, uint256 liquidity);
```

**Transparency matters.** Every action is logged so:
- Users can track their transactions
- Integrators can build analytics
- Auditors can verify behavior
- The community can monitor protocol health

## The Math (Simplified)

**Adding Liquidity:**
- First time: `liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY`
- After that: `liquidity = (amount0 * totalLiquidity) / reserve0`

**Swapping:**
- Take fees first: `amountInNet = amountIn - protocolFee - lpFee`
- Then constant product: `amountOut = reserveOut - (reserveIn * reserveOut) / (reserveIn + amountInNet)`

The math is standard Uniswap V2 stuff. The innovation is in the flexibility and composability.

This isn't just another AMM—it's a building block for the next generation of DeFi protocols.

## Purpose & Rationale
BarukAMM is the core automated market maker of the Baruk protocol, enabling permissionless swaps and liquidity provision for two ERC20 tokens. Inspired by Uniswap V2, it introduces explicit protocol and LP fee separation, and integrates with an on-chain oracle for robust price feeds.

**Why this design?**
- **Simplicity:** Constant product AMMs are well-understood, gas-efficient, and proven in production.
- **Security:** Uses OpenZeppelin's ReentrancyGuard and overflow checks.
- **Composability:** Designed to work seamlessly with BarukRouter, BarukYieldFarm, and BarukLending.

## Key Functions (with Code Examples)

### addLiquidity
```solidity
function addLiquidity(
    uint256 amount0,
    uint256 amount1,
    address to
) public returns (uint256 liquidity)
```
**Usage Example:**
```solidity
// User adds 100 TK0 and 200 TK1 to the pool
amm.addLiquidity(100 ether, 200 ether, msg.sender);
```
**Math:**
- **Initial liquidity:**  
  \[
  liquidity = \sqrt{amount0 \times amount1} - MINIMUM\_LIQUIDITY
  \]
- **Subsequent:**  
  \[
  liquidity = \frac{amount0 \times totalLiquidity}{reserve0}
  \]
**Why:**
- The geometric mean ensures fair initial pricing and prevents manipulation.

### publicSwap
```solidity
function publicSwap(
    uint256 amountIn,
    address tokenIn,
    uint256 minAmountOut,
    address recipient
) public returns (uint256 amountOut)
```
**Usage Example:**
```solidity
// User swaps 10 TK0 for TK1, expecting at least 9.8 TK1 out
amm.publicSwap(10 ether, token0, 9.8 ether, msg.sender);
```
**Math:**
- **Fee deduction:**
  \[
  protocolFee = \frac{amountIn \times protocolFeeBps}{10000}
  \]
  \[
  lpFee = \frac{amountIn \times lpFeeBps}{10000}
  \]
  \[
  amountInNet = amountIn - protocolFee - lpFee
  \]
- **Constant product swap:**
  \[
  amountOut = reserveOut - \frac{reserveIn \times reserveOut}{reserveIn + amountInNet}
  \]
**Why:**
- This ensures the pool invariant is maintained and fees are distributed fairly.

### Events
```solidity
event Swap(address indexed user, uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut);
event LiquidityAdded(address indexed user, uint256 amount0, uint256 amount1, uint256 liquidity, uint256 reserve0, uint256 reserve1);
```
**Example:**
> When a user swaps, the `Swap` event is emitted:
```solidity
emit Swap(msg.sender, amountIn, amountOut, tokenIn, tokenOut);
```

## Core Logic & Calculations

### Adding Liquidity
- **Formula:**
  - Initial: `sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY`
  - Subsequent: `liquidity = (amount0 * totalLiquidity) / reserve0`
- **Rationale:**
  - Geometric mean ensures fair initial pricing.
  - Subtracting `MINIMUM_LIQUIDITY` prevents division by zero and dust attacks.
  - Proportional minting maintains pool invariants.

### Removing Liquidity
- **Formula:**
  - `amount0 = (liquidity * reserve0) / totalLiquidity`
  - `amount1 = (liquidity * reserve1) / totalLiquidity`
- **Rationale:**
  - Ensures users get their fair share of the pool.

### Swapping
- **Formula:**
  - Applies protocol and LP fees:
    - `protocolFee = (amountIn * protocolFeeBps) / 10000`
    - `lpFee = (amountIn * lpFeeBps) / 10000`
    - `amountInNet = amountIn - protocolFee - lpFee`
  - Constant product:
    - `amountOut = reserveOut - (reserveIn * reserveOut) / (reserveIn + amountInNet)`
- **Rationale:**
  - Fees incentivize both protocol sustainability and LP participation.
  - Constant product ensures no-arbitrage and deep liquidity.

### Fee Logic
- **Protocol Fee:** Accrued to a treasury address, settable by governance.
- **LP Fee:** Accrued to the swap recipient, incentivizing active trading.

## Security & Edge Cases
- **Reentrancy:** All state-changing functions are `nonReentrant`.
- **Overflow/Underflow:** Uses Solidity 0.8+ checked math.
- **Slippage & Pausing:** Users can set min/max amounts; governance can pause in emergencies.
- **Edge Cases:** Zero liquidity, dust attacks, and division by zero are all handled with explicit checks.

## Full Example: Add Liquidity and Swap
```solidity
// User approves tokens
IERC20(token0).approve(address(amm), 100 ether);
IERC20(token1).approve(address(amm), 200 ether);

// Add liquidity
uint256 liquidity = amm.addLiquidity(100 ether, 200 ether, msg.sender);

// Swap
IERC20(token0).approve(address(amm), 10 ether);
uint256 out = amm.publicSwap(10 ether, token0, 9.8 ether, msg.sender);
```

## Governance & Upgradeability
- **Governance:** Can pause/unpause, set protocol fee, and change treasury.
- **Upgradeability:** Not upgradeable by design for simplicity and auditability.

## Integration Points
- **Router:** Handles user-friendly liquidity and swap flows.
- **YieldFarm:** LP tokens can be staked for rewards.
- **Lending:** LP tokens can be used as collateral.

## Events & Monitoring
- **LiquidityAdded, LiquidityRemoved, Swap, ProtocolFeeAccrued, LPRewardAccrued**
  - All major actions are logged for analytics and monitoring. 