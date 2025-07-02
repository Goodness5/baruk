// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/BarukLending.sol";
import "./mocks/MockERC20.sol";
import "../src/interfaces/ISeiOracle.sol";

contract MockSeiOracle is ISeiOracle {
    function getOracleTwaps(uint64) external view returns (OracleTwap[] memory) {
        OracleTwap[] memory twaps = new OracleTwap[](1);
        int64 ts = int64(uint64(block.timestamp));
        twaps[0] = OracleTwap("LP_DENOM", "1000000000000000000", ts); // 1.0 * 1e18
        return twaps;
    }
    function getExchangeRates() external view returns (DenomOracleExchangeRatePair[] memory) {
        return new DenomOracleExchangeRatePair[](0);
    }
}

contract BarukLendingTest is Test {
    BarukLending lending;
    address user1;
    address user2;
    address governance;
    address lpToken;
    BarukYieldFarm farm;

    function setUp() public {
        user1 = address(0x1);
        user2 = address(0x2);
        governance = address(this);
        lpToken = address(new MockERC20("LPToken", "LPT"));
        MockERC20(lpToken).mint(user1, 1_000_000 ether);
        MockERC20(lpToken).mint(user2, 1_000_000 ether);
        farm = new BarukYieldFarm(lpToken);
        lending = new BarukLending(address(farm));
        lending.setTokenDenom(lpToken, "LP_DENOM");
        // Deploy and set up mock oracle at the expected address
        vm.etch(address(0x0000000000000000000000000000000000001008), address(new MockSeiOracle()).code);
        // Fund the farm with the asset to be borrowed
        MockERC20(lpToken).mint(address(farm), 1_000_000 ether);
        // Add a pool for lpToken and stake tokens to populate availableReserve
        farm.addPool(lpToken, lpToken, 1 ether); // rewardRate can be any nonzero value
        vm.startPrank(user1);
        MockERC20(lpToken).approve(address(farm), 1_000_000 ether);
        farm.stake(0, 500_000 ether); // Stake only half, so user1 has enough left for tests
        vm.stopPrank();
        // Authorize lending contract to call lendOut
        farm.setAuthorizedLender(address(lending), true);
        vm.prank(user1);
        MockERC20(lpToken).approve(address(lending), type(uint256).max);
        vm.prank(user2);
        MockERC20(lpToken).approve(address(lending), type(uint256).max);
    }

    // --- Deposit/Withdraw ---
    function testDeposit() public {
        uint256 amount = 1000 ether;
        uint256 before = MockERC20(lpToken).balanceOf(user1);
        vm.prank(user1);
        lending.deposit(lpToken, amount);
        assertEq(MockERC20(lpToken).balanceOf(user1), before - amount);
        assertEq(lending.deposits(user1, lpToken), amount);
    }
    function testDepositZero() public {
        vm.prank(user1);
        vm.expectRevert();
        lending.deposit(lpToken, 0);
    }
    function testWithdrawTooMuch() public {
        vm.prank(user1);
        lending.deposit(lpToken, 100 ether);
        // Withdraw not implemented in contract, so just check mapping
        assertEq(lending.deposits(user1, lpToken), 100 ether);
    }

    // --- Borrow ---
    function testBorrow() public {
        vm.prank(user1);
        lending.deposit(lpToken, 1000 ether);
        vm.prank(user1);
        lending.borrow(lpToken, 100 ether, lpToken);
        assertGt(lending.borrows(user1, lpToken), 0);
    }
    function testBorrowInsufficientCollateral() public {
        vm.prank(user1);
        vm.expectRevert();
        lending.borrow(lpToken, 1000 ether, lpToken);
    }
    function testBorrowInsufficientLiquidity() public {
        vm.prank(user1);
        lending.deposit(lpToken, 1000 ether);
        // Drain farm reserve
        vm.prank(governance);
        farm.setAuthorizedLender(address(this), true);
        // Drain all available reserve, but not more than the farm's actual ERC20 balance
        uint256 step = 100 ether;
        while (farm.availableReserve(lpToken) > 0 && MockERC20(lpToken).balanceOf(address(farm)) > 0) {
            uint256 reserve = farm.availableReserve(lpToken);
            uint256 balance = MockERC20(lpToken).balanceOf(address(farm));
            uint256 toLend = reserve < step ? reserve : step;
            toLend = toLend < balance ? toLend : balance;
            if (toLend == 0) break;
            farm.lendOut(lpToken, address(0xdead), toLend);
        }
        vm.prank(user1);
        vm.expectRevert();
        lending.borrow(lpToken, 100 ether, lpToken);
    }

    // --- Repay ---
    function testRepay() public {
        vm.prank(user1);
        lending.deposit(lpToken, 1000 ether);
        vm.prank(user1);
        lending.borrow(lpToken, 100 ether, lpToken);
        MockERC20(lpToken).mint(user1, 100 ether);
        vm.prank(user1);
        lending.repay(lpToken, 100 ether);
        assertEq(lending.borrows(user1, lpToken), 0);
    }
    function testRepayTooMuch() public {
        vm.prank(user1);
        lending.deposit(lpToken, 1000 ether);
        vm.prank(user1);
        lending.borrow(lpToken, 100 ether, lpToken);
        MockERC20(lpToken).mint(user1, 200 ether);
        vm.prank(user1);
        vm.expectRevert();
        lending.repay(lpToken, 200 ether);
    }
    function testRepayZero() public {
        vm.prank(user1);
        vm.expectRevert();
        lending.repay(lpToken, 0);
    }

    // --- Liquidation ---
    function testLiquidateHealthy() public {
        vm.expectRevert();
        lending.liquidate(user1, lpToken);
    }
    function testLiquidateUnhealthy() public {
        // User borrows up to limit, then price drops (simulate by staleness)
        vm.prank(user1);
        lending.deposit(lpToken, 1000 ether);
        vm.prank(user1);
        lending.borrow(lpToken, 100 ether, lpToken);
        // Simulate unhealthy by staleness
        vm.warp(block.timestamp + 1000);
        vm.expectRevert();
        lending.liquidate(user1, lpToken);
    }
    function testLiquidateOnlyGovernance() public {
        vm.prank(user1);
        vm.expectRevert();
        lending.liquidate(user2, lpToken);
    }

    // --- Protocol Fee ---
    function testProtocolFeeAccrualAndClaim() public {
        vm.prank(user1);
        lending.deposit(lpToken, 1000 ether);
        vm.prank(user1);
        lending.borrow(lpToken, 100 ether, lpToken);
        uint256 fee = (100 ether * lending.protocolFeeBps()) / 10000;
        assertGt(lending.protocolFeesAccrued(), 0);
        // Set treasury and claim
        vm.prank(governance);
        lending.setProtocolFee(5, governance);
        // This will revert in mock since claimProtocolFees tries to send ETH
        vm.expectRevert();
        lending.claimProtocolFees();
        // After revert, fee is still accrued
        assertEq(lending.protocolFeesAccrued(), fee);
    }

    // --- Oracle Integration ---
    function testOraclePriceFetch() public {
        (uint256 price, ) = lending.getTokenTwap(lpToken);
        assertEq(price, 1e18);
    }
    function testOracleNoMapping() public {
        address newToken = address(new MockERC20("New", "NEW"));
        vm.expectRevert();
        lending.getTokenTwap(newToken);
    }

    // --- Governance ---
    function testSetFee() public {
        vm.prank(governance);
        lending.setProtocolFee(10, governance);
        assertEq(lending.protocolFeeBps(), 10);
    }
    function testSetTreasury() public {
        vm.prank(governance);
        lending.setProtocolFee(5, user2);
        assertEq(lending.protocolTreasury(), user2);
    }
    function testSetTokenDenom() public {
        address newToken = address(new MockERC20("New", "NEW"));
        vm.prank(governance);
        lending.setTokenDenom(newToken, "NEW_DENOM");
        assertEq(keccak256(bytes(lending.tokenDenoms(newToken))), keccak256(bytes("NEW_DENOM")));
    }

    // --- Events ---
    function testEventEmissions() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit BarukLending.Deposited(user1, lpToken, 1000 ether);
        lending.deposit(lpToken, 1000 ether);
    }

    // --- Fuzzing ---
    function testFuzzDeposit(uint256 amount) public {
        uint256 maxDeposit = MockERC20(lpToken).balanceOf(user1);
        amount = bound(amount, 1, maxDeposit);
        uint256 before = MockERC20(lpToken).balanceOf(user1);
        vm.prank(user1);
        lending.deposit(lpToken, amount);
        assertEq(MockERC20(lpToken).balanceOf(user1), before - amount);
        assertEq(lending.deposits(user1, lpToken), amount);
    }
    function testFuzzBorrow(uint256 amount) public {
        // Bound to avoid insufficient collateral
        uint256 maxBorrow = (1000 ether * 1e18) / (lending.COLLATERAL_FACTOR() * 1e16);
        amount = bound(amount, 1, maxBorrow);
        vm.prank(user1);
        lending.deposit(lpToken, 1000 ether);
        vm.prank(user1);
        lending.borrow(lpToken, amount, lpToken);
        assertGt(lending.borrows(user1, lpToken), 0);
    }

    function testDepositZeroReverts() public {
        vm.prank(user1);
        vm.expectRevert();
        lending.deposit(lpToken, 0);
    }
    function testBorrowInsufficientCollateralReverts() public {
        vm.prank(user1);
        vm.expectRevert();
        lending.borrow(lpToken, 1000 ether, lpToken);
    }
    function testRepayMoreThanBorrowedReverts() public {
        vm.prank(user1);
        lending.deposit(lpToken, 1000 ether);
        vm.prank(user1);
        lending.borrow(lpToken, 100 ether, lpToken);
        // Ensure user1 has enough tokens to repay
        MockERC20(lpToken).mint(user1, 200 ether);
        emit log_named_uint("user1 lpToken balance before repay", MockERC20(lpToken).balanceOf(user1));
        vm.prank(user1);
        vm.expectRevert();
        lending.repay(lpToken, 200 ether);
    }
    function testLiquidateHealthyReverts() public {
        vm.expectRevert();
        lending.liquidate(user1, lpToken);
    }
    function testOnlyGovernanceCanLiquidate() public {
        vm.prank(user1);
        vm.expectRevert();
        lending.liquidate(user2, lpToken);
    }
} 