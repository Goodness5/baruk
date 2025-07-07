// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/AMM.sol";
import "../src/BarukAMMFactory.sol";
import "../src/Router.sol";
import "../src/BarukYieldFarm.sol";
import "../src/BarukLending.sol";
import "../src/BarukLimitOrder.sol";
import "../src/interfaces/IAmm.sol";
import "../test/mocks/MockERC20.sol";

contract DeployBaruk is Script {
    function run() external {
        vm.startBroadcast();
        MockERC20 token0 = new MockERC20("Token0", "TK0");
        MockERC20 token1 = new MockERC20("Token1", "TK1");
        MockERC20 token2 = new MockERC20("Token2", "TK2");

        // Deploy AMM implementation
        BarukAMM ammImpl = new BarukAMM();
        // Deploy factory with implementation address
        BarukAMMFactory factory = new BarukAMMFactory(address(ammImpl));
        // Deploy router with factory address
        BarukRouter router = new BarukRouter(address(factory));

        // Use factory to create AMM pair
        address t0 = address(token0);
        address t1 = address(token1);
        if (t0 >= t1) {
            (t0, t1) = (t1, t0);
        }
        address pair = factory.createPair(t0, t1);
        BarukAMM amm = BarukAMM(pair);
        // Unpause AMM as deployer (current governance)
        amm.unpause();

        BarukYieldFarm farm = new BarukYieldFarm(address(amm));
        BarukLending lending = new BarukLending(address(farm));
        BarukLimitOrder limitOrder = new BarukLimitOrder(address(router));

        uint256 max = 1e30;
        token0.mint(msg.sender, max);
        token1.mint(msg.sender, max);
        token2.mint(msg.sender, max);
        token0.approve(address(router), max);
        token1.approve(address(router), max);
        router.addLiquidity(address(token0), address(token1), 100 ether, 100 ether);

        farm.addPool(address(amm), address(token0), 0.01 ether);
        farm.addPool(address(token0), address(token0), 1 ether);
        token0.mint(address(farm), 1000 ether);
        token1.mint(address(farm), 1000 ether);
        token0.mint(address(lending), 1000 ether);
        token1.mint(address(lending), 1000 ether);
        farm.setAuthorizedLender(address(lending), true);
        lending.setTokenDenom(address(amm), "LP_DENOM");
        lending.setTokenDenom(address(token0), "TK0_DENOM");
        // Now transfer governance to the final address
        address governance = 0xcc649e2a60ceDE9F7Ac182EAfa2af06655e54F60;
        router.setGovernance(governance);
        farm.setGovernance(governance);
        lending.setGovernance(governance);
        limitOrder.setGovernance(governance);
        amm.setGovernance(governance);
        console.log("Governance transferred to:", governance);
        console.log("Token0:", address(token0));
        console.log("Token1:", address(token1));
        console.log("Token2:", address(token2));
        console.log("AMM:", address(amm));
        console.log("Router:", address(router));
        console.log("YieldFarm:", address(farm));
        console.log("Lending:", address(lending));
        console.log("LimitOrder:", address(limitOrder));
        console.log("Oracle (Sei native precompile):", 0x0000000000000000000000000000000000001008);
        console.log("Factory:", address(factory));
        vm.stopBroadcast();
    }
} 