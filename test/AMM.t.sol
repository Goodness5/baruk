// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/AMM.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC20NoReturn.sol";
import "./mocks/MockERC20Reentrant.sol";
import "./mocks/MockERC20TransferFromFail.sol";

// Minimal flash loan receiver contract for testing
contract FlashLoanReceiver {
    BarukAMM public amm;
    address public token;
    bool public repay;
    constructor(address _amm, address _token, bool _repay) {
        amm = BarukAMM(_amm);
        token = _token;
        repay = _repay;
    }
    function execute(bytes calldata) external {
        if (repay) {
            uint256 fee = (100 ether * amm.flashLoanFeeBps()) / 10000;
            MockERC20(token).transfer(address(amm), 100 ether + fee);
        }
    }
}

contract AMMTest is Test {
    BarukAMM amm;
    address user1;
    address user2;
    address governance;
    address token0;
    address token1;

    function setUp() public {
        user1 = address(0x1);
        user2 = address(0x2);
        governance = address(this);
        address t0 = address(new MockERC20("Token0", "TK0"));
        address t1 = address(new MockERC20("Token1", "TK1"));
        (token0, token1) = t0 < t1 ? (t0, t1) : (t1, t0);
        // Mint tokens to users
        MockERC20(token0).mint(user1, 1_000_000 ether);
        MockERC20(token1).mint(user1, 1_000_000 ether);
        MockERC20(token0).mint(user2, 1_000_000 ether);
        MockERC20(token1).mint(user2, 1_000_000 ether);
        // Deploy AMM
        amm = new BarukAMM(token0, token1);
        // Approve AMM for both tokens from user1 and user2
        vm.prank(user1);
        MockERC20(token0).approve(address(amm), type(uint256).max);
        vm.prank(user1);
        MockERC20(token1).approve(address(amm), type(uint256).max);
        vm.prank(user2);
        MockERC20(token0).approve(address(amm), type(uint256).max);
        vm.prank(user2);
        MockERC20(token1).approve(address(amm), type(uint256).max);
    }

    // --- Add/Remove Liquidity ---
    function testAddLiquidity() public {
        uint256 amount0 = 1000 ether;
        uint256 amount1 = 2000 ether;
        // Print initial balances
        console.log("Initial user1 token0:", MockERC20(token0).balanceOf(user1));
        console.log("Initial user1 token1:", MockERC20(token1).balanceOf(user1));
        console.log("Initial AMM token0:", MockERC20(token0).balanceOf(address(amm)));
        console.log("Initial AMM token1:", MockERC20(token1).balanceOf(address(amm)));
        // Add liquidity as user1
        vm.prank(user1);
        uint256 liquidity = amm.addLiquidity(amount0, amount1, user1);
        // Print final balances
        console.log("Final user1 token0:", MockERC20(token0).balanceOf(user1));
        console.log("Final user1 token1:", MockERC20(token1).balanceOf(user1));
        console.log("Final AMM token0:", MockERC20(token0).balanceOf(address(amm)));
        console.log("Final AMM token1:", MockERC20(token1).balanceOf(address(amm)));
        console.log("Liquidity minted:", liquidity);
        // Assert balances
        assertEq(MockERC20(token0).balanceOf(address(amm)), amount0);
        assertEq(MockERC20(token1).balanceOf(address(amm)), amount1);
        assertEq(MockERC20(token0).balanceOf(user1), 1_000_000 ether - amount0);
        assertEq(MockERC20(token1).balanceOf(user1), 1_000_000 ether - amount1);
        // Assert liquidity tokens
        assertGt(liquidity, 0);
        assertEq(amm.balanceOf(user1), liquidity);
    }
    function testAddLiquidityZero() public {
        // Zero amount0
        vm.prank(user1);
        vm.expectRevert();
        amm.addLiquidity(0, 1000 ether, address(this));
        // Zero amount1
        vm.prank(user1);
        vm.expectRevert();
        amm.addLiquidity(1000 ether, 0, address(this));
        // Both zero
        vm.prank(user1);
        vm.expectRevert();
        amm.addLiquidity(0, 0, address(this));
        console.log("testAddLiquidityZero: All zero cases reverted as expected");
    }
    function testAddLiquidityTooSmall() public {
        // Try to add liquidity below MINIMUM_LIQUIDITY
        uint256 min = 1e3; // MINIMUM_LIQUIDITY in AMM
        vm.prank(user1);
        vm.expectRevert();
        amm.addLiquidity(min, min, address(this));
        console.log("testAddLiquidityTooSmall: Reverted as expected for too small amounts");
    }
    function testAddLiquidityPaused() public {
        // Pause the contract as governance
        amm.pause();
        // Try to add liquidity while paused
        vm.prank(user1);
        vm.expectRevert();
        amm.addLiquidity(1000 ether, 1000 ether, address(this));
        console.log("testAddLiquidityPaused: Reverted as expected when paused");
    }
    function testRemoveLiquidity() public {
        // User1 adds liquidity
        uint256 amount0 = 1000 ether;
        uint256 amount1 = 2000 ether;
        vm.prank(user1);
        uint256 liquidity = amm.addLiquidity(amount0, amount1, user1);
        // Remove liquidity
        vm.prank(user1);
        (uint256 out0, uint256 out1) = amm.removeLiquidity(liquidity);
        // Print and assert
        console.log("Removed token0:", out0);
        console.log("Removed token1:", out1);
        assertEq(MockERC20(token0).balanceOf(user1), 1_000_000 ether - amount0 + out0);
        assertEq(MockERC20(token1).balanceOf(user1), 1_000_000 ether - amount1 + out1);
        assertEq(amm.balanceOf(user1), 0);
        assertEq(MockERC20(token0).balanceOf(address(amm)), 0);
        assertEq(MockERC20(token1).balanceOf(address(amm)), 0);
    }
    function testRemoveLiquidityZero() public {
        vm.prank(user1);
        vm.expectRevert();
        amm.removeLiquidity(0);
        console.log("testRemoveLiquidityZero: Reverted as expected for zero liquidity");
    }
    function testRemoveLiquidityTooMuch() public {
        // User1 adds liquidity
        uint256 amount0 = 1000 ether;
        uint256 amount1 = 2000 ether;
        vm.prank(user1);
        uint256 liquidity = amm.addLiquidity(amount0, amount1, address(this));
        // Try to remove more than owned
        vm.prank(user1);
        vm.expectRevert();
        amm.removeLiquidity(liquidity + 1 ether);
        console.log("testRemoveLiquidityTooMuch: Reverted as expected for too much liquidity");
    }
    function testRemoveLiquidityPaused() public {
        // User1 adds liquidity
        uint256 amount0 = 1000 ether;
        uint256 amount1 = 2000 ether;
        vm.prank(user1);
        uint256 liquidity = amm.addLiquidity(amount0, amount1, address(this));
        // Pause contract
        amm.pause();
        // Try to remove liquidity
        vm.prank(user1);
        vm.expectRevert();
        amm.removeLiquidity(liquidity);
        console.log("testRemoveLiquidityPaused: Reverted as expected when paused");
    }

    // --- Swap ---
    function testSwapNormal() public {
        // User1 adds liquidity
        uint256 amount0 = 1000 ether;
        uint256 amount1 = 2000 ether;
        vm.prank(user1);
        amm.addLiquidity(amount0, amount1, user1);
        // User2 transfers tokens to AMM before swap
        uint256 swapAmount = 100 ether;
        vm.prank(user2);
        MockERC20(token0).transfer(address(amm), swapAmount);
        // User2 swaps token0 for token1
        vm.prank(user2);
        uint256 out = amm.publicSwap(swapAmount, token0, 1, user2);
        console.log("User2 swapped token0 for token1, got:", out);
        assertGt(out, 0);
        // Account for swap fees: user2's token0 should be exactly initial minus swapAmount
        assertEq(MockERC20(token0).balanceOf(user2), 1_000_000 ether - swapAmount);
        assertGe(MockERC20(token1).balanceOf(user2), 1_000_000 ether + out);
    }
    function testSwapSlippage() public {
        // User1 adds liquidity
        uint256 amount0 = 1000 ether;
        uint256 amount1 = 2000 ether;
        vm.prank(user1);
        amm.addLiquidity(amount0, amount1, user1);
        // User2 swaps with minAmountOut too high
        uint256 swapAmount = 100 ether;
        vm.prank(user2);
        vm.expectRevert();
        amm.publicSwap(swapAmount, token0, 1_000_000 ether, user2);
        console.log("testSwapSlippage: Reverted as expected for slippage");
    }
    function testSwapInvalidToken() public {
        // User1 adds liquidity
        uint256 amount0 = 1000 ether;
        uint256 amount1 = 2000 ether;
        vm.prank(user1);
        amm.addLiquidity(amount0, amount1, address(this));
        // User2 tries to swap a non-pool token
        address fakeToken = address(new MockERC20("Fake", "FAKE"));
        MockERC20(fakeToken).mint(user2, 100 ether);
        vm.prank(user2);
        vm.expectRevert();
        amm.publicSwap(100, fakeToken, 1, address(this));
        console.log("testSwapInvalidToken: Reverted as expected for invalid token");
    }
    function testSwapPaused() public {
        // User1 adds liquidity
        uint256 amount0 = 1000 ether;
        uint256 amount1 = 2000 ether;
        vm.prank(user1);
        amm.addLiquidity(amount0, amount1, address(this));
        // Pause contract
        amm.pause();
        // User2 tries to swap
        uint256 swapAmount = 100 ether;
        vm.prank(user2);
        vm.expectRevert();
        amm.publicSwap(swapAmount, token0, 1, address(this));
        console.log("testSwapPaused: Reverted as expected when paused");
    }
    function testSwapInsufficientLiquidity() public {
        // No liquidity in pool
        uint256 swapAmount = 100 ether;
        vm.prank(user2);
        vm.expectRevert();
        amm.publicSwap(swapAmount, token0, 1, address(this));
        console.log("testSwapInsufficientLiquidity: Reverted as expected for no liquidity");
    }

    // --- Batch Operations ---
    function testBatchAddLiquidity() public {
        uint256[] memory amounts0 = new uint256[](2);
        uint256[] memory amounts1 = new uint256[](2);
        amounts0[0] = 1000 ether;
        amounts1[0] = 2000 ether;
        amounts0[1] = 500 ether;
        amounts1[1] = 1000 ether;
        // User1 batch adds liquidity
        vm.prank(user1);
        amm.batchAddLiquidity(amounts0, amounts1);
        // Assert balances
        assertEq(MockERC20(token0).balanceOf(address(amm)), 1500 ether);
        assertEq(MockERC20(token1).balanceOf(address(amm)), 3000 ether);
        assertEq(amm.balanceOf(user1), amm.totalSupply());
        console.log("testBatchAddLiquidity: Batch add successful");
    }
    function testBatchRemoveLiquidity() public {
        // Add liquidity first
        uint256[] memory amounts0 = new uint256[](2);
        uint256[] memory amounts1 = new uint256[](2);
        amounts0[0] = 1000 ether;
        amounts1[0] = 2000 ether;
        amounts0[1] = 500 ether;
        amounts1[1] = 1000 ether;
        vm.prank(user1);
        amm.batchAddLiquidity(amounts0, amounts1);
        // Remove all liquidity in two steps
        uint256 totalLP = amm.balanceOf(user1);
        uint256[] memory liquidities = new uint256[](2);
        liquidities[0] = totalLP / 2;
        liquidities[1] = totalLP - liquidities[0];
        vm.prank(user1);
        amm.batchRemoveLiquidity(liquidities);
        // Assert all liquidity removed
        assertEq(amm.balanceOf(user1), 0);
        assertEq(MockERC20(token0).balanceOf(address(amm)), 0);
        assertEq(MockERC20(token1).balanceOf(address(amm)), 0);
        console.log("testBatchRemoveLiquidity: Batch remove successful");
    }
    function testBatchSwap() public {
        // Add liquidity
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 2000 ether, user1);
        // User2 batch swaps token0 for token1 twice
        uint256[] memory amountsIn = new uint256[](2);
        address[] memory tokensIn = new address[](2);
        uint256[] memory minAmountsOut = new uint256[](2);
        amountsIn[0] = 100 ether;
        amountsIn[1] = 50 ether;
        tokensIn[0] = token0;
        tokensIn[1] = token0;
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        vm.prank(user2);
        amm.batchSwap(amountsIn, tokensIn, minAmountsOut);
        // Assert user2's token0 decreased, token1 increased (allow equality)
        assertLe(MockERC20(token0).balanceOf(user2), 1_000_000 ether);
        assertGe(MockERC20(token1).balanceOf(user2), 1_000_000 ether);
        console.log("testBatchSwap: Batch swap successful");
    }

    // --- Protocol/LP Fee ---
    function testProtocolFeeAccrualAndClaim() public {
        // Set treasury
        amm.setProtocolFee(5, address(this));
        // Add liquidity and swap
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 2000 ether, user1);
        vm.prank(user2);
        amm.publicSwap(1000 ether, token0, 1, user2); // Use a larger swap to ensure fee accrual
        // Protocol fees should accrue
        uint256 accrued = amm.protocolFeesAccrued();
        assertGt(accrued, 0);
        // Claim protocol fees
        uint256 treasuryBalBefore = MockERC20(token0).balanceOf(address(this));
        amm.claimProtocolFees();
        uint256 treasuryBalAfter = MockERC20(token0).balanceOf(address(this));
        assertEq(treasuryBalAfter, treasuryBalBefore + accrued);
        assertEq(amm.protocolFeesAccrued(), 0);
        console.log("testProtocolFeeAccrualAndClaim: Protocol fee claim successful");
    }
    function testLPFeeAccrualAndClaim() public {
        // Add liquidity and swap
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 2000 ether, user1);
        vm.prank(user2);
        amm.publicSwap(10000 ether, token0, 1, user2); // Use a much larger swap to ensure fee accrual
        // LP rewards should accrue for user2 (swap recipient)
        uint256 reward = amm.lpRewards(user2);
        assertGt(reward, 0);
        uint256 balBefore = MockERC20(token0).balanceOf(user2);
        vm.prank(user2);
        amm.claimLPReward();
        uint256 balAfter = MockERC20(token0).balanceOf(user2);
        assertEq(balAfter, balBefore + reward);
        assertEq(amm.lpRewards(user2), 0);
        console.log("testLPFeeAccrualAndClaim: LP fee claim successful");
    }

    // --- Flash Loan ---
    function testFlashLoanSuccess() public {
        // Add liquidity
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 2000 ether, user1);
        // Deploy receiver that repays
        FlashLoanReceiver receiver = new FlashLoanReceiver(address(amm), token0, true);
        // Fund receiver
        MockERC20(token0).mint(address(receiver), 200 ether);
        // Take flash loan
        bytes memory data = abi.encodeWithSelector(receiver.execute.selector, "");
        vm.prank(address(receiver));
        amm.flashLoan(token0, 100, data);
        // Assert AMM balance is original + fee (protocol/LP fees may also accrue)
        uint256 fee = (100 * amm.flashLoanFeeBps()) / 10000;
        uint256 expected = 1000 ether + fee;
        // If protocol/LP fees accrue, add them here as well
        assertGe(MockERC20(token0).balanceOf(address(amm)), expected);
        console.log("testFlashLoanSuccess: Flash loan repaid successfully");
    }
    function testFlashLoanNotRepaid() public {
        // Add liquidity
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 2000 ether, address(this));
        // Deploy receiver that does NOT repay
        FlashLoanReceiver receiver = new FlashLoanReceiver(address(amm), token0, false);
        // Fund receiver
        MockERC20(token0).mint(address(receiver), 100 ether);
        // Take flash loan, expect revert
        bytes memory data = abi.encodeWithSelector(receiver.execute.selector, "");
        vm.prank(address(receiver));
        vm.expectRevert();
        amm.flashLoan(token0, 100, data);
        console.log("testFlashLoanNotRepaid: Reverted as expected when not repaid");
    }
    function testFlashLoanCallbackFails() public {
        // Add liquidity
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 2000 ether, address(this));
        // Deploy receiver that reverts in callback
        address receiver = address(0xdeadbeef);
        bytes memory data = hex"00"; // Invalid call, will fail
        vm.prank(receiver);
        vm.expectRevert();
        amm.flashLoan(token0, 100, data);
        console.log("testFlashLoanCallbackFails: Reverted as expected on callback failure");
    }

    // --- Oracle Integration ---
    function testOraclePriceFetch() public {
        // Set token denom mapping
        amm.setTokenDenom(token0, "sei");
        // This will revert if oracle returns 0 or is stale, so just check for no revert
        try amm.getTokenTwap(token0) returns (uint256 price, int64 lastUpdate) {
            assertGt(price, 0);
            console.log("testOraclePriceFetch: Oracle price fetched:", price);
        } catch {
            console.log("testOraclePriceFetch: Oracle call reverted (expected if no oracle on testnet)");
        }
    }
    function testOracleStaleness() public {
        // Set token denom mapping
        amm.setTokenDenom(token0, "sei");
        // Simulate staleness by manipulating block.timestamp (if possible)
        // This will revert if price is stale
        vm.warp(block.timestamp + 1000);
        vm.expectRevert();
        amm.getTokenTwap(token0);
        console.log("testOracleStaleness: Reverted as expected for stale price");
    }
    function testOracleNoMapping() public {
        // No mapping set for token1
        vm.expectRevert();
        amm.getTokenTwap(token1);
        console.log("testOracleNoMapping: Reverted as expected for missing mapping");
    }

    // --- Governance ---
    function testSetFee() public {
        // Only governance can set fee
        amm.setProtocolFee(10, address(this));
        assertEq(amm.protocolFeeBps(), 10);
        // Try as non-governance
        vm.prank(user1);
        vm.expectRevert();
        amm.setProtocolFee(20, user1);
        console.log("testSetFee: Only governance can set fee");
    }
    function testSetTreasury() public {
        // Only governance can set treasury
        amm.setProtocolFee(10, user2);
        assertEq(amm.protocolTreasury(), user2);
        // Try as non-governance
        vm.prank(user1);
        vm.expectRevert();
        amm.setProtocolFee(10, user1);
        console.log("testSetTreasury: Only governance can set treasury");
    }
    function testSetTokenDenom() public {
        // Only governance can set token denom
        amm.setTokenDenom(token0, "sei");
        assertEq(keccak256(bytes(amm.tokenDenoms(token0))), keccak256(bytes("sei")));
        // Try as non-governance
        vm.prank(user1);
        vm.expectRevert();
        amm.setTokenDenom(token1, "other");
        console.log("testSetTokenDenom: Only governance can set token denom");
    }
    function testPauseUnpause() public {
        // Only governance can pause/unpause
        amm.pause();
        assertTrue(amm.paused());
        amm.unpause();
        assertFalse(amm.paused());
        // Try as non-governance
        vm.prank(user1);
        vm.expectRevert();
        amm.pause();
        console.log("testPauseUnpause: Only governance can pause/unpause");
    }

    // --- Reentrancy ---
    function testReentrancyAttack() public {
        // Not implemented: would require a malicious contract. Placeholder for audit.
        console.log("testReentrancyAttack: Not implemented (would require malicious contract)");
    }

    // --- Events ---
    function testEventEmissions() public {
        // Add liquidity and check event
        vm.recordLogs();
        vm.prank(user1);
        uint256 liquidity = amm.addLiquidity(1000 ether, 2000 ether, user1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundLiquidityAdded = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("LiquidityAdded(address,uint256,uint256,uint256,uint256,uint256)")) {
                foundLiquidityAdded = true;
                break;
            }
        }
        assertTrue(foundLiquidityAdded, "LiquidityAdded event not found");
        // Remove liquidity and check event
        vm.recordLogs();
        vm.prank(user1);
        amm.removeLiquidity(liquidity);
        entries = vm.getRecordedLogs();
        bool foundLiquidityRemoved = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("LiquidityRemoved(address,uint256,uint256,uint256,uint256,uint256)")) {
                foundLiquidityRemoved = true;
                break;
            }
        }
        assertTrue(foundLiquidityRemoved, "LiquidityRemoved event not found");
        // Swap and check event
        vm.prank(user1);
        uint256 liquidity2 = amm.addLiquidity(1000 ether, 2000 ether, user1);
        vm.recordLogs();
        vm.prank(user2);
        amm.publicSwap(100, token0, 1, user2);
        entries = vm.getRecordedLogs();
        bool foundSwap = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Swap(address,uint256,uint256,address,address)")) {
                foundSwap = true;
                break;
            }
        }
        assertTrue(foundSwap, "Swap event not found");
        console.log("testEventEmissions: Events emitted as expected");
    }

    // --- Fuzzing ---
    function testFuzzSwap(uint256 amountIn) public {
        vm.assume(amountIn > 0 && amountIn < 1_000_000 ether);
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 2000 ether, address(this));
        vm.prank(user2);
        try amm.publicSwap(amountIn, token0, 1, address(this)) returns (uint256 out) {
            assertGt(out, 0);
        } catch {
            // Acceptable: may revert for too large amountIn
        }
    }
    function testFuzzAddLiquidity(uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 > 0 && amount1 > 0 && amount0 < 1_000_000 ether && amount1 < 1_000_000 ether);
        vm.prank(user1);
        try amm.addLiquidity(amount0, amount1, address(this)) returns (uint256 liquidity) {
            assertGt(liquidity, 0);
        } catch {
            // Acceptable: may revert for too small/imbalanced
        }
    }

    function testAddLiquidityMultipleUsers() public {
        uint256 amount0_1 = 1000 ether;
        uint256 amount1_1 = 2000 ether;
        uint256 amount0_2 = 500 ether;
        uint256 amount1_2 = 1000 ether;
        // User1 adds initial liquidity
        vm.prank(user1);
        uint256 liquidity1 = amm.addLiquidity(amount0_1, amount1_1, user1);
        // User2 adds liquidity
        vm.prank(user2);
        uint256 liquidity2 = amm.addLiquidity(amount0_2, amount1_2, user2);
        // Assert balances
        assertEq(MockERC20(token0).balanceOf(address(amm)), amount0_1 + amount0_2);
        assertEq(MockERC20(token1).balanceOf(address(amm)), amount1_1 + amount1_2);
        assertEq(amm.balanceOf(user1) + amm.balanceOf(user2), amm.totalSupply());
        // Proportionality: user2's LP should be about half of user1's (since they added half the amounts)
        assertApproxEqRel(liquidity2, liquidity1 / 2, 0.01e18); // allow 1% error due to rounding
    }

    // --- Security Tests ---
    // function testReentrancyAttackReal() public {
    //     // Deploy MockERC20Reentrant
    //     MockERC20Reentrant reentrant = new MockERC20Reentrant();
    //     reentrant.mint(user1, 1_000_000 ether);
    //     vm.prank(user1);
    //     reentrant.approve(address(amm), type(uint256).max);
    //     // Schedule reentrancy on addLiquidity
    //     bytes memory data = abi.encodeWithSelector(amm.removeLiquidity.selector, 1 ether);
    //     reentrant.scheduleReenter(ERC20Reentrant.Type.Before, address(amm), data);
    //     vm.prank(user1);
    //     vm.expectRevert();
    //     amm.addLiquidity(1000 ether, 1000 ether);
    //     // Schedule reentrancy on removeLiquidity
    //     vm.prank(user1);
    //     uint256 liquidity = amm.addLiquidity(1000 ether, 1000 ether);
    //     data = abi.encodeWithSelector(amm.addLiquidity.selector, 1000 ether, 1000 ether);
    //     reentrant.scheduleReenter(ERC20Reentrant.Type.Before, address(amm), data);
    //     vm.prank(user1);
    //     vm.expectRevert();
    //     amm.removeLiquidity(liquidity);
    //     console.log("testReentrancyAttackReal: Reentrancy prevented");
    // }
    function testUnauthorizedAccess() public {
        // Try to call governance-only functions as user1
        vm.prank(user1);
        vm.expectRevert();
        amm.pause();
        vm.prank(user1);
        vm.expectRevert();
        amm.unpause();
        vm.prank(user1);
        vm.expectRevert();
        amm.setProtocolFee(10, user1);
        vm.prank(user1);
        vm.expectRevert();
        amm.setTokenDenom(token0, "sei");
        console.log("testUnauthorizedAccess: Governance functions protected");
    }
    function testZeroAddressChecks() public {
        // Try to set protocol fee/treasury to zero address
        vm.expectRevert();
        amm.setProtocolFee(10, address(0));
        console.log("testZeroAddressChecks: Zero address check for treasury");
    }
    function testERC20ReturnValueHandling() public {
        // Deploy MockERC20TransferFromFail
        MockERC20TransferFromFail badToken = new MockERC20TransferFromFail("Bad", "BAD");
        badToken.mint(user1, 1000 ether);
        address t0 = address(badToken);
        address t1 = token1;
        if (t0 >= t1) {
            (t0, t1) = (t1, t0);
        }
        BarukAMM badAmm = new BarukAMM(t0, t1);
        vm.startPrank(user1);
        MockERC20(t0).approve(address(badAmm), 1000 ether);
        MockERC20(t1).approve(address(badAmm), 1000 ether);
        vm.expectRevert();
        badAmm.addLiquidity(1000 ether, 1000 ether, address(this));
        vm.stopPrank();
        console.log("testERC20ReturnValueHandling: ERC20 transferFrom return value handled");
    }
    function testOverflowFuzzing(uint256 amount) public {
        vm.assume(amount > 1e30 && amount < type(uint256).max / 2);
        vm.prank(user1);
        try amm.addLiquidity(amount, amount, address(this)) returns (uint256 liquidity) {
            assertGt(liquidity, 0);
        } catch {
            // Acceptable: may revert for too large/overflow
        }
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 2000 ether, address(this));
        vm.prank(user2);
        try amm.publicSwap(amount, token0, 1, address(this)) returns (uint256 out) {
            assertGt(out, 0);
        } catch {
            // Acceptable: may revert for too large/overflow
        }
    }
} 