// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Router.sol";
import "../src/AMM.sol";
import "./mocks/MockERC20.sol";

contract RouterTest is Test {
    BarukRouter router;
    address user1;
    address user2;
    address governance;
    address token0;
    address token1;
    address token2;

    function setUp() public {
        user1 = address(0x1);
        user2 = address(0x2);
        governance = address(this);
        token0 = address(new MockERC20("Token0", "TK0"));
        token1 = address(new MockERC20("Token1", "TK1"));
        token2 = address(new MockERC20("Token2", "TK2"));
        MockERC20(token0).mint(user1, 1_000_000 ether);
        MockERC20(token1).mint(user1, 1_000_000 ether);
        MockERC20(token2).mint(user1, 1_000_000 ether);
        MockERC20(token0).mint(user2, 1_000_000 ether);
        MockERC20(token1).mint(user2, 1_000_000 ether);
        MockERC20(token2).mint(user2, 1_000_000 ether);
        router = new BarukRouter();
        vm.prank(user1);
        MockERC20(token0).approve(address(router), type(uint256).max);
        vm.prank(user1);
        MockERC20(token1).approve(address(router), type(uint256).max);
        vm.prank(user1);
        MockERC20(token2).approve(address(router), type(uint256).max);
        vm.prank(user2);
        MockERC20(token0).approve(address(router), type(uint256).max);
        vm.prank(user2);
        MockERC20(token1).approve(address(router), type(uint256).max);
        vm.prank(user2);
        MockERC20(token2).approve(address(router), type(uint256).max);
    }

    // --- Pair Management ---
    function testCreatePair() public {}
    function testCreatePairDuplicate() public {}
    function testCreatePairZeroAddress() public {}
    function testCreatePairSameTokenReverts() public {
        vm.expectRevert();
        router.createPair(token0, token0);
    }
    function testCreateDuplicatePairReverts() public {
        router.createPair(token0, token1);
        vm.expectRevert();
        router.createPair(token0, token1);
    }

    // --- Routing Swaps ---
    function testRoutingSwapSingle() public {}
    function testRoutingSwapMultiHop() public {}
    function testRoutingSwapInvalidPair() public {}

    // --- Add/Remove Liquidity ---
    function testAddLiquidityViaRouter() public {}
    function testRemoveLiquidityViaRouter() public {}
    function testAddLiquidityZeroReverts() public {
        address pair = router.createPair(token0, token1);
        vm.prank(user1);
        vm.expectRevert();
        router.addLiquidity(token0, token1, 0, 1000 ether);
        vm.prank(user1);
        vm.expectRevert();
        router.addLiquidity(token0, token1, 1000 ether, 0);
    }

    // --- Batch Operations ---
    function testBatchAddLiquidityViaRouter() public {}
    function testBatchRemoveLiquidityViaRouter() public {}
    function testBatchSwapViaRouter() public {}

    // --- Events ---
    function testEventEmissions() public {}

    // --- Integration ---
    function testRouterAMMIntegration() public {}

    function testGetAllPairs() public {
        // Create three pairs
        address tokenA = address(new MockERC20("TokenA", "TKA"));
        address tokenB = address(new MockERC20("TokenB", "TKB"));
        address tokenC = address(new MockERC20("TokenC", "TKC"));
        address pair1 = router.createPair(tokenA, tokenB);
        address pair2 = router.createPair(tokenA, tokenC);
        address pair3 = router.createPair(tokenB, tokenC);
        // Fetch all pairs
        uint256 n = router.allPairsLength();
        console.log("Total pairs:", n);
        assertEq(n, 3);
        for (uint256 i = 0; i < n; i++) {
            address pair = router.allPairs(i);
            console.log("Pair", i, ":", pair);
            // Optionally, print token0/token1 for each pair
            address t0 = IBarukAMM(pair).token0();
            address t1 = IBarukAMM(pair).token1();
            console.log("  token0:", t0);
            console.log("  token1:", t1);
        }
    }

    function testSwapZeroAmountReverts() public {
        address pair = router.createPair(token0, token1);
        vm.prank(user1);
        router.addLiquidity(token0, token1, 1000 ether, 1000 ether);
        vm.prank(user1);
        vm.expectRevert();
        router.swap(token0, token1, 0, 1, block.timestamp + 600, address(this));
    }

    function testSwapPausedReverts() public {
        address pair = router.createPair(token0, token1);
        vm.prank(user1);
        router.addLiquidity(token0, token1, 1000 ether, 1000 ether);
        router.pause();
        vm.prank(user1);
        vm.expectRevert();
        router.swap(token0, token1, 100 ether, 1, block.timestamp + 600, address(this));
    }

    function testOnlyGovernanceCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        router.pause();
        router.pause(); // as governance
        assertTrue(router.paused());
    }
} 