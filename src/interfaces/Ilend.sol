// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBarukLending {
    // Events
    event Deposit(address indexed user, address asset, uint256 amount);
    event Borrow(address indexed user, address asset, uint256 amount, address collateral);
    event Repay(address indexed user, address asset, uint256 amount);
    event Liquidate(address indexed user, address collateral, uint256 amount);

    // Deposit assets to earn interest
    function deposit(address asset, uint256 amount) external;

    // Borrow assets against collateral
    function borrow(address asset, uint256 amount, address collateral) external;

    // Repay borrowed assets
    function repay(address asset, uint256 amount) external;

    // Liquidate under-collateralized loans
    function liquidate(address user, address collateral) external;

    // Get user’s deposit balance
    function getDepositBalance(address user, address asset) external view returns (uint256);

    // Get user’s borrow balance
    function getBorrowBalance(address user, address asset) external view returns (uint256);

    // Get current interest rate for an asset
    function getInterestRate(address asset) external view returns (uint256);
}