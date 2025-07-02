# BarukLending

## Lending: The Missing Piece

Most DeFi protocols are siloed. You have AMMs for swapping, yield farms for staking, but no way to borrow against your assets. We built a lending protocol that integrates seamlessly with our AMM and yield farm.

## The Oracle Integration

```solidity
mapping(address => string) public tokenDenoms;

function getTokenTwap(address token) public view returns (uint256 price, int64 oracleLastUpdate) {
    string memory denom = tokenDenoms[token];
    require(bytes(denom).length > 0, "Token not configured");
    
    ISeiOracle oracle = ISeiOracle(ORACLE_ADDRESS);
    OracleTwap[] memory twaps = oracle.getOracleTwaps(3600); // 1 hour lookback
    
    for (uint i = 0; i < twaps.length; i++) {
        if (keccak256(bytes(twaps[i].denom)) == keccak256(bytes(denom))) {
            return (uint256(keccak256(bytes(twaps[i].price))), twaps[i].timestamp);
        }
    }
    revert("Price not found");
}
```

**Why do we need oracles?** Because we need reliable price feeds for:
- Collateralization checks
- Liquidation triggers
- Risk management

**Why TWAP (Time-Weighted Average Price)?** Because spot prices can be manipulated. TWAP gives us a more stable, manipulation-resistant price.

## The Collateralization System

```solidity
function depositAndBorrow(
    address collateralToken,
    uint256 collateralAmount,
    address borrowToken,
    uint256 borrowAmount
) external {
    // Calculate collateral value in USD
    (uint256 collateralPrice,) = getTokenTwap(collateralToken);
    uint256 collateralValue = (collateralAmount * collateralPrice) / 1e18;
    
    // Calculate borrow value in USD
    (uint256 borrowPrice,) = getTokenTwap(borrowToken);
    uint256 borrowValue = (borrowAmount * borrowPrice) / 1e18;
    
    // Check collateralization ratio
    require(collateralValue >= borrowValue * COLLATERALIZATION_RATIO / 100, "Insufficient collateral");
    
    // ... rest of logic
}
```

**How collateralization works:**
1. User deposits collateral (e.g., LP tokens)
2. We get the USD value from oracle
3. User can borrow up to `collateralValue / collateralizationRatio`
4. If collateral value drops, position can be liquidated

## The Liquidation Mechanism

```solidity
function liquidate(address user, address collateralToken) external {
    uint256 collateralAmount = deposits[user][collateralToken];
    uint256 borrowAmount = borrows[user][collateralToken];
    
    (uint256 collateralPrice,) = getTokenTwap(collateralToken);
    uint256 collateralValue = (collateralAmount * collateralPrice) / 1e18;
    
    (uint256 borrowPrice,) = getTokenTwap(collateralToken);
    uint256 borrowValue = (borrowAmount * borrowPrice) / 1e18;
    
    require(collateralValue < borrowValue * LIQUIDATION_THRESHOLD / 100, "Not liquidatable");
    
    // Liquidate and give liquidator a bonus
    // ... liquidation logic
}
```

**Why liquidation?** To protect the protocol from bad debt. If collateral value drops too much, anyone can liquidate the position and get a bonus.

## The Farm Integration

```solidity
function borrow(address token, uint256 amount) external {
    require(borrows[msg.sender][token] + amount <= maxBorrow[msg.sender][token], "Exceeds max borrow");
    
    // Borrow from farm
    IBarukYieldFarm(farm).lendOut(token, amount);
    
    borrows[msg.sender][token] += amount;
    emit Borrow(msg.sender, token, amount);
}
```

**The farm acts as our liquidity backstop.** When users want to borrow, we pull tokens from the yield farm's reserves. This creates a circular economy where:
- Users stake in farm → farm has liquidity
- Users borrow from lending → lending pulls from farm
- Users pay interest → farm gets better rewards

## Interest Rate Model

```solidity
uint256 public constant BASE_RATE = 500; // 5% base rate
uint256 public constant UTILIZATION_RATE = 1000; // 10% per 100% utilization

function calculateInterestRate(uint256 utilization) public pure returns (uint256) {
    return BASE_RATE + (utilization * UTILIZATION_RATE / 10000);
}
```

**Simple but effective.** Interest rates increase with utilization to:
- Incentivize repayment when demand is high
- Discourage over-borrowing
- Maintain protocol solvency

## Security Features

```solidity
modifier nonReentrant() { ... }
require(block.timestamp - oracleLastUpdate <= ORACLE_STALENESS_PERIOD, "Stale oracle");
require(collateralValue >= borrowValue * COLLATERALIZATION_RATIO / 100, "Insufficient collateral");
```

**We protect against:**
- Reentrancy attacks
- Stale oracle data
- Insufficient collateralization
- Oracle manipulation

## Governance Controls

```solidity
function setTokenDenom(address token, string memory denom) external onlyGovernance
function setCollateralizationRatio(uint256 newRatio) external onlyGovernance
function setLiquidationThreshold(uint256 newThreshold) external onlyGovernance
```

**Governance can adjust:**
- Oracle denom mappings
- Collateralization ratios
- Liquidation thresholds
- Interest rate parameters

The lending protocol completes our DeFi ecosystem by allowing users to leverage their assets while maintaining security through proper collateralization and liquidation mechanisms. 