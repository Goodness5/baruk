// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IAmm.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract BarukAMM is IBarukAMM, ReentrancyGuard {


    
    IERC20 public token0; // e.g., SEI
    IERC20 public token1; // e.g., BRK
    address public factory; // Factory contract for pool creation
    uint256 public reserve0; // Reserve of token0
    uint256 public reserve1; // Reserve of token1
    uint256 public totalLiquidity; // Total liquidity tokens issued
    mapping(address => uint256) public liquidityBalance; // Liquidity balance per user
    uint256 private constant FEE = 30; // 0.3% fee (30 basis points)
    uint256 private constant MINIMUM_LIQUIDITY = 10 ** 3; // Prevent division by zero

    // Custom errors for better debugging
    error ArithmeticOverflow(string operation);
    error DivisionByZero();
    error InvalidToken();
    error InsufficientLiquidity();
    error SlippageTooHigh();
    error TransferFailed();

    constructor(address _token0, address _token1) {
        factory = msg.sender;
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }


    function addLiquidity(
        uint256 amount0,
        uint256 amount1
    ) external override nonReentrant returns (uint256 liquidity) {
        require(amount0 > 0 && amount1 > 0, "Invalid amounts");

        uint256 _reserve0 = reserve0;
        uint256 _reserve1 = reserve1;
        if (_reserve0 == 0 && _reserve1 == 0) {
            liquidity = sqrt(amount0 * amount1);
            if (liquidity <= MINIMUM_LIQUIDITY)
                revert ArithmeticOverflow("Initial liquidity too low");
            liquidity -= MINIMUM_LIQUIDITY;
        } else {
            uint256 amount1Optimal = (amount0 * _reserve1) / _reserve0;
            require(amount1 >= amount1Optimal, "Invalid token ratio");
            liquidity = (amount0 * totalLiquidity) / _reserve0;
        }

        if (!token0.transferFrom(msg.sender, address(this), amount0))
            revert TransferFailed();
        if (!token1.transferFrom(msg.sender, address(this), amount1))
            revert TransferFailed();

        if (reserve0 + amount0 < reserve0)
            revert ArithmeticOverflow("reserve0 addition");
        if (reserve1 + amount1 < reserve1)
            revert ArithmeticOverflow("reserve1 addition");
        if (totalLiquidity + liquidity < totalLiquidity)
            revert ArithmeticOverflow("totalLiquidity addition");
        if (
            liquidityBalance[msg.sender] + liquidity <
            liquidityBalance[msg.sender]
        ) revert ArithmeticOverflow("liquidityBalance addition");

        reserve0 += amount0;
        reserve1 += amount1;
        totalLiquidity += liquidity;
        liquidityBalance[msg.sender] += liquidity;

        emit LiquidityAdded(msg.sender, amount0, amount1, liquidity);
    }

    function removeLiquidity(
        uint256 liquidity
    )
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity == 0 || liquidityBalance[msg.sender] < liquidity)
            revert InsufficientLiquidity();

        amount0 = (liquidity * reserve0) / totalLiquidity;
        amount1 = (liquidity * reserve1) / totalLiquidity;

        if (liquidityBalance[msg.sender] < liquidity)
            revert ArithmeticOverflow("liquidityBalance subtraction");
        if (totalLiquidity < liquidity)
            revert ArithmeticOverflow("totalLiquidity subtraction");
        if (reserve0 < amount0)
            revert ArithmeticOverflow("reserve0 subtraction");
        if (reserve1 < amount1)
            revert ArithmeticOverflow("reserve1 subtraction");

        liquidityBalance[msg.sender] -= liquidity;
        totalLiquidity -= liquidity;
        reserve0 -= amount0;
        reserve1 -= amount1;

        if (!token0.transfer(msg.sender, amount0)) revert TransferFailed();
        if (!token1.transfer(msg.sender, amount1)) revert TransferFailed();

        emit LiquidityRemoved(msg.sender, amount0, amount1, liquidity);
    }

    function swap(
        uint256 amountIn,
        address tokenIn,
        uint256 minAmountOut
    ) external override nonReentrant returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientLiquidity();
        if (tokenIn != address(token0) && tokenIn != address(token1))
            revert InvalidToken();

        bool isToken0 = tokenIn == address(token0);
        (uint256 reserveIn, uint256 reserveOut) = isToken0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        IERC20 tokenInContract = isToken0 ? token0 : token1;
        IERC20 tokenOutContract = isToken0 ? token1 : token0;

        uint256 amountInWithFee = (amountIn * (10000 - FEE)) / 10000;
        amountOut = getAmountOut(amountInWithFee, reserveIn, reserveOut);
        if (amountOut < minAmountOut) revert SlippageTooHigh();

        if (!tokenInContract.transferFrom(msg.sender, address(this), amountIn))
            revert TransferFailed();
        if (!tokenOutContract.transfer(msg.sender, amountOut))
            revert TransferFailed();

        if (isToken0) {
            if (reserve0 + amountIn < reserve0)
                revert ArithmeticOverflow("reserve0 addition");
            if (reserve1 < amountOut)
                revert ArithmeticOverflow("reserve1 subtraction");
            reserve0 += amountIn;
            reserve1 -= amountOut;
        } else {
            if (reserve1 + amountIn < reserve1)
                revert ArithmeticOverflow("reserve1 addition");
            if (reserve0 < amountOut)
                revert ArithmeticOverflow("reserve0 subtraction");
            reserve1 += amountIn;
            reserve0 -= amountOut;
        }

        emit Swap(msg.sender, amountIn, amountOut, tokenIn);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure override returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0)
            revert InsufficientLiquidity();
        uint256 numerator = amountIn * reserveOut;
        uint256 denominator = reserveIn + amountIn;
        if (denominator == 0) revert DivisionByZero();
        return numerator / denominator;
    }

    function getReserves()
        external
        view
        override
        returns (uint256 _reserve0, uint256 _reserve1)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    function sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        } else {
            z = 0; // Handle y = 0 case explicitly
        }
        return z;
    }
}
