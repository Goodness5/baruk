// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IAmm.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IBarukFlashSwapCallback {
    function barukFlashSwapCallback(uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract BarukRouter is ReentrancyGuard {
    IBarukFactory public factory;
    address public governance;
    bool public paused;

    // Pair tracking
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    // Events
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event LiquidityAdded(address indexed provider, address indexed pair, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, address indexed pair, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed user, address indexed pair, uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut);
    event FlashSwap(address indexed user, address indexed pair, uint256 amount0Out, uint256 amount1Out, uint256 reserve0, uint256 reserve1);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);

    // Custom errors
    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();
    error PairNotFound();
    error InvalidToken();
    
    
    error TransferFailed();
    error TransactionExpired();

    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }
    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    constructor(address _factory) {
        factory = IBarukFactory(_factory);
        governance = msg.sender;
    }

    function setGovernance(address newGovernance) external onlyGovernance {
        require(newGovernance != address(0), "Zero address");
        emit GovernanceTransferred(governance, newGovernance);
        governance = newGovernance;
    }
    function pause() external onlyGovernance {
        require(!paused, "Already paused");
        paused = true;
        emit Paused(msg.sender);
    }
    function unpause() external onlyGovernance {
        require(paused, "Not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    // --- Pair Management ---
    function createPair(address tokenA, address tokenB) public whenNotPaused returns (address pair) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert PairExists();
        pair = factory.createPair(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // bi-directional lookup
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    // --- Liquidity Management ---
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external nonReentrant whenNotPaused returns (address pair, uint256 liquidity) {
        pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = createPair(tokenA, tokenB);
        }
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        // Approve the pair to pull tokens from the router
        IERC20(tokenA).approve(pair, amountA);
        IERC20(tokenB).approve(pair, amountB);
        liquidity = IBarukAMM(pair).addLiquidity(amountA, amountB, msg.sender);
        emit LiquidityAdded(msg.sender, pair, amountA, amountB, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external nonReentrant whenNotPaused returns (uint256 amountA, uint256 amountB) {
        address pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) revert PairNotFound();
        (amountA, amountB) = IBarukAMM(pair).removeLiquidity(liquidity);
        emit LiquidityRemoved(msg.sender, pair, amountA, amountB, liquidity);
    }

    // --- Swapping ---
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        address recipient
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        if (block.timestamp > deadline) revert TransactionExpired();
        address pair = factory.getPair(tokenIn, tokenOut);
        if (pair == address(0)) revert PairNotFound();
        IERC20(tokenIn).transferFrom(msg.sender, pair, amountIn);
        amountOut = IBarukAMM(pair).publicSwap(amountIn, tokenIn, minAmountOut, recipient);
        emit Swap(msg.sender, pair, amountIn, amountOut, tokenIn, tokenOut);
    }

    // function swapWithPermit(
    //     address tokenIn,
    //     address tokenOut,
    //     uint256 amountIn,
    //     uint256 minAmountOut,
    //     uint256 deadline,
    //     uint8 v,
    //     bytes32 r,
    //     bytes32 s,
    //     address recipient
    // ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
    //     if (block.timestamp > deadline) revert TransactionExpired();
    //     address pair = getPair[tokenIn][tokenOut];
    //     if (pair == address(0)) revert PairNotFound();
    //     IERC20Permit(tokenIn).permit(msg.sender, pair, amountIn, deadline, v, r, s);
    //     IERC20(tokenIn).transferFrom(msg.sender, pair, amountIn);
    //     amountOut = IBarukAMM(pair).publicSwap(amountIn, tokenIn, minAmountOut, recipient);
    //     emit Swap(msg.sender, pair, amountIn, amountOut, tokenIn, tokenOut);
    // }

    // --- Flash Swap ---
    function flashSwap(
        address tokenA,
        address tokenB,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external nonReentrant whenNotPaused {
        address pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) revert PairNotFound();
        address token0 = IBarukAMM(pair).token0();
        address token1 = IBarukAMM(pair).token1();
        uint256 balance0Before = IERC20(token0).balanceOf(pair);
        uint256 balance1Before = IERC20(token1).balanceOf(pair);
        if (amount0Out > 0) IERC20(token0).transferFrom(pair, to, amount0Out);
        if (amount1Out > 0) IERC20(token1).transferFrom(pair, to, amount1Out);
        IBarukFlashSwapCallback(to).barukFlashSwapCallback(amount0Out, amount1Out, data);
        if (IERC20(token0).balanceOf(pair) < balance0Before || IERC20(token1).balanceOf(pair) < balance1Before)
            revert TransferFailed();
        (uint256 reserve0, uint256 reserve1) = IBarukAMM(pair).getReserves();
        emit FlashSwap(to, pair, amount0Out, amount1Out, reserve0, reserve1);
    }
} 