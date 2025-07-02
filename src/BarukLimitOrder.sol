// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Router.sol";

contract BarukLimitOrder {
    struct Order {
        address user;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        bool active;
    }

    address public governance;
    address public router;
    Order[] public orders;

    // Protocol fee and treasury
    uint256 public protocolFeeBps = 5; // 0.05% default
    address public protocolTreasury;
    mapping(address => uint256) public protocolFeesAccrued; // token => amount
    event ProtocolFeeSet(uint256 newFeeBps, address newTreasury);
    event ProtocolFeeAccrued(address indexed treasury, uint256 amount);
    event ProtocolFeeClaimed(address indexed treasury, uint256 amount);

    event OrderPlaced(uint256 indexed orderId, address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut);
    event OrderCancelled(uint256 indexed orderId, address indexed user);
    event OrderExecuted(uint256 indexed orderId, address indexed user, uint256 amountOut);

    bool public paused;
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }

    constructor(address _router) {
        governance = msg.sender;
        router = _router;
    }

    function placeOrder(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut) external whenNotPaused returns (uint256 orderId) {
        require(amountIn > 0, "Zero amount");
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        orders.push(Order({
            user: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            active: true
        }));
        orderId = orders.length - 1;
        emit OrderPlaced(orderId, msg.sender, tokenIn, tokenOut, amountIn, minAmountOut);
    }

    function cancelOrder(uint256 orderId) external whenNotPaused {
        require(orderId < orders.length, "Invalid orderId");
        Order storage order = orders[orderId];
        require(order.user == msg.sender, "Not order owner");
        require(order.active, "Order not active");
        order.active = false;
        emit OrderCancelled(orderId, msg.sender);
    }

    // Protocol can claim accrued fees
    function claimProtocolFees(address token) external {
        require(msg.sender == protocolTreasury, "Not treasury");
        uint256 amount = protocolFeesAccrued[token];
        require(amount > 0, "No fees");
        protocolFeesAccrued[token] = 0;
        IERC20(token).transfer(protocolTreasury, amount);
        emit ProtocolFeeClaimed(protocolTreasury, amount);
    }

    // Update executeOrder to take protocol fee (for demo, fee is a flat value or % of amountOut)
    function executeOrder(uint256 orderId, uint256 amountOut) external onlyGovernance whenNotPaused {
        require(orderId < orders.length, "Invalid orderId");
        Order storage order = orders[orderId];
        require(order.active, "Order not active");
        order.active = false;
        require(IERC20(order.tokenIn).balanceOf(address(this)) >= order.amountIn, "Insufficient tokenIn");
        IERC20(order.tokenIn).approve(router, order.amountIn);
        uint256 outAmount = BarukRouter(router).swap(order.tokenIn, order.tokenOut, order.amountIn, order.minAmountOut, block.timestamp + 600, address(this));
        require(outAmount >= order.minAmountOut, "Slippage");
        uint256 protocolFee = (outAmount * protocolFeeBps) / 10000;
        protocolFeesAccrued[order.tokenOut] += protocolFee;
        emit ProtocolFeeAccrued(protocolTreasury, protocolFee);
        uint256 amountAfterFee = outAmount - protocolFee;
        IERC20(order.tokenOut).transfer(order.user, amountAfterFee);
        emit OrderExecuted(orderId, order.user, amountAfterFee);
    }

    // Governance function to set protocol fee and treasury
    function setProtocolFee(uint256 newFeeBps, address newTreasury) external onlyGovernance {
        require(newFeeBps <= 100, "Fee too high");
        protocolFeeBps = newFeeBps;
        protocolTreasury = newTreasury;
        emit ProtocolFeeSet(newFeeBps, newTreasury);
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
} 