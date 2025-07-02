// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBarukAMM {
    // Events
    event LiquidityAdded(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity,
        uint256 reserve0,
        uint256 reserve1
    );
    event LiquidityRemoved(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity,
        uint256 reserve0,
        uint256 reserve1
    );
    event Paused();
    event Unpaused();

    // Add liquidity to the pool
    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external returns (uint256 liquidity);

    // Remove liquidity from the pool
    function removeLiquidity(
        uint256 liquidity
    ) external returns (uint256 amount0, uint256 amount1);

    // Swap tokens (public interface for Router)
    function publicSwap(
        uint256 amountIn,
        address tokenIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    // Get amount out for a given input
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    // Get current reserves
    function getReserves()
        external
        view
        returns (uint256 reserve0, uint256 reserve1);

    // Get token addresses
    function token0() external view returns (address);
    function token1() external view returns (address);

    // Get price oracle data
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function lastUpdateTimestamp() external view returns (uint32);

    // Governance functions
    function pause() external;
    function unpause() external;
}