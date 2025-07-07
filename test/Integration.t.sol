// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Router.sol";
import "../src/AMM.sol";
import "../src/BarukYieldFarm.sol";
import "../src/BarukLending.sol";
import "../src/BarukLimitOrder.sol";
import "../src/BarukAMMFactory.sol";
import "./mocks/MockERC20.sol";
import "../src/interfaces/ISeiOracle.sol";

contract MockSeiOracle is ISeiOracle {
    function getOracleTwaps(uint64 lookbackSeconds) external view returns (OracleTwap[] memory) {
        OracleTwap[] memory twaps = new OracleTwap[](2);
        int64 ts = int64(uint64(block.timestamp));
        twaps[0] = OracleTwap("LP_DENOM", "1000000000000000000", ts);
        twaps[1] = OracleTwap("TK0_DENOM", "1000000000000000000", ts);
        return twaps;
    }

    function getExchangeRates() external view returns (DenomOracleExchangeRatePair[] memory) {
        return new DenomOracleExchangeRatePair[](0);
    }
}

contract IntegrationTest is Test {
    BarukRouter router;
    BarukAMM amm;
    BarukYieldFarm farm;
    BarukLending lending;
    BarukLimitOrder limitOrder;
    address user1;
    address user2;
    address governance;
    address token0;
    address token1;
    address token2;
    BarukAMMFactory factory;
    BarukAMM ammImpl;

    function setUp() public {
        user1 = address(0x1);
        user2 = address(0x2);
        governance = address(this);

        // Deploy tokens
        token0 = address(new MockERC20("Token0", "TK0"));
        token1 = address(new MockERC20("Token1", "TK1"));
        token2 = address(new MockERC20("Token2", "TK2"));

        // Mint MAX tokens and Ether to users and test contract
        uint256 max = 1e30;
        address[] memory allHolders = new address[](3);
        allHolders[0] = user1;
        allHolders[1] = user2;
        allHolders[2] = address(this);

        for (uint i = 0; i < allHolders.length; i++) {
            MockERC20(token0).mint(allHolders[i], max);
            MockERC20(token1).mint(allHolders[i], max);
            MockERC20(token2).mint(allHolders[i], max);
            // Give max Ether as well
            vm.deal(allHolders[i], max);
        }

        // Deploy AMM implementation and factory, then router
        ammImpl = new BarukAMM();
        factory = new BarukAMMFactory(address(ammImpl));
        router = new BarukRouter(address(factory));
        address t0 = token0;
        address t1 = token1;
        if (t0 >= t1) {
            (t0, t1) = (t1, t0);
        }
        // Deploy AMM via factory (minimal proxy)
        address pair = factory.createPair(t0, t1);
        amm = BarukAMM(pair);
        farm = new BarukYieldFarm(address(amm));
        lending = new BarukLending(address(farm));
        limitOrder = new BarukLimitOrder(address(router));

        // Fund farm and lending for rewards and borrowing
        MockERC20(token0).mint(address(farm), max);
        MockERC20(token1).mint(address(farm), max);
        MockERC20(token0).mint(address(lending), max);
        MockERC20(token1).mint(address(lending), max);

        // Set up mock oracle
        vm.etch(address(0x0000000000000000000000000000000000001008), address(new MockSeiOracle()).code);

        // Approve all contracts for tokens and LP tokens
        address[] memory contracts = new address[](5);
        contracts[0] = address(router);
        contracts[1] = address(amm);
        contracts[2] = address(farm);
        contracts[3] = address(lending);
        contracts[4] = address(limitOrder);

        for (uint i = 0; i < contracts.length; i++) {
            vm.startPrank(user1);
            MockERC20(token0).approve(contracts[i], max);
            MockERC20(token1).approve(contracts[i], max);
            MockERC20(token2).approve(contracts[i], max);
            vm.stopPrank();
            vm.startPrank(user2);
            MockERC20(token0).approve(contracts[i], max);
            MockERC20(token1).approve(contracts[i], max);
            MockERC20(token2).approve(contracts[i], max);
            vm.stopPrank();
        }

        // Approve LP tokens for farm and lending
        vm.startPrank(user1);
        ERC20(address(amm)).approve(address(farm), max);
        ERC20(address(amm)).approve(address(lending), max);
        vm.stopPrank();
        vm.startPrank(user2);
        ERC20(address(amm)).approve(address(farm), max);
        ERC20(address(amm)).approve(address(lending), max);
        vm.stopPrank();
    }

    function testEndToEndSwapAndFarm() public {
        // Step 1: User1 approves router for tokens before adding liquidity
        vm.startPrank(user1);
        MockERC20(token0).approve(address(router), type(uint256).max);
        MockERC20(token1).approve(address(router), type(uint256).max);
        vm.stopPrank();

        // Step 2: User1 adds liquidity via router
        uint256 addAmount = 100 ether;
        vm.prank(user1);
        (address pair, uint256 liquidity) = router.addLiquidity(token0, token1, addAmount, addAmount);

        // Step 3: Assert LP balance
        uint256 lpBalance = ERC20(pair).balanceOf(user1);
        assertGt(lpBalance, 0, "No LP tokens minted");

        // Step 4: User1 swaps a small amount via router
        vm.prank(user1);
        router.swap(token0, token1, 0.1 ether, 1, block.timestamp + 600, address(this));

        // Step 5: Governance adds farm pool
        vm.prank(governance);
        farm.addPool(pair, token0, 0.01 ether);

        // ✅ Step 6: User1 approves LP token (pair) for farm
        vm.prank(user1);
        ERC20(pair).approve(address(farm), type(uint256).max);

        // Step 7: User1 stakes LP in farm
        vm.prank(user1);
        farm.stake(0, 0.1 ether);

        // Step 8: Advance time to accrue rewards
        vm.roll(block.number + 100);

        // Step 9: User1 claims rewards
        vm.prank(user1);
        farm.claimReward(0);

        // Step 10: User1 unstakes
        vm.prank(user1);
        farm.unstake(0, 0.1 ether);

        // Step 11: Assert LP balance restored
        assertGt(ERC20(pair).balanceOf(user1), 0);
    }

    function testEndToEndLendAndBorrow() public {
        // Step 1: User1 adds initial liquidity and receives LP tokens
        uint256 addAmount = 100 ether;
        vm.prank(user1);
        amm.addLiquidity(addAmount, addAmount, user1);

        uint256 lpBalance = ERC20(address(amm)).balanceOf(user1);
        assertGt(lpBalance, 0, "No LP tokens minted");

        // Step 2: Governance sets up LP token pool for farming
        vm.prank(governance);
        farm.addPool(address(amm), token0, 0.01 ether); // poolId = 0

        // Step 3: User1 stakes a portion of LP tokens into the farm
        vm.prank(user1);
        farm.stake(0, 0.1 ether);

        // Step 4: User1 adds more liquidity to generate more LP tokens
        vm.prank(user1);
        amm.addLiquidity(addAmount, addAmount, user1);

        // Step 5: Governance sets up token0 pool to serve as lending reserve
        vm.prank(governance);
        farm.addPool(token0, token0, 1 ether); // poolId = 1

        // Step 6: Fund the farm with token0 and stake to populate availableReserve
        MockERC20(token0).mint(address(farm), 100 ether);

        vm.startPrank(user1);
        MockERC20(token0).approve(address(farm), 1 ether);
        farm.stake(1, 1 ether);
        vm.stopPrank();

        // Step 7: Governance sets oracle denoms for LP and token0
        vm.prank(governance);
        lending.setTokenDenom(address(amm), "LP_DENOM");
        vm.prank(governance);
        lending.setTokenDenom(token0, "TK0_DENOM");

        // ✅ Step 8: Authorize the lending contract to call `lendOut` on the farm
        vm.prank(governance);
        farm.setAuthorizedLender(address(lending), true);

        // Step 9: User1 deposits LP tokens and borrows token0
        uint256 lpBalanceForLending = ERC20(address(amm)).balanceOf(user1);
        vm.startPrank(user1);
        ERC20(address(amm)).approve(address(lending), lpBalanceForLending);
        lending.depositAndBorrow(address(amm), lpBalanceForLending, token0, 0.01 ether);
        vm.stopPrank();

        // Step 10: User1 repays the loan
        MockERC20(token0).mint(user1, 0.02 ether);
        vm.startPrank(user1);
        MockERC20(token0).approve(address(lending), 0.02 ether);
        lending.repay(token0, 0.01 ether);
        vm.stopPrank();

        // Final check: borrow balance should be 0
        assertEq(lending.borrows(user1, token0), 0);
    }

    function testEndToEndLimitOrder() public {
        uint256 addAmount = 100 ether;
        uint256 orderAmount = 0.1 ether;
        uint256 expectedMinOut = 0.09 ether;

        // Step 1: User1 approves router and adds liquidity to create pair
        vm.startPrank(user1);
        MockERC20(token0).approve(address(router), type(uint256).max);
        MockERC20(token1).approve(address(router), type(uint256).max);
        router.addLiquidity(token0, token1, addAmount, addAmount);
        vm.stopPrank();

        // Step 2: User1 approves limitOrder contract to pull orderAmount
        vm.prank(user1);
        MockERC20(token0).approve(address(limitOrder), orderAmount);

        // Step 3: User1 places a limit order
        vm.prank(user1);
        uint256 orderId = limitOrder.placeOrder(token0, token1, orderAmount, expectedMinOut);

        // Step 4: Allow limitOrder contract to use router for execution
        // This step is only needed if limitOrder internally calls router.swap(...)
        vm.prank(address(limitOrder));
        MockERC20(token0).approve(address(router), orderAmount);

        // Step 5: Governance executes the order
        vm.prank(governance);
        limitOrder.executeOrder(orderId, expectedMinOut);

        // Step 6: Check post-conditions
        uint256 received = MockERC20(token1).balanceOf(user1);
        assertGt(received, 0, "User should receive token1");

        uint256 protocolFee = limitOrder.protocolFeesAccrued(token1);
        assertGt(protocolFee, 0, "Protocol fee should be accrued in token1");
    }

    function testEndToEndGovernanceChange() public {
        // Transfer governance to user2
        vm.prank(governance);
        router.setGovernance(user2);

        // Old governance cannot pause
        vm.expectRevert();
        router.pause();

        // New governance can pause
        vm.prank(user2);
        router.pause();
        assertTrue(router.paused());

        // New governance can unpause
        vm.prank(user2);
        router.unpause();
        assertFalse(router.paused());
    }

    function testEndToEndOracleChange() public {
        // Governance sets new token denom
        vm.prank(governance);
        lending.setTokenDenom(token0, "TK0_DENOM");

        // Check that the mapping is set
        assertEq(keccak256(bytes(lending.tokenDenoms(token0))), keccak256(bytes("TK0_DENOM")));
    }

    function testEndToEndUserScenario() public {
        uint256 addAmount = 100 ether;

        // Step 1: User1 approves router and adds liquidity
        vm.startPrank(user1);
        MockERC20(token0).approve(address(router), type(uint256).max);
        MockERC20(token1).approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.prank(user1);
        (address pair, uint256 liquidity) = router.addLiquidity(token0, token1, addAmount, addAmount);

        // Step 2: Swap via router
        vm.prank(user1);
        router.swap(token0, token1, 0.1 ether, 1, block.timestamp + 600, address(this));

        // Step 3: Governance adds LP token to yield farm
        vm.prank(governance);
        farm.addPool(pair, token0, 0.01 ether); // poolId = 0

        // Step 4: User1 approves LP token to farm and stakes
        vm.startPrank(user1);
        ERC20(pair).approve(address(farm), type(uint256).max);
        farm.stake(0, 0.1 ether);
        vm.stopPrank();

        // Step 5: Governance sets token denoms
        vm.prank(governance);
        lending.setTokenDenom(address(amm), "LP_DENOM");
        vm.prank(governance);
        lending.setTokenDenom(token0, "TK0_DENOM");

        // --- NEW: Add pool for token0 and fund the farm with token0 ---
        // Add a pool for token0 if not already present (assume poolId = 1)
        vm.prank(governance);
        farm.addPool(token0, token0, 1 ether); // poolId = 1
        // Mint token0 to the farm
        MockERC20(token0).mint(address(farm), 100 ether);
        // Stake some token0 to populate availableReserve
        vm.startPrank(user1);
        MockERC20(token0).approve(address(farm), 10 ether);
        farm.stake(1, 10 ether);
        vm.stopPrank();
        // --- END NEW ---

        // Step 6: Authorize lender on farm (if `lendOut()` is protected)
        vm.prank(governance);
        farm.setAuthorizedLender(address(lending), true);

        // --- NEW: Use token0 as collateral for lending ---
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 0.01 ether;
        // Ensure user1 has enough token0 and has approved lending contract
        vm.startPrank(user1);
        MockERC20(token0).approve(address(lending), collateralAmount);
        emit log_named_uint("user1 token0 balance before depositAndBorrow", MockERC20(token0).balanceOf(user1));
        emit log_named_uint("lending contract token0 balance before depositAndBorrow", MockERC20(token0).balanceOf(address(lending)));
        lending.depositAndBorrow(token0, collateralAmount, token0, borrowAmount);
        emit log_named_uint("user1 token0 balance after depositAndBorrow", MockERC20(token0).balanceOf(user1));
        emit log_named_uint("lending contract token0 balance after depositAndBorrow", MockERC20(token0).balanceOf(address(lending)));
        vm.stopPrank();
        // --- END NEW ---

        // Step 7: Claim reward
        vm.roll(block.number + 100);
        vm.prank(user1);
        farm.claimReward(0);

        // Step 8: Unstake LP tokens
        vm.prank(user1);
        farm.unstake(0, 0.1 ether);

        // Step 9: Place and execute a limit order
        uint256 orderAmount = 0.01 ether;
        vm.prank(user1);
        MockERC20(token0).approve(address(limitOrder), orderAmount);

        vm.prank(user1);
        uint256 orderId = limitOrder.placeOrder(token0, token1, orderAmount, 0.009 ether);

        // Approve router from limitOrder (if needed for swap)
        vm.prank(address(limitOrder));
        MockERC20(token0).approve(address(router), orderAmount);

        // Execute order by governance
        vm.prank(governance);
        limitOrder.executeOrder(orderId, 0.009 ether);

        // Final assertions
        uint256 received = MockERC20(token1).balanceOf(user1);
        assertGt(received, 0, "User should receive token1");
        assertGt(limitOrder.protocolFeesAccrued(token1), 0, "Protocol fee should be accrued");
    }

    function testStakeBorrowRepayClaimFlow() public {
        uint256 addAmount = 100 ether;

        // Step 1: Add liquidity to get LP tokens
        vm.prank(user1);
        amm.addLiquidity(addAmount, addAmount, user1);

        uint256 lpBalance = ERC20(address(amm)).balanceOf(user1);
        assertGt(lpBalance, 0, "No LP tokens minted");

        // Step 2: Governance adds LP pool to farm
        vm.prank(governance);
        farm.addPool(address(amm), token0, 0.01 ether); // poolId = 0

        // Step 3: User1 stakes some LP tokens
        vm.prank(user1);
        farm.stake(0, 0.1 ether);

        // Step 4: Governance adds token0 pool to farm as borrow reserve
        vm.prank(governance);
        farm.addPool(token0, token0, 1 ether); // poolId = 1

        // Step 5: Fund the farm with token0 and stake to populate reserve
        MockERC20(token0).mint(address(farm), 100 ether);

        vm.startPrank(user1);
        MockERC20(token0).approve(address(farm), 1 ether);
        farm.stake(1, 1 ether); // Must stake in the correct poolId for token0
        vm.stopPrank();

        // ✅ Step 6: Authorize the lending contract to call lendOut
        vm.prank(governance);
        farm.setAuthorizedLender(address(lending), true);

        // Step 7: Set token denoms for oracle pricing
        vm.prank(governance);
        lending.setTokenDenom(address(amm), "LP_DENOM");
        vm.prank(governance);
        lending.setTokenDenom(token0, "TK0_DENOM");

        // Step 8: Deposit LP tokens and borrow token0
        vm.startPrank(user1);
        ERC20(address(amm)).approve(address(lending), 0.1 ether);
        lending.depositAndBorrow(address(amm), 0.1 ether, token0, 0.01 ether);
        vm.stopPrank();

        // Step 9: Repay loan
        MockERC20(token0).mint(user1, 0.02 ether);
        vm.startPrank(user1);
        MockERC20(token0).approve(address(lending), 0.02 ether);
        lending.repay(token0, 0.01 ether);
        vm.stopPrank();

        // Step 10: Claim reward
        vm.roll(block.number + 100);
        vm.prank(user1);
        farm.claimReward(0);

        // Final check
        assertEq(lending.borrows(user1, token0), 0);
    }

    function testOracleStalenessReverts() public {
        // Simulate staleness in oracle
        vm.warp(block.timestamp + 1000);
        vm.expectRevert();
        lending.getTokenTwap(address(amm));
    }

    function testPausingAffectsAllModules() public {
        // Pause router
        vm.prank(governance);
        router.pause();

        // Try to swap, expect revert
        vm.prank(user1);
        vm.expectRevert();
        router.swap(token0, token1, 100 ether, 1, block.timestamp + 600, address(this));
    }
}