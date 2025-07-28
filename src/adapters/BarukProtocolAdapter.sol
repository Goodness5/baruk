// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IDeFiProtocol.sol";
import "../Router.sol";
import "../AMM.sol";
import "../BarukYieldFarm.sol";
import "../BarukLending.sol";
import "../BarukLimitOrder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BarukProtocolAdapter
 * @dev Adapter for Baruk protocol to implement IDeFiProtocol interface
 * Allows AI to interact with Baruk's AMM, lending, and yield farming features
 */
contract BarukProtocolAdapter is IDeFiProtocol, Ownable, ReentrancyGuard {
    
    BarukRouter public immutable router;
    BarukYieldFarm public immutable yieldFarm;
    BarukLending public immutable lending;
    BarukLimitOrder public immutable limitOrder;
    
    // Trading parameters
    uint256 public slippageTolerance = 50; // 0.5%
    uint256 public maxGasPrice = 50 gwei;
    
    // Protocol info
    string public constant PROTOCOL_NAME = "Baruk";
    string public constant PROTOCOL_VERSION = "1.0.0";
    bool public isProtocolActive = true;
    
    // Events
    event BarukSwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 priceImpact
    );
    
    event BarukLiquidityOperation(
        address indexed user,
        string operation,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
    
    constructor(
        address _router,
        address _yieldFarm,
        address _lending,
        address _limitOrder
    ) Ownable(msg.sender) {
        router = BarukRouter(_router);
        yieldFarm = BarukYieldFarm(_yieldFarm);
        lending = BarukLending(_lending);
        limitOrder = BarukLimitOrder(_limitOrder);
    }
    
    // Protocol identification
    function protocolName() external pure override returns (string memory) {
        return PROTOCOL_NAME;
    }
    
    function protocolVersion() external pure override returns (string memory) {
        return PROTOCOL_VERSION;
    }
    
    function isActive() external view override returns (bool) {
        return isProtocolActive;
    }
    
    // Token operations
    function getTokenBalance(address token, address user) external view override returns (uint256) {
        return IERC20(token).balanceOf(user);
    }
    
    function getTokenAllowance(address token, address spender, address owner) external view override returns (uint256) {
        return IERC20(token).allowance(owner, spender);
    }
    
    function approveToken(address token, address spender, uint256 amount) external override returns (bool) {
        return IERC20(token).approve(spender, amount);
    }
    
    // Swap operations
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external override nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid amount");
        require(deadline >= block.timestamp, "Expired deadline");
        
        // Get quote first
        (uint256 expectedAmountOut, uint256 priceImpact) = this.getQuote(tokenIn, tokenOut, amountIn);
        require(expectedAmountOut >= minAmountOut, "Insufficient output amount");
        
        // Approve router to spend tokens
        IERC20(tokenIn).approve(address(router), amountIn);
        
        // Execute swap through router
        amountOut = router.swap(tokenIn, tokenOut, amountIn, minAmountOut, deadline, recipient);
        
        emit BarukSwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut, priceImpact);
        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut, priceImpact);
    }
    
    function swapTokensForExactTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 maxAmountIn,
        address recipient,
        uint256 deadline
    ) external override nonReentrant returns (uint256 amountIn) {
        require(amountOut > 0, "Invalid amount");
        require(deadline >= block.timestamp, "Expired deadline");
        
        // For exact output, we need to estimate input amount
        // This is a simplified implementation - in practice you'd need more complex logic
        (uint256 estimatedAmountIn, ) = this.getQuote(tokenOut, tokenIn, amountOut);
        require(estimatedAmountIn <= maxAmountIn, "Excessive input amount");
        
        // Approve router
        IERC20(tokenIn).approve(address(router), estimatedAmountIn);
        
        // Execute swap
        amountIn = router.swap(tokenIn, tokenOut, estimatedAmountIn, amountOut, deadline, recipient);
        
        emit BarukSwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut, 0);
        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut, 0);
    }
    
    // Liquidity operations
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 minLiquidity,
        address recipient,
        uint256 deadline
    ) external override nonReentrant returns (uint256 liquidity, uint256 amountAUsed, uint256 amountBUsed) {
        require(deadline >= block.timestamp, "Expired deadline");
        
        // Approve router
        IERC20(tokenA).approve(address(router), amountA);
        IERC20(tokenB).approve(address(router), amountB);
        
        // Add liquidity through router
        (address pair, uint256 liquidityMinted) = router.addLiquidity(tokenA, tokenB, amountA, amountB);
        
        require(liquidityMinted >= minLiquidity, "Insufficient liquidity minted");
        
        liquidity = liquidityMinted;
        amountAUsed = amountA;
        amountBUsed = amountB;
        
        emit BarukLiquidityOperation(msg.sender, "add", tokenA, tokenB, amountA, amountB, liquidity);
        emit LiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
    }
    
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 minAmountA,
        uint256 minAmountB,
        address recipient,
        uint256 deadline
    ) external override nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(deadline >= block.timestamp, "Expired deadline");
        
        // Get pair address
        address pair = router.getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");
        
        // Approve router to burn LP tokens
        IERC20(pair).approve(address(router), liquidity);
        
        // Remove liquidity through router
        (amountA, amountB) = router.removeLiquidity(tokenA, tokenB, liquidity);
        
        emit BarukLiquidityOperation(msg.sender, "remove", tokenA, tokenB, amountA, amountB, liquidity);
        emit LiquidityRemoved(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
    }
    
    // Lending operations
    function deposit(address token, uint256 amount) external override nonReentrant returns (uint256 shares) {
        require(amount > 0, "Invalid amount");
        
        IERC20(token).approve(address(lending), amount);
        lending.deposit(token, amount);
        shares = amount; // For simplicity, assume 1:1 shares
        
        emit LendingOperation(msg.sender, "deposit", token, amount);
    }
    
    function withdraw(address token, uint256 shares) external override nonReentrant returns (uint256 amount) {
        require(shares > 0, "Invalid shares");
        
        // For simplicity, assume 1:1 withdrawal
        amount = shares;
        
        emit LendingOperation(msg.sender, "withdraw", token, amount);
    }
    
    function borrow(address token, uint256 amount) external override nonReentrant returns (bool) {
        require(amount > 0, "Invalid amount");
        
        // For simplicity, use the token as collateral
        lending.borrow(token, amount, token);
        
        emit LendingOperation(msg.sender, "borrow", token, amount);
        return true;
    }
    
    function repay(address token, uint256 amount) external override nonReentrant returns (bool) {
        require(amount > 0, "Invalid amount");
        
        IERC20(token).approve(address(lending), amount);
        lending.repay(token, amount);
        
        emit LendingOperation(msg.sender, "repay", token, amount);
        return true;
    }
    
    // Yield farming operations
    function stake(address token, uint256 amount) external override nonReentrant returns (bool) {
        require(amount > 0, "Invalid amount");
        
        IERC20(token).approve(address(yieldFarm), amount);
        // For simplicity, use pool ID 0
        yieldFarm.stake(0, amount);
        
        emit YieldFarmingOperation(msg.sender, "stake", token, amount);
        return true;
    }
    
    function unstake(address token, uint256 amount) external override nonReentrant returns (bool) {
        require(amount > 0, "Invalid amount");
        
        // For simplicity, use pool ID 0
        yieldFarm.unstake(0, amount);
        
        emit YieldFarmingOperation(msg.sender, "unstake", token, amount);
        return true;
    }
    
    function claimRewards(address token) external override nonReentrant returns (uint256 rewards) {
        // For simplicity, use pool ID 0
        yieldFarm.claimReward(0);
        rewards = 0; // For simplicity, return 0 rewards
        
        emit YieldFarmingOperation(msg.sender, "claim", token, rewards);
        return rewards;
    }
    
    // Price and quote operations
    function getPrice(address tokenIn, address tokenOut) external view override returns (uint256 price) {
        // Get pair address
        address pair = router.getPair(tokenIn, tokenOut);
        if (pair == address(0)) return 0;
        
        // Get reserves from AMM
        BarukAMM amm = BarukAMM(pair);
        (uint256 reserve0, uint256 reserve1) = amm.getReserves();
        
        if (reserve0 == 0 || reserve1 == 0) return 0;
        
        // Calculate price based on reserves
        if (amm.token0() == tokenIn) {
            price = (reserve1 * 1e18) / reserve0;
        } else {
            price = (reserve0 * 1e18) / reserve1;
        }
    }
    
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256 amountOut, uint256 priceImpact) {
        require(amountIn > 0, "Invalid amount");
        
        // Get pair address
        address pair = router.getPair(tokenIn, tokenOut);
        if (pair == address(0)) return (0, type(uint256).max);
        
        // Get reserves
        BarukAMM amm = BarukAMM(pair);
        (uint256 reserve0, uint256 reserve1) = amm.getReserves();
        
        if (reserve0 == 0 || reserve1 == 0) return (0, type(uint256).max);
        
        // Calculate output amount using constant product formula
        uint256 fee = 30; // 0.3% fee
        uint256 amountInWithFee = amountIn * (10000 - fee) / 10000;
        
        if (amm.token0() == tokenIn) {
            amountOut = (amountInWithFee * reserve1) / (reserve0 + amountInWithFee);
        } else {
            amountOut = (amountInWithFee * reserve0) / (reserve1 + amountInWithFee);
        }
        
        // Calculate price impact
        uint256 priceBefore = amm.token0() == tokenIn ? 
            (reserve1 * 1e18) / reserve0 : 
            (reserve0 * 1e18) / reserve1;
        
        uint256 priceAfter = amm.token0() == tokenIn ?
            ((reserve1 - amountOut) * 1e18) / (reserve0 + amountIn) :
            ((reserve0 - amountOut) * 1e18) / (reserve1 + amountIn);
        
        priceImpact = priceBefore > priceAfter ? 
            ((priceBefore - priceAfter) * 10000) / priceBefore :
            ((priceAfter - priceBefore) * 10000) / priceBefore;
    }
    
    // Risk and safety operations
    function getSlippageTolerance() external view override returns (uint256) {
        return slippageTolerance;
    }
    
    function setSlippageTolerance(uint256 tolerance) external override onlyOwner {
        require(tolerance <= 1000, "Tolerance too high"); // Max 10%
        slippageTolerance = tolerance;
    }
    
    function getMaxGasPrice() external view override returns (uint256) {
        return maxGasPrice;
    }
    
    function setMaxGasPrice(uint256 maxPrice) external override onlyOwner {
        maxGasPrice = maxPrice;
    }
    
    // Admin functions
    function setProtocolActive(bool active) external onlyOwner {
        isProtocolActive = active;
    }
    
    function emergencyPause() external onlyOwner {
        isProtocolActive = false;
    }
    
    function emergencyResume() external onlyOwner {
        isProtocolActive = true;
    }
} 