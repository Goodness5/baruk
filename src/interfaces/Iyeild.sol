// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBarukYieldFarming {
    // Events
    event Stake(address indexed user, uint256 amount, address pool);
    event Unstake(address indexed user, uint256 amount, address pool);
    event ClaimRewards(address indexed user, uint256 amount);

    // Stake assets in a pool
    function stake(address pool, uint256 amount) external;

    // Unstake assets from a pool
    function unstake(address pool, uint256 amount) external;

    // Claim accumulated BRK rewards
    function claimRewards(address pool) external;

    // Get staked balance for a user
    function getStakedBalance(
        address user,
        address pool
    ) external view returns (uint256);

    // Get pending rewards for a user
    function getPendingRewards(
        address user,
        address pool
    ) external view returns (uint256);
}
