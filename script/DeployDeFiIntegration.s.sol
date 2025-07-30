// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/AMM.sol";
import "../src/BarukAMMFactory.sol";
import "../src/Router.sol";
import "../src/BarukYieldFarm.sol";
import "../src/BarukLending.sol";
import "../src/BarukLimitOrder.sol";
import "../src/DeFiProtocolRegistry.sol";
import "../src/adapters/BarukProtocolAdapter.sol";
import "../src/adapters/GenericProtocolAdapter.sol";
import "../src/AITradingStrategy.sol";
import "../src/interfaces/IDeFiProtocol.sol";
import "../test/mocks/MockERC20.sol";

contract DeployDeFiIntegration is Script {
    function run() external {
        vm.startBroadcast();
        
        console.log("=== Deploying Baruk Core Protocol ===");
        
        // Deploy mock tokens for testing
        MockERC20 token0 = new MockERC20("Token0", "TK0");
        MockERC20 token1 = new MockERC20("Token1", "TK1");
        MockERC20 token2 = new MockERC20("Token2", "TK2");
        MockERC20 token3 = new MockERC20("Token3", "TK3");
        
        // Deploy Baruk core contracts
        BarukAMM ammImpl = new BarukAMM();
        BarukAMMFactory factory = new BarukAMMFactory(address(ammImpl));
        BarukRouter router = new BarukRouter(address(factory));
        BarukYieldFarm farm = new BarukYieldFarm(address(ammImpl));
        BarukLending lending = new BarukLending(address(farm));
        BarukLimitOrder limitOrder = new BarukLimitOrder(address(router));
        
        console.log("Baruk Core deployed:");
        console.log("  AMM Implementation:", address(ammImpl));
        console.log("  Factory:", address(factory));
        console.log("  Router:", address(router));
        console.log("  Yield Farm:", address(farm));
        console.log("  Lending:", address(lending));
        console.log("  Limit Order:", address(limitOrder));
        
        console.log("\n=== Deploying DeFi Protocol Registry ===");
        
        // Deploy protocol registry
        DeFiProtocolRegistry registry = new DeFiProtocolRegistry();
        console.log("Protocol Registry:", address(registry));
        
        console.log("\n=== Deploying Protocol Adapters ===");
        
        // Deploy Baruk protocol adapter
        BarukProtocolAdapter barukAdapter = new BarukProtocolAdapter(
            address(router),
            address(farm),
            address(lending),
            address(limitOrder)
        );
        console.log("Baruk Protocol Adapter:", address(barukAdapter));
        
        // Deploy generic adapters for other protocols
        GenericProtocolAdapter astroportAdapter = new GenericProtocolAdapter(
            "Astroport",
            "1.0.0",
            "AMM"
        );
        console.log("Astroport Adapter:", address(astroportAdapter));
        
        GenericProtocolAdapter seiSwapAdapter = new GenericProtocolAdapter(
            "SeiSwap",
            "1.0.0",
            "AMM"
        );
        console.log("SeiSwap Adapter:", address(seiSwapAdapter));
        
        GenericProtocolAdapter seiLendAdapter = new GenericProtocolAdapter(
            "SeiLend",
            "1.0.0",
            "Lending"
        );
        console.log("SeiLend Adapter:", address(seiLendAdapter));
        
        console.log("\n=== Registering Protocols ===");
        
        // Register Baruk protocol
        registry.registerProtocol(
            address(barukAdapter),
            "Baruk",
            "1.0.0",
            "AMM",
            100 // High priority
        );
        
        // Register other protocols (placeholder addresses)
        registry.registerProtocol(
            address(astroportAdapter),
            "Astroport",
            "1.0.0",
            "AMM",
            80
        );
        
        registry.registerProtocol(
            address(seiSwapAdapter),
            "SeiSwap",
            "1.0.0",
            "AMM",
            70
        );
        
        registry.registerProtocol(
            address(seiLendAdapter),
            "SeiLend",
            "1.0.0",
            "Lending",
            90
        );
        
        console.log("Protocols registered successfully");
        
        console.log("\n=== Deploying AI Trading Strategy ===");
        
        // Deploy AI trading strategy
        AITradingStrategy aiStrategy = new AITradingStrategy(address(registry));
        console.log("AI Trading Strategy:", address(aiStrategy));
        
        console.log("\n=== Setting up Initial Configuration ===");
        
        // Create pairs and add liquidity
        address t0 = address(token0);
        address t1 = address(token1);
        if (t0 >= t1) {
            (t0, t1) = (t1, t0);
        }
        
        address pair = factory.createPair(t0, t1);
        BarukAMM amm = BarukAMM(pair);
        amm.unpause();
        
        // Mint tokens and add liquidity
        uint256 max = 1e30;
        token0.mint(msg.sender, max);
        token1.mint(msg.sender, max);
        token2.mint(msg.sender, max);
        token3.mint(msg.sender, max);
        
        token0.approve(address(router), max);
        token1.approve(address(router), max);
        token2.approve(address(router), max);
        token3.approve(address(router), max);
        
        // Add liquidity to pairs
        router.addLiquidity(address(token0), address(token1), 1000 ether, 1000 ether);
        router.addLiquidity(address(token0), address(token2), 1000 ether, 1000 ether);
        router.addLiquidity(address(token1), address(token2), 1000 ether, 1000 ether);
        
        // Set up yield farming
        farm.addPool(address(amm), address(token0), 0.01 ether);
        farm.addPool(address(token0), address(token0), 1 ether);
        
        // Mint tokens for protocols
        token0.mint(address(farm), 1000 ether);
        token1.mint(address(farm), 1000 ether);
        token0.mint(address(lending), 1000 ether);
        token1.mint(address(lending), 1000 ether);
        
        // Configure lending
        farm.setAuthorizedLender(address(lending), true);
        lending.setTokenDenom(address(amm), "LP_DENOM");
        lending.setTokenDenom(address(token0), "TK0_DENOM");
        
        // Set up token pairs in registry
        registry.addTokenPair(address(token0), address(token1), address(barukAdapter));
        registry.addTokenPair(address(token0), address(token2), address(barukAdapter));
        registry.addTokenPair(address(token1), address(token2), address(barukAdapter));
        
        // Create AI trading strategies
        address[] memory targetTokens = new address[](4);
        targetTokens[0] = address(token0);
        targetTokens[1] = address(token1);
        targetTokens[2] = address(token2);
        targetTokens[3] = address(token3);
        
        string[] memory targetCategories = new string[](2);
        targetCategories[0] = "AMM";
        targetCategories[1] = "Lending";
        
        aiStrategy.createStrategy(
            "Conservative",
            50, // 0.5% slippage
            30 gwei, // max gas price
            1 ether, // min profit threshold
            targetTokens,
            targetCategories
        );
        
        aiStrategy.createStrategy(
            "Aggressive",
            200, // 2% slippage
            50 gwei, // max gas price
            0.1 ether, // min profit threshold
            targetTokens,
            targetCategories
        );
        
        aiStrategy.createStrategy(
            "Arbitrage",
            100, // 1% slippage
            40 gwei, // max gas price
            0.5 ether, // min profit threshold
            targetTokens,
            targetCategories
        );
        
        console.log("AI Strategies created:");
        console.log("  - Conservative");
        console.log("  - Aggressive");
        console.log("  - Arbitrage");
        
        // Set risk limits
        aiStrategy.setRiskLimits(10000 ether, 1000 ether);
        
        // Transfer governance
        address governance = 0xcc649e2a60ceDE9F7Ac182EAfa2af06655e54F60;
        router.setGovernance(governance);
        farm.setGovernance(governance);
        lending.setGovernance(governance);
        limitOrder.setGovernance(governance);
        amm.setGovernance(governance);
        registry.transferOwnership(governance);
        barukAdapter.transferOwnership(governance);
        astroportAdapter.transferOwnership(governance);
        seiSwapAdapter.transferOwnership(governance);
        seiLendAdapter.transferOwnership(governance);
        aiStrategy.transferOwnership(governance);
        
        console.log("\n=== Deployment Summary ===");
        console.log("Governance transferred to:", governance);
        console.log("Token0:", address(token0));
        console.log("Token1:", address(token1));
        console.log("Token2:", address(token2));
        console.log("Token3:", address(token3));
        console.log("AMM:", address(amm));
        console.log("Router:", address(router));
        console.log("Yield Farm:", address(farm));
        console.log("Lending:", address(lending));
        console.log("Limit Order:", address(limitOrder));
        console.log("Protocol Registry:", address(registry));
        console.log("Baruk Adapter:", address(barukAdapter));
        console.log("AI Trading Strategy:", address(aiStrategy));
        console.log("Oracle (Sei native precompile):", 0x0000000000000000000000000000000000001008);
        console.log("Factory:", address(factory));
        
        console.log("\n=== Integration Ready ===");
        console.log("The AI can now trade across multiple DeFi protocols on SEI!");
        console.log("Use the AITradingStrategy contract to execute trading strategies.");
        console.log("Use the DeFiProtocolRegistry to discover and interact with protocols.");
        
        vm.stopBroadcast();
    }
} 