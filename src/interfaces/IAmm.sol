// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBarukAMM {
    // Events
    event Swap(
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        address tokenIn
    );
    event LiquidityAdded(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event LiquidityRemoved(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    // Add liquidity to the pool
    function addLiquidity(
        uint256 amount0,
        uint256 amount1
    ) external returns (uint256 liquidity);

    // Remove liquidity from the pool
    function removeLiquidity(
        uint256 liquidity
    ) external returns (uint256 amount0, uint256 amount1);

    // Swap tokens
    function swap(
        uint256 amountIn,
        address tokenIn,
        uint256 minAmountOut
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
}
