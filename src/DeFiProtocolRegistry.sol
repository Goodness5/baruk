// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDeFiProtocol.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DeFiProtocolRegistry
 * @dev Registry for managing multiple DeFi protocol integrations
 * Allows the AI to discover and interact with different protocols
 */
contract DeFiProtocolRegistry is Ownable, ReentrancyGuard {
    
    struct ProtocolInfo {
        string name;
        string version;
        address implementation;
        bool isActive;
        uint256 priority; // Higher priority protocols are preferred
        string category; // AMM, Lending, Yield Farming, etc.
        uint256 totalVolume;
        uint256 totalUsers;
        uint256 lastUpdated;
    }
    
    struct TokenPair {
        address tokenA;
        address tokenB;
        address protocol;
        uint256 liquidity;
        uint256 volume24h;
        uint256 fees24h;
    }
    
    // Protocol registry
    mapping(address => ProtocolInfo) public protocols;
    address[] public protocolAddresses;
    
    // Token pair registry
    mapping(address => mapping(address => address)) public tokenPairProtocols;
    TokenPair[] public tokenPairs;
    
    // AI trading parameters
    uint256 public slippageTolerance = 50; // 0.5%
    uint256 public maxGasPrice = 50 gwei;
    uint256 public maxSlippage = 500; // 5%
    uint256 public minLiquidity = 1000 ether;
    
    // Events
    event ProtocolRegistered(address indexed protocol, string name, string category);
    event ProtocolUpdated(address indexed protocol, bool isActive, uint256 priority);
    event ProtocolRemoved(address indexed protocol);
    event TokenPairAdded(address indexed tokenA, address indexed tokenB, address indexed protocol);
    event TradingParametersUpdated(uint256 slippageTolerance, uint256 maxGasPrice, uint256 maxSlippage);
    event AITradeExecuted(
        address indexed protocol,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 gasUsed
    );
    
    modifier onlyActiveProtocol(address protocol) {
        require(protocols[protocol].isActive, "Protocol not active");
        _;
    }
    
    modifier onlyValidTokens(address tokenA, address tokenB) {
        require(tokenA != address(0) && tokenB != address(0), "Invalid tokens");
        require(tokenA != tokenB, "Identical tokens");
        _;
    }
    
    constructor() Ownable(msg.sender) {}
    
    // Protocol Management
    
    function registerProtocol(
        address protocol,
        string memory name,
        string memory version,
        string memory category,
        uint256 priority
    ) external onlyOwner {
        require(protocol != address(0), "Invalid protocol address");
        require(bytes(name).length > 0, "Name cannot be empty");
        
        protocols[protocol] = ProtocolInfo({
            name: name,
            version: version,
            implementation: protocol,
            isActive: true,
            priority: priority,
            category: category,
            totalVolume: 0,
            totalUsers: 0,
            lastUpdated: block.timestamp
        });
        
        protocolAddresses.push(protocol);
        emit ProtocolRegistered(protocol, name, category);
    }
    
    function updateProtocol(
        address protocol,
        bool isActive,
        uint256 priority
    ) external onlyOwner {
        require(protocols[protocol].implementation != address(0), "Protocol not registered");
        
        protocols[protocol].isActive = isActive;
        protocols[protocol].priority = priority;
        protocols[protocol].lastUpdated = block.timestamp;
        
        emit ProtocolUpdated(protocol, isActive, priority);
    }
    
    function removeProtocol(address protocol) external onlyOwner {
        require(protocols[protocol].implementation != address(0), "Protocol not registered");
        
        delete protocols[protocol];
        
        // Remove from addresses array
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            if (protocolAddresses[i] == protocol) {
                protocolAddresses[i] = protocolAddresses[protocolAddresses.length - 1];
                protocolAddresses.pop();
                break;
            }
        }
        
        emit ProtocolRemoved(protocol);
    }
    
    // Token Pair Management
    
    function addTokenPair(
        address tokenA,
        address tokenB,
        address protocol
    ) external onlyOwner onlyValidTokens(tokenA, tokenB) onlyActiveProtocol(protocol) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        tokenPairProtocols[token0][token1] = protocol;
        
        tokenPairs.push(TokenPair({
            tokenA: token0,
            tokenB: token1,
            protocol: protocol,
            liquidity: 0,
            volume24h: 0,
            fees24h: 0
        }));
        
        emit TokenPairAdded(token0, token1, protocol);
    }
    
    function updateTokenPairStats(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 volume24h,
        uint256 fees24h
    ) external onlyOwner onlyValidTokens(tokenA, tokenB) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            if (tokenPairs[i].tokenA == token0 && tokenPairs[i].tokenB == token1) {
                tokenPairs[i].liquidity = liquidity;
                tokenPairs[i].volume24h = volume24h;
                tokenPairs[i].fees24h = fees24h;
                break;
            }
        }
    }
    
    // AI Trading Functions
    
    function findBestProtocol(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (address bestProtocol, uint256 bestAmountOut, uint256 bestPriceImpact) {
        require(tokenIn != tokenOut, "Identical tokens");
        
        bestAmountOut = 0;
        bestPriceImpact = type(uint256).max;
        
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            address protocol = protocolAddresses[i];
            if (!protocols[protocol].isActive) continue;
            
            try IDeFiProtocol(protocol).getQuote(tokenIn, tokenOut, amountIn) returns (uint256 amountOut, uint256 priceImpact) {
                if (amountOut > bestAmountOut && priceImpact < maxSlippage) {
                    bestAmountOut = amountOut;
                    bestPriceImpact = priceImpact;
                    bestProtocol = protocol;
                }
            } catch {
                // Protocol doesn't support this pair or has an error
                continue;
            }
        }
        
        require(bestProtocol != address(0), "No suitable protocol found");
    }
    
    function executeAISwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external onlyOwner nonReentrant returns (uint256 amountOut, uint256 gasUsed) {
        require(amountIn > 0, "Invalid amount");
        require(recipient != address(0), "Invalid recipient");
        
        uint256 gasStart = gasleft();
        
        // Find best protocol
        (address bestProtocol, uint256 expectedAmountOut, ) = this.findBestProtocol(tokenIn, tokenOut, amountIn);
        
        // Calculate minimum amount out with slippage tolerance
        uint256 minAmountOutWithSlippage = expectedAmountOut * (10000 - slippageTolerance) / 10000;
        minAmountOut = minAmountOut > minAmountOutWithSlippage ? minAmountOut : minAmountOutWithSlippage;
        
        // Execute swap
        amountOut = IDeFiProtocol(bestProtocol).swapExactTokensForTokens(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            recipient,
            block.timestamp + 300 // 5 minute deadline
        );
        
        gasUsed = gasStart - gasleft();
        
        // Update protocol stats
        protocols[bestProtocol].totalVolume += amountIn;
        protocols[bestProtocol].lastUpdated = block.timestamp;
        
        emit AITradeExecuted(bestProtocol, tokenIn, tokenOut, amountIn, amountOut, gasUsed);
    }
    
    function executeAIBatchSwap(
        address[] memory tokensIn,
        address[] memory tokensOut,
        uint256[] memory amountsIn,
        uint256[] memory minAmountsOut,
        address recipient
    ) external onlyOwner nonReentrant returns (uint256[] memory amountsOut) {
        require(
            tokensIn.length == tokensOut.length &&
            tokensIn.length == amountsIn.length &&
            tokensIn.length == minAmountsOut.length,
            "Array length mismatch"
        );
        
        amountsOut = new uint256[](tokensIn.length);
        
        for (uint256 i = 0; i < tokensIn.length; i++) {
            (amountsOut[i], ) = this.executeAISwap(
                tokensIn[i],
                tokensOut[i],
                amountsIn[i],
                minAmountsOut[i],
                recipient
            );
        }
    }
    
    // View Functions
    
    function getProtocolsByCategory(string memory category) external view returns (address[] memory) {
        uint256 count = 0;
        
        // Count matching protocols
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            if (protocols[protocolAddresses[i]].isActive && 
                keccak256(bytes(protocols[protocolAddresses[i]].category)) == keccak256(bytes(category))) {
                count++;
            }
        }
        
        // Create result array
        address[] memory result = new address[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            if (protocols[protocolAddresses[i]].isActive && 
                keccak256(bytes(protocols[protocolAddresses[i]].category)) == keccak256(bytes(category))) {
                result[index] = protocolAddresses[i];
                index++;
            }
        }
        
        return result;
    }
    
    function getTokenPairs() external view returns (TokenPair[] memory) {
        return tokenPairs;
    }
    
    function getProtocolInfo(address protocol) external view returns (ProtocolInfo memory) {
        return protocols[protocol];
    }
    
    function getAllProtocols() external view returns (address[] memory) {
        return protocolAddresses;
    }
    
    // Admin Functions
    
    function setTradingParameters(
        uint256 _slippageTolerance,
        uint256 _maxGasPrice,
        uint256 _maxSlippage,
        uint256 _minLiquidity
    ) external onlyOwner {
        slippageTolerance = _slippageTolerance;
        maxGasPrice = _maxGasPrice;
        maxSlippage = _maxSlippage;
        minLiquidity = _minLiquidity;
        
        emit TradingParametersUpdated(slippageTolerance, maxGasPrice, maxSlippage);
    }
    
    function emergencyPause() external onlyOwner {
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            protocols[protocolAddresses[i]].isActive = false;
        }
    }
    
    function emergencyResume() external onlyOwner {
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            protocols[protocolAddresses[i]].isActive = true;
        }
    }
} 