// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IYieldStrategy {
    function deposit(address token, uint256 amount) external returns (uint256 shares);
    function withdraw(address token, uint256 shares) external returns (uint256 amount);
    function getBalance(address token) external view returns (uint256);
    function getYieldAccrued(address token) external view returns (uint256);
}
