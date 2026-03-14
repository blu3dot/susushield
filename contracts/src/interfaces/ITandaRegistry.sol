// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITandaRegistry {
    struct PoolListing {
        uint256 poolId;
        string category;
        uint256 minTrustScore;
        uint256 memberCount;
        uint256 maxMembers;
        uint256 contributionAmount;
        address paymentToken;
        bool isActive;
    }

    event PoolRegistered(uint256 indexed poolId, string category, uint256 minTrustScore);
    event PoolDelisted(uint256 indexed poolId);
    event CategoryAdded(string category);

    error PoolAlreadyRegistered();
    error PoolNotRegistered();
    error NotPoolCreator();
    error InvalidCategory();
    error RegistryPaused();

    function registerPool(uint256 poolId, string calldata category, uint256 minTrustScore) external;
    function delistPool(uint256 poolId) external;
    function search(string calldata category, uint256 offset, uint256 limit) external view returns (PoolListing[] memory);
    function getListedPools(uint256 offset, uint256 limit) external view returns (PoolListing[] memory);
    function getPoolListing(uint256 poolId) external view returns (PoolListing memory);
    function isPoolListed(uint256 poolId) external view returns (bool);
    function getPoolsByCategory(string calldata category) external view returns (uint256[] memory);
    function totalListedPools() external view returns (uint256);
}
