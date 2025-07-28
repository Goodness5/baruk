// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeFiProtocolRegistry.sol";
import "./interfaces/IDeFiProtocol.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AITradingStrategy
 * @dev AI trading strategy contract that can execute complex strategies across multiple DeFi protocols
 */
contract AITradingStrategy is Ownable, ReentrancyGuard {
    
    DeFiProtocolRegistry public immutable protocolRegistry;
    
    // Strategy configuration
    struct Strategy {
        string name;
        bool isActive;
        uint256 maxSlippage;
        uint256 maxGasPrice;
        uint256 minProfitThreshold;
        address[] targetTokens;
        string[] targetCategories;
        uint256 lastExecuted;
        uint256 totalExecutions;
        uint256 totalProfit;
    }
    
    // Trading parameters
    mapping(string => Strategy) public strategies;
    string[] public strategyNames;
    
    // Risk management
    uint256 public maxPositionSize = 1000 ether;
    uint256 public maxDailyLoss = 100 ether;
    uint256 public dailyLoss;
    uint256 public lastResetDay;
    
    // Performance tracking
    uint256 public totalTrades;
    uint256 public successfulTrades;
    uint256 public totalVolume;
    uint256 public totalFees;
    
    // Events
    event StrategyCreated(string indexed strategyName, uint256 maxSlippage, uint256 minProfitThreshold);
    event StrategyExecuted(
        string indexed strategyName,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 profit,
        uint256 gasUsed
    );
    event ArbitrageExecuted(
        address indexed protocolA,
        address indexed protocolB,
        address indexed token,
        uint256 amount,
        uint256 profit
    );
    event RiskLimitHit(string indexed limitType, uint256 value, uint256 limitValue);
    
    modifier onlyActiveStrategy(string memory strategyName) {
        require(strategies[strategyName].isActive, "Strategy not active");
        _;
    }
    
    modifier withinRiskLimits(uint256 amount) {
        require(amount <= maxPositionSize, "Position size too large");
        require(dailyLoss <= maxDailyLoss, "Daily loss limit exceeded");
        _;
    }
    
    constructor(address _protocolRegistry) Ownable(msg.sender) {
        protocolRegistry = DeFiProtocolRegistry(_protocolRegistry);
        lastResetDay = block.timestamp / 1 days;
    }
    
    // Strategy Management
    
    function createStrategy(
        string memory name,
        uint256 maxSlippage,
        uint256 maxGasPrice,
        uint256 minProfitThreshold,
        address[] memory targetTokens,
        string[] memory targetCategories
    ) external onlyOwner {
        require(bytes(name).length > 0, "Strategy name required");
        require(maxSlippage <= 1000, "Slippage too high"); // Max 10%
        require(minProfitThreshold > 0, "Invalid profit threshold");
        
        strategies[name] = Strategy({
            name: name,
            isActive: true,
            maxSlippage: maxSlippage,
            maxGasPrice: maxGasPrice,
            minProfitThreshold: minProfitThreshold,
            targetTokens: targetTokens,
            targetCategories: targetCategories,
            lastExecuted: 0,
            totalExecutions: 0,
            totalProfit: 0
        });
        
        strategyNames.push(name);
        emit StrategyCreated(name, maxSlippage, minProfitThreshold);
    }
    
    function updateStrategy(
        string memory name,
        bool isActive,
        uint256 maxSlippage,
        uint256 maxGasPrice,
        uint256 minProfitThreshold
    ) external onlyOwner {
        require(bytes(strategies[name].name).length > 0, "Strategy not found");
        
        strategies[name].isActive = isActive;
        strategies[name].maxSlippage = maxSlippage;
        strategies[name].maxGasPrice = maxGasPrice;
        strategies[name].minProfitThreshold = minProfitThreshold;
    }
    
    function addTargetTokens(string memory strategyName, address[] memory tokens) external onlyOwner {
        Strategy storage strategy = strategies[strategyName];
        require(bytes(strategy.name).length > 0, "Strategy not found");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            strategy.targetTokens.push(tokens[i]);
        }
    }
    
    function addTargetCategories(string memory strategyName, string[] memory categories) external onlyOwner {
        Strategy storage strategy = strategies[strategyName];
        require(bytes(strategy.name).length > 0, "Strategy not found");
        
        for (uint256 i = 0; i < categories.length; i++) {
            strategy.targetCategories.push(categories[i]);
        }
    }
    
    // Trading Functions
    
    function executeSimpleSwap(
        string memory strategyName,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external onlyOwner onlyActiveStrategy(strategyName) withinRiskLimits(amountIn) returns (uint256 amountOut) {
        Strategy storage strategy = strategies[strategyName];
        
        // Check if tokens are in target list
        bool tokenInAllowed = isTokenInTargets(strategy, tokenIn);
        bool tokenOutAllowed = isTokenInTargets(strategy, tokenOut);
        require(tokenInAllowed && tokenOutAllowed, "Tokens not in strategy targets");
        
        uint256 gasStart = gasleft();
        
        // Execute swap through registry
        (amountOut, ) = protocolRegistry.executeAISwap(tokenIn, tokenOut, amountIn, minAmountOut, address(this));
        
        uint256 gasUsed = gasStart - gasleft();
        
        // Calculate profit
        uint256 profit = amountOut > amountIn ? amountOut - amountIn : 0;
        
        // Update strategy stats
        strategy.lastExecuted = block.timestamp;
        strategy.totalExecutions++;
        strategy.totalProfit += profit;
        
        // Update global stats
        totalTrades++;
        if (profit > 0) successfulTrades++;
        totalVolume += amountIn;
        
        emit StrategyExecuted(strategyName, tokenIn, tokenOut, amountIn, amountOut, profit, gasUsed);
    }
    
    function executeArbitrage(
        string memory strategyName,
        address tokenA,
        address tokenB,
        uint256 amount
    ) external onlyOwner onlyActiveStrategy(strategyName) withinRiskLimits(amount) returns (uint256 profit) {
        Strategy storage strategy = strategies[strategyName];
        
        // Get all AMM protocols
        address[] memory ammProtocols = protocolRegistry.getProtocolsByCategory("AMM");
        require(ammProtocols.length >= 2, "Need at least 2 AMM protocols for arbitrage");
        
        uint256 bestBuyPrice = 0;
        uint256 bestSellPrice = 0;
        address bestBuyProtocol;
        address bestSellProtocol;
        
        // Find best buy and sell prices across protocols
        for (uint256 i = 0; i < ammProtocols.length; i++) {
            IDeFiProtocol protocol = IDeFiProtocol(ammProtocols[i]);
            
            try protocol.getPrice(tokenA, tokenB) returns (uint256 price) {
                if (price > bestBuyPrice) {
                    bestBuyPrice = price;
                    bestBuyProtocol = ammProtocols[i];
                }
            } catch {
                continue;
            }
        }
        
        for (uint256 i = 0; i < ammProtocols.length; i++) {
            if (ammProtocols[i] == bestBuyProtocol) continue;
            
            IDeFiProtocol protocol = IDeFiProtocol(ammProtocols[i]);
            
            try protocol.getPrice(tokenB, tokenA) returns (uint256 price) {
                if (price > bestSellPrice) {
                    bestSellPrice = price;
                    bestSellProtocol = ammProtocols[i];
                }
            } catch {
                continue;
            }
        }
        
        require(bestBuyProtocol != address(0) && bestSellProtocol != address(0), "No arbitrage opportunity");
        
        // Execute arbitrage if profitable
        if (bestSellPrice > bestBuyPrice) {
            // Buy on protocol A, sell on protocol B
            uint256 amountOut = executeSwapOnProtocol(bestBuyProtocol, tokenA, tokenB, amount);
            uint256 finalAmount = executeSwapOnProtocol(bestSellProtocol, tokenB, tokenA, amountOut);
            
            profit = finalAmount > amount ? finalAmount - amount : 0;
            
            if (profit > 0) {
                emit ArbitrageExecuted(bestBuyProtocol, bestSellProtocol, tokenA, amount, profit);
                
                // Update strategy stats
                strategy.lastExecuted = block.timestamp;
                strategy.totalExecutions++;
                strategy.totalProfit += profit;
                
                // Update global stats
                totalTrades++;
                successfulTrades++;
                totalVolume += amount;
            }
        }
    }
    
    function executeMultiHopSwap(
        string memory strategyName,
        address[] memory tokens,
        uint256 amountIn,
        uint256 minAmountOut
    ) external onlyOwner onlyActiveStrategy(strategyName) withinRiskLimits(amountIn) returns (uint256 amountOut) {
        require(tokens.length >= 3, "Need at least 3 tokens for multi-hop");
        
        Strategy storage strategy = strategies[strategyName];
        
        // Check if all tokens are in target list
        for (uint256 i = 0; i < tokens.length; i++) {
            require(isTokenInTargets(strategy, tokens[i]), "Token not in strategy targets");
        }
        
        uint256 currentAmount = amountIn;
        
        // Execute swaps through the token path
        for (uint256 i = 0; i < tokens.length - 1; i++) {
            (currentAmount, ) = protocolRegistry.executeAISwap(
                tokens[i],
                tokens[i + 1],
                currentAmount,
                0, // No minimum for intermediate swaps
                address(this)
            );
        }
        
        amountOut = currentAmount;
        require(amountOut >= minAmountOut, "Insufficient output amount");
        
        // Calculate profit
        uint256 profit = amountOut > amountIn ? amountOut - amountIn : 0;
        
        // Update strategy stats
        strategy.lastExecuted = block.timestamp;
        strategy.totalExecutions++;
        strategy.totalProfit += profit;
        
        // Update global stats
        totalTrades++;
        if (profit > 0) successfulTrades++;
        totalVolume += amountIn;
        
        emit StrategyExecuted(strategyName, tokens[0], tokens[tokens.length - 1], amountIn, amountOut, profit, 0);
    }
    
    // Helper Functions
    
    function isTokenInTargets(Strategy storage strategy, address token) internal view returns (bool) {
        for (uint256 i = 0; i < strategy.targetTokens.length; i++) {
            if (strategy.targetTokens[i] == token) {
                return true;
            }
        }
        return false;
    }
    
    function executeSwapOnProtocol(
        address protocol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        IDeFiProtocol defiProtocol = IDeFiProtocol(protocol);
        
        // Approve protocol to spend tokens
        IERC20(tokenIn).approve(protocol, amountIn);
        
        // Execute swap
        amountOut = defiProtocol.swapExactTokensForTokens(
            tokenIn,
            tokenOut,
            amountIn,
            0, // No minimum for arbitrage
            address(this),
            block.timestamp + 300
        );
    }
    
    // Risk Management
    
    function setRiskLimits(uint256 _maxPositionSize, uint256 _maxDailyLoss) external onlyOwner {
        maxPositionSize = _maxPositionSize;
        maxDailyLoss = _maxDailyLoss;
    }
    
    function resetDailyLoss() external onlyOwner {
        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay > lastResetDay) {
            dailyLoss = 0;
            lastResetDay = currentDay;
        }
    }
    
    // View Functions
    
    function getStrategy(string memory name) external view returns (Strategy memory) {
        return strategies[name];
    }
    
    function getAllStrategies() external view returns (string[] memory) {
        return strategyNames;
    }
    
    function getPerformanceStats() external view returns (
        uint256 _totalTrades,
        uint256 _successfulTrades,
        uint256 _totalVolume,
        uint256 _totalFees,
        uint256 _dailyLoss
    ) {
        return (totalTrades, successfulTrades, totalVolume, totalFees, dailyLoss);
    }
    
    function getSuccessRate() external view returns (uint256) {
        return totalTrades > 0 ? (successfulTrades * 10000) / totalTrades : 0;
    }
    
    // Emergency Functions
    
    function emergencyPause() external onlyOwner {
        for (uint256 i = 0; i < strategyNames.length; i++) {
            strategies[strategyNames[i]].isActive = false;
        }
    }
    
    function emergencyResume() external onlyOwner {
        for (uint256 i = 0; i < strategyNames.length; i++) {
            strategies[strategyNames[i]].isActive = true;
        }
    }
    
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
    
    function withdrawETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
} 