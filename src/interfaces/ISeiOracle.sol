// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISeiOracle {
    struct OracleExchangeRate {
        string exchangeRate;
        string lastUpdate;
        int64 lastUpdateTimestamp;
    }

    struct DenomOracleExchangeRatePair {
        string denom;
        OracleExchangeRate oracleExchangeRateVal;
    }

    struct OracleTwap {
        string denom;
        string twap;
        int64 lookbackSeconds;
    }

    function getExchangeRates() external view returns (DenomOracleExchangeRatePair[] memory);
    function getOracleTwaps(uint64 lookbackSeconds) external view returns (OracleTwap[] memory);
} 