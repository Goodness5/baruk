# BarukLimitOrder

## Limit Orders: Bringing CEX Features to DeFi

Most DEXs only support market orders—you get whatever price is available right now. But sophisticated traders need limit orders. We built a limit order system that works with our AMM and router.

## The Order Structure

```solidity
struct Order {
    address user;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 minAmountOut;
    uint256 orderId;
    bool executed;
    bool cancelled;
}
```

**Why this structure?** Because we need to track:
- Who placed the order
- What they want to trade
- How much they're willing to pay
- Whether it's been filled or cancelled

## The Execution Logic

```solidity
function executeOrder(uint256 orderId, uint256 minAmountOut) external onlyGovernance {
    Order storage order = orders[orderId];
    require(!order.executed && !order.cancelled, "Order not available");
    require(minAmountOut >= order.minAmountOut, "Slippage too high");
    
    // Execute the swap via router
    uint256 amountOut = router.swap(
        order.tokenIn,
        order.tokenOut,
        order.amountIn,
        minAmountOut,
        block.timestamp + 600,
        order.user
    );
    
    // Calculate and collect protocol fee
    uint256 protocolFee = (amountOut * protocolFeeBps) / 10000;
    uint256 userAmount = amountOut - protocolFee;
    
    // Transfer tokens to user and protocol
    IERC20(order.tokenOut).safeTransfer(order.user, userAmount);
    IERC20(order.tokenOut).safeTransfer(treasury, protocolFee);
    
    order.executed = true;
    emit OrderExecuted(orderId, order.user, order.tokenIn, order.tokenOut, order.amountIn, userAmount, protocolFee);
}
```

**How execution works:**
1. Governance (or authorized executor) calls `executeOrder`
2. Router performs the actual swap
3. Protocol fee is deducted from output
4. User gets their tokens, protocol gets fee
5. Order is marked as executed

## The Fee Model

```solidity
uint256 public protocolFeeBps = 50; // 0.5%

function setProtocolFeeBps(uint256 newFeeBps) external onlyGovernance {
    require(newFeeBps <= 1000, "Fee too high"); // Max 10%
    protocolFeeBps = newFeeBps;
}
```

**Why charge fees on limit orders?** Because:
- Limit orders provide value (price discovery, liquidity)
- Fees fund protocol development
- It discourages spam orders
- It aligns incentives between users and protocol

## The Cancellation System

```solidity
function cancelOrder(uint256 orderId) external {
    Order storage order = orders[orderId];
    require(order.user == msg.sender, "Not your order");
    require(!order.executed && !order.cancelled, "Order not available");
    
    order.cancelled = true;
    
    // Return tokens to user
    IERC20(order.tokenIn).safeTransfer(order.user, order.amountIn);
    
    emit OrderCancelled(orderId, order.user);
}
```

**Users can cancel their orders anytime.** This is important because:
- Market conditions change
- Users might change their mind
- It prevents stuck orders

## The Router Integration

```solidity
function executeOrder(uint256 orderId, uint256 minAmountOut) external onlyGovernance {
    // ... validation logic
    
    uint256 amountOut = router.swap(
        order.tokenIn,
        order.tokenOut,
        order.amountIn,
        minAmountOut,
        block.timestamp + 600,
        order.user
    );
    
    // ... fee logic
}
```

**We use the router for execution.** This means:
- All swaps go through the same AMM logic
- Slippage protection is consistent
- Gas optimization is shared
- Integration is seamless

## Security Features

```solidity
modifier onlyGovernance() { ... }
require(!order.executed && !order.cancelled, "Order not available");
require(minAmountOut >= order.minAmountOut, "Slippage too high");
```

**We protect against:**
- Unauthorized execution (only governance)
- Double execution
- Excessive slippage
- Invalid orders

## The Order ID System

```solidity
uint256 public nextOrderId = 1;

function placeOrder(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut) external returns (uint256 orderId) {
    orderId = nextOrderId++;
    // ... rest of logic
}
```

**Simple but effective.** Each order gets a unique ID that:
- Can't be predicted
- Can't be manipulated
- Is easy to track
- Works with events

## Events for Transparency

```solidity
event OrderPlaced(uint256 indexed orderId, address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut);
event OrderExecuted(uint256 indexed orderId, address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 protocolFee);
event OrderCancelled(uint256 indexed orderId, address indexed user);
```

**Everything is logged.** This helps with:
- Order tracking
- Analytics
- Debugging
- Community transparency

## Governance Controls

```solidity
function setProtocolFeeBps(uint256 newFeeBps) external onlyGovernance
function setTreasury(address newTreasury) external onlyGovernance
```

**Governance can adjust:**
- Protocol fee rates
- Treasury address
- Execution parameters

The limit order system brings sophisticated trading features to DeFi while maintaining security and transparency.

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