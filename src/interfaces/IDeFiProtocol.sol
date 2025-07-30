// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IDeFiProtocol
 * @dev Generic interface for DeFi protocol integrations
 * This allows the AI to interact with different protocols in a standardized way
 */
interface IDeFiProtocol {
    
    // Protocol identification
    function protocolName() external view returns (string memory);
    function protocolVersion() external view returns (string memory);
    function isActive() external view returns (bool);
    
    // Token operations
    function getTokenBalance(address token, address user) external view returns (uint256);
    function getTokenAllowance(address token, address spender, address owner) external view returns (uint256);
    function approveToken(address token, address spender, uint256 amount) external returns (bool);
    
    // Swap operations
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);
    
    function swapTokensForExactTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 maxAmountIn,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountIn);
    
    // Liquidity operations
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 minLiquidity,
        address recipient,
        uint256 deadline
    ) external returns (uint256 liquidity, uint256 amountAUsed, uint256 amountBUsed);
    
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 minAmountA,
        uint256 minAmountB,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
    
    // Lending operations
    function deposit(address token, uint256 amount) external returns (uint256 shares);
    function withdraw(address token, uint256 shares) external returns (uint256 amount);
    function borrow(address token, uint256 amount) external returns (bool);
    function repay(address token, uint256 amount) external returns (bool);
    
    // Yield farming operations
    function stake(address token, uint256 amount) external returns (bool);
    function unstake(address token, uint256 amount) external returns (bool);
    function claimRewards(address token) external returns (uint256 rewards);
    
    // Price and quote operations
    function getPrice(address tokenIn, address tokenOut) external view returns (uint256 price);
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut, uint256 priceImpact);
    
    // Risk and safety operations
    function getSlippageTolerance() external view returns (uint256);
    function setSlippageTolerance(uint256 tolerance) external;
    function getMaxGasPrice() external view returns (uint256);
    function setMaxGasPrice(uint256 maxGasPrice) external;
    
    // Events
    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 priceImpact
    );
    
    event LiquidityAdded(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
    
    event LiquidityRemoved(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
    
    event LendingOperation(
        address indexed user,
        string operation,
        address indexed token,
        uint256 amount
    );
    
    event YieldFarmingOperation(
        address indexed user,
        string operation,
        address indexed token,
        uint256 amount
    );
} 