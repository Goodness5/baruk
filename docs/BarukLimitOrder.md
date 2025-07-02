# BarukLimitOrder

## Why We Built Limit Orders (And Why They're Different)

Most DeFi protocols only support market orders—you get whatever price is available right now. We wanted to give users more control over their trading.

## The On-Chain Order Book: Why It Matters

```solidity
function placeOrder(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 orderId)
```

**Most DEXs don't have limit orders.** Why did we add them? Because:
- Market orders can get front-run
- Users want to set their own prices
- It enables more sophisticated trading strategies
- It reduces MEV and improves user experience

**The innovation:** Orders are stored on-chain, not in a centralized order book. This means:
- No counterparty risk
- Transparent execution
- No manipulation by centralized parties

## The Execution Logic: Why Governance Controls It

```solidity
function executeOrder(uint256 orderId, uint256 minOut) external
```

**Only governance can execute orders.** This might seem centralized, but it's actually a security feature:

- Prevents order manipulation
- Ensures fair execution
- Allows for circuit breakers during extreme volatility
- Protects against flash loan attacks

**The trade-off:** Slightly less decentralized for much better security and user protection.

## The Integration with Router: The Smart Move

```solidity
// Orders are executed via the router
router.swap(tokenIn, tokenOut, amountIn, minOut, deadline, recipient);
```

**We didn't build a separate execution engine.** Instead, we use our existing router. This means:
- Reuse of battle-tested swap logic
- Consistent fee structure
- Same slippage protection
- Unified event logging

**Why reinvent the wheel?** The router already handles all the complex swap logic. We just need to trigger it when conditions are right.

## The Protocol Fee: Why We Charge It

```solidity
uint256 protocolFee = (amountIn * protocolFeeBps) / 10000;
```

**Limit orders have costs:** gas for storage, execution, and monitoring. The protocol fee covers these costs and discourages spam orders.

**The fee is small but important.** It ensures the protocol can sustainably offer limit order functionality.

## Why This Matters for Hackathons

- **Innovation:** On-chain limit orders are rare in DeFi
- **User Experience:** Better control over trading execution
- **Security:** Governance-controlled execution prevents manipulation
- **Composability:** Works seamlessly with existing AMM and router

This isn't just a limit order system—it's a more sophisticated trading primitive that gives users real control over their DeFi experience.

## Purpose & Rationale
BarukLimitOrder enables users to place on-chain limit orders for swaps, providing more control over execution price and timing. It is designed for flexibility, security, and seamless integration with the Baruk protocol.

**Why this design?**
- **User Control:** Users can specify price and amount, and orders are executed only when conditions are met.
- **Composability:** Integrates with Router and AMM for execution.
- **Security:** Explicit checks and event logging for transparency.

---

## Key Functions (with Code Examples)

### placeOrder
```solidity
function placeOrder(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 orderId)
```
**Usage Example:**
```solidity
// User places a limit order to swap 10 TK0 for at least 9.9 TK1
uint256 orderId = limitOrder.placeOrder(token0, token1, 10 ether, 9.9 ether);
```
**Logic:**
- Stores order details on-chain.
- Emits `OrderPlaced` event.

### executeOrder
```solidity
function executeOrder(uint256 orderId, uint256 minOut) external
```
**Usage Example:**
```solidity
// Governance executes the order when conditions are met
limitOrder.executeOrder(orderId, 9.9 ether);
```
**Logic:**
- Checks order conditions, executes swap via router.
- Emits `OrderExecuted` event.

### Events
```solidity
event OrderPlaced(uint256 indexed orderId, address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut);
event OrderExecuted(uint256 indexed orderId, address indexed executor, uint256 amountOut);
event OrderCancelled(uint256 indexed orderId, address indexed user);
```
**Example:**
> When a user places an order, the `OrderPlaced` event is emitted:
```solidity
emit OrderPlaced(orderId, msg.sender, tokenIn, tokenOut, amountIn, minOut);
```

---

## Security & Edge Cases
- **Reentrancy:** All state-changing functions are `nonReentrant`.
- **Order Expiry:** Orders can have deadlines or be cancelled.
- **Edge Cases:** Handles partial fills, slippage, and protocol fee accrual.

---

## Full Example: Place and Execute Order
```solidity
// User approves tokens
IERC20(token0).approve(address(limitOrder), 10 ether);

// Place order
uint256 orderId = limitOrder.placeOrder(token0, token1, 10 ether, 9.9 ether);

// Approve router from limitOrder (if needed)
IERC20(token0).approve(address(router), 10 ether);

// Execute order
limitOrder.executeOrder(orderId, 9.9 ether);
```

---

## Governance
- **Set Protocol Fee:** Governance can adjust protocol fee rates.
- **Authorize Executors:** Only authorized actors can execute orders.

---

## Integration Points
- **Router:** Executes swaps for limit orders.
- **AMM:** Provides liquidity for order execution.

---

## Events & Monitoring
- **OrderPlaced, OrderExecuted, OrderCancelled, ProtocolFeeAccrued**
  - All major actions are logged for analytics and monitoring. 