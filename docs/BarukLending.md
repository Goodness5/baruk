# BarukLending

## Why Our Lending Protocol is Different

Most lending protocols are isolated—you deposit, you borrow, that's it. We wanted something that works seamlessly with the rest of the DeFi ecosystem.

## The Oracle Integration: Why We Need It

```solidity
function getTokenTwap(address token) public view returns (uint256 price, int64 oracleLastUpdate)
```

**Most lending protocols use simple price feeds.** We use TWAP (Time-Weighted Average Price) from a sophisticated oracle system.

**Why TWAP?** Because:
- Spot prices can be manipulated
- TWAP smooths out price volatility
- It's more resistant to flash loan attacks
- It gives users time to react to price changes

**The oracle isn't just for pricing—it's for risk management.** We need reliable, manipulation-resistant prices to protect both lenders and borrowers.

## The Collateralization Logic: Why 150%?

```solidity
uint256 public constant COLLATERAL_FACTOR = 150; // 150%
```

**150% might seem arbitrary, but it's not.** Here's why:
- 100% would mean no buffer for price volatility
- 200% would be too conservative and limit borrowing
- 150% provides a good balance between safety and efficiency

**The math:** If your collateral drops 33%, you're still safe. That's a reasonable buffer for most market conditions.

## The Protocol Fee: Why We Charge It

```solidity
uint256 protocolFee = (amount * protocolFeeBps) / 10000;
```

**Most lending protocols don't have protocol fees.** Why do we?

- **Sustainability:** Protocol fees fund development and maintenance
- **Incentive alignment:** Fees discourage excessive borrowing
- **Risk management:** Higher fees on riskier assets

**The fee is small (0.05% default) but important.** It's not about profit—it's about building a sustainable protocol.

## The Health Factor: Why We Track It

```solidity
function healthFactor(address user, address collateral) public view returns (uint256)
```

**Health factors are crucial for risk management.** We calculate:
- Collateral value (from oracle)
- Total borrowed amount
- Required collateralization ratio

**If health factor < 1, the position is liquidatable.** This protects the protocol from undercollateralized loans.

## The Integration with Yield Farm: The Innovation

```solidity
function borrow(address asset, uint256 amount, address collateral) external
```

**Here's where it gets interesting.** Our lending protocol can borrow from our yield farm. This creates a unique dynamic:

1. Users stake tokens in the farm
2. The farm lends tokens to the lending protocol
3. Users can borrow against their staked tokens
4. The lending protocol pays interest back to the farm

**It's a circular economy that benefits everyone.** Stakers get better yields, borrowers get access to capital, and the protocol earns fees.

## Why This Matters for Hackathons

- **Innovation:** Oracle integration for robust risk management
- **Composability:** Works seamlessly with AMM and yield farm
- **Sustainability:** Protocol fees ensure long-term viability
- **Security:** Health factors and collateralization protect users

This isn't just a lending protocol—it's a risk-managed, composable DeFi primitive that works with the entire ecosystem.

## Purpose & Rationale
BarukLending enables overcollateralized borrowing and lending using LP tokens and supported assets. It is designed for risk management, composability, and robust security.

**Why this design?**
- **Risk Management:** Overcollateralization and oracle integration protect against undercollateralized loans.
- **Composability:** Works with YieldFarm and AMM for seamless DeFi flows.
- **Security:** Explicit checks, reentrancy protection, and protocol fee logic.

---

## Key Functions (with Code Examples)

### deposit
```solidity
function deposit(address asset, uint256 amount) external
```
**Usage Example:**
```solidity
// User deposits 100 LP tokens as collateral
lending.deposit(lpToken, 100 ether);
```
**Logic:**
- Transfers asset from user to lending contract.
- Updates user deposit mapping.
- Emits `Deposited` event.

### borrow
```solidity
function borrow(address asset, uint256 amount, address collateral) external
```
**Usage Example:**
```solidity
// User borrows 10 LP tokens using 100 as collateral
lending.borrow(lpToken, 10 ether, lpToken);
```
**Math:**
- **Collateralization check:**
  \[
  collateralValue \geq borrowValue \times \frac{COLLATERAL\_FACTOR}{100}
  \]
- **Why:**
  - Ensures protocol is always overcollateralized, protecting lenders.

### repay
```solidity
function repay(address asset, uint256 amount) external
```
**Usage Example:**
```solidity
// User repays 10 LP tokens
lending.repay(lpToken, 10 ether);
```
**Logic:**
- Transfers asset from user to lending contract.
- Deducts protocol fee, updates borrow mapping.
- Emits `Repaid` event.

### liquidate
```solidity
function liquidate(address user, address collateral) external
```
**Usage Example:**
```solidity
// Governance liquidates an unhealthy position
lending.liquidate(user1, lpToken);
```
**Logic:**
- Only governance can call.
- Checks health factor, then liquidates if undercollateralized.
- Emits `Liquidated` event.

### Events
```solidity
event Deposited(address indexed user, address indexed asset, uint256 amount);
event Borrowed(address indexed user, address indexed asset, uint256 amount, address collateral);
event Repaid(address indexed user, address indexed asset, uint256 amount);
event Liquidated(address indexed user, address indexed collateral, uint256 amount);
```
**Example:**
> When a user borrows, the `Borrowed` event is emitted:
```solidity
emit Borrowed(msg.sender, asset, amountAfterFee, collateral);
```

---

## Security & Edge Cases
- **Reentrancy:** All state-changing functions are `nonReentrant`.
- **Oracle Staleness:** Borrowing and liquidation require fresh price data.
- **Edge Cases:** Handles zero deposit/repay, over-repay, and undercollateralization.

---

## Full Example: Deposit, Borrow, Repay
```solidity
// User approves LP tokens
IERC20(lpToken).approve(address(lending), 100 ether);

// Deposit
lending.deposit(lpToken, 100 ether);

// Borrow
lending.borrow(lpToken, 10 ether, lpToken);

// Repay
IERC20(lpToken).approve(address(lending), 10 ether);
lending.repay(lpToken, 10 ether);
```

---

## Governance
- **Set Collateral Factors:** Governance can adjust risk parameters.
- **Set Protocol Fee/Treasury:** Governance can update fee rates and treasury address.
- **Set Token Denoms:** Governance can map tokens to oracle denoms.

---

## Integration Points
- **YieldFarm:** Uses farm reserves for lending and collateral management.
- **Oracle:** Fetches prices for risk checks.

---

## Events & Monitoring
- **Deposited, Borrowed, Repaid, Liquidated, ProtocolFeeAccrued, ProtocolFeeClaimed**
  - All major actions are logged for analytics and monitoring. 