// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBarukSwap {
    // Events
    event Swap(
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        address tokenIn
    );
    event FlashSwap(
        address indexed user,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 reserve0,
        uint256 reserve1
    );

    // Swap tokens
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) external returns (uint256 amountOut);

    // Swap with permit (EIP-2612)
    function swapWithPermit(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountOut);

    // Flash swap
    function flashSwap(
        address tokenA,
        address tokenB,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    // Pair management
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint256 index) external view returns (address pair);
    function allPairsLength() external view returns (uint256);

    // Liquidity management
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external returns (address pair, uint256 liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external returns (uint256 amountA, uint256 amountB);
}

interface IBarukFlashSwapCallback {
    function barukFlashSwapCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}