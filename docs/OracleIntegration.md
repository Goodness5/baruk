# Oracle Integration

## Why Oracles Matter in DeFi

DeFi protocols need reliable price data. Without it, they can't:
- Calculate collateralization ratios
- Trigger liquidations
- Determine swap rates
- Manage risk

We integrate with the Sei oracle system to get manipulation-resistant price feeds.

## The TWAP Integration

```solidity
interface ISeiOracle {
    function getOracleTwaps(uint64 lookbackSeconds) external view returns (OracleTwap[] memory);
    function getExchangeRates() external view returns (DenomOracleExchangeRatePair[] memory);
}

struct OracleTwap {
    string denom;
    string price;
    int64 timestamp;
}
```

**Why TWAP (Time-Weighted Average Price)?** Because:
- Spot prices can be manipulated with flash loans
- TWAP smooths out price volatility
- It gives users time to react to price changes
- It's more resistant to market manipulation

## The Price Fetching Logic

```solidity
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

**How it works:**
1. Map token address to oracle denom
2. Fetch TWAP data from Sei oracle
3. Find the matching denom
4. Return price and timestamp

## Staleness Protection

```solidity
require(block.timestamp - oracleLastUpdate <= ORACLE_STALENESS_PERIOD, "Stale oracle");
```

**Why check for staleness?** Because:
- Old prices can be inaccurate
- Market conditions change rapidly
- Stale data can lead to bad decisions
- It protects against oracle failures

## The Denom Mapping System

```solidity
mapping(address => string) public tokenDenoms;

function setTokenDenom(address token, string memory denom) external onlyGovernance {
    tokenDenoms[token] = denom;
    emit TokenDenomSet(token, denom);
}
```

**Why map tokens to denoms?** Because:
- Different tokens have different oracle symbols
- Governance can add new tokens
- It's flexible and extensible
- It works with any oracle system

## Integration Points

**Lending Protocol:**
- Collateralization checks
- Liquidation triggers
- Risk management

**AMM:**
- Price discovery
- Fee calculations
- Market analysis

**Yield Farm:**
- Asset valuation
- Reward calculations
- Portfolio tracking

## Security Considerations

```solidity
modifier onlyGovernance() { ... }
require(bytes(denom).length > 0, "Token not configured");
require(block.timestamp - oracleLastUpdate <= ORACLE_STALENESS_PERIOD, "Stale oracle");
```

**We protect against:**
- Unauthorized denom changes
- Unconfigured tokens
- Stale price data
- Oracle manipulation

## Governance Controls

```solidity
function setTokenDenom(address token, string memory denom) external onlyGovernance
function setOracleStalenessPeriod(uint256 newPeriod) external onlyGovernance
```

**Governance can:**
- Add new token-oracle mappings
- Adjust staleness periods
- Update oracle addresses
- Emergency pause oracle usage

The oracle integration provides the reliable price data that makes our DeFi ecosystem secure and functional. 