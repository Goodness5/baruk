# Oracle Integration

## Why We Built Our Own Oracle System

Most DeFi protocols just use whatever oracle is available. We wanted something more sophisticated that actually protects users from manipulation.

## The TWAP Approach: Why We Chose It

```solidity
function getTokenTwap(address token) public view returns (uint256 price, int64 oracleLastUpdate)
```

**Most oracles give you spot prices.** We use TWAP (Time-Weighted Average Price) because:
- Spot prices can be manipulated with flash loans
- TWAP smooths out volatility and manipulation attempts
- It gives users time to react to price changes
- It's more resistant to market manipulation

**The trade-off:** TWAP is slightly delayed, but the security benefits far outweigh the latency cost.

## The Staleness Check: Why It's Critical

```solidity
require(block.timestamp - uint64(oracleLastUpdate) <= PRICE_STALENESS_THRESHOLD, "Stale price");
```

**Stale prices are dangerous.** If the oracle stops updating, we could:
- Accept overvalued collateral
- Liquidate positions unfairly
- Make bad lending decisions

**The solution:** We check that prices are recent (within 60 seconds). If they're stale, we revert the transaction.

**This protects users from oracle failures and manipulation.**

## The Denom Mapping: Why We Need It

```solidity
mapping(address => string) public tokenDenoms;
```

**Different tokens have different oracle symbols.** We need to map token addresses to their oracle denoms.

**Why is this important?** Because:
- Not all tokens are tracked by the oracle
- Different tokens might use different naming conventions
- We need to ensure we're getting the right price for the right token

**The mapping is governance-controlled** so we can add new tokens as needed.

## The Integration Points: Why They Matter

**Our oracle isn't just for pricing—it's for risk management:**

- **AMM:** Uses oracle for TWAP calculations and analytics
- **Lending:** Uses oracle for collateralization checks and liquidation
- **Future protocols:** Can use the same oracle for consistent pricing

**This creates a unified pricing system** across the entire Baruk ecosystem.

## Why This Matters for Hackathons

- **Innovation:** TWAP-based oracle system for manipulation resistance
- **Security:** Staleness checks prevent oracle failures
- **Composability:** Unified pricing across all protocols
- **Reliability:** Robust price feeds for risk management

This isn't just an oracle—it's a security-first pricing system that protects users from manipulation and ensures fair protocol operation.

---

## Key Functions (with Code Examples)

### getTokenTwap
```solidity
function getTokenTwap(address token) public view returns (uint256 price, int64 oracleLastUpdate)
```
**Usage Example:**
```solidity
// Fetch the TWAP for an LP token
(uint256 price, int64 lastUpdate) = lending.getTokenTwap(lpToken);
```
**Logic:**
- Looks up the denom for the token, fetches TWAP from oracle, checks staleness.
- Reverts if price is stale or denom is missing.

**Math:**
- **Staleness check:**
  \[
  \text{require}(block.timestamp - oracleLastUpdate \leq PRICE\_STALENESS\_THRESHOLD)
  \]

### Events
- (Oracle contracts typically do not emit events, but all price-dependent actions in AMM/Lending emit events for monitoring.)

---

## Security & Edge Cases
- **Staleness:** Operations revert if price data is stale.
- **Edge Cases:** Handles missing denoms, zero price, and oracle downtime.

---

## Full Example: Fetch and Use Oracle Price
```solidity
// Governance sets token denom
lending.setTokenDenom(lpToken, "LP_DENOM");

// Fetch price
(uint256 price, int64 lastUpdate) = lending.getTokenTwap(lpToken);

// Use price in collateral check
require(price > 0 && block.timestamp - uint64(lastUpdate) <= 60, "Stale or missing price");
```

---

## Governance
- **Set Denoms:** Governance can update token-denom mappings.
- **Update Oracle Address:** (If upgradeable) Governance can update the oracle source.

---

## Integration Points
- **AMM:** Uses oracle for TWAP and analytics.
- **Lending:** Uses oracle for collateral and borrow risk checks. 