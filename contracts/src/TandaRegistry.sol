// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./interfaces/ITandaRegistry.sol";
import "./interfaces/ITandaPool.sol";

/**
 * @title TandaRegistry
 * @dev Circle Discovery & Registry for nuROSA ROSCA pools
 * @notice Allows pool creators to list their pools for discovery by category,
 *         with paginated search. MVP on-chain — production uses The Graph subgraph.
 */
contract TandaRegistry is Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, ITandaRegistry {
    // Reference to TandaPool contract
    address public tandaPool;

    // Pool listings
    mapping(uint256 => PoolListing) internal _listings;
    mapping(uint256 => bool) internal _isListed;
    uint256[] public listedPoolIds;

    // Category management
    mapping(string => uint256[]) internal _categoryPools;
    mapping(string => bool) public validCategories;
    string[] public categories;

    // Counters
    uint256 public listedCount;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _tandaPool) public initializer {
        require(_tandaPool != address(0), "Invalid TandaPool");
        __Ownable_init(msg.sender);
        __Pausable_init();
        tandaPool = _tandaPool;

        // Add default categories
        _addCategory("savings");
        _addCategory("investment");
        _addCategory("community");
        _addCategory("emergency");
        _addCategory("education");
    }

    // ---------------------------------------------------------------
    // Mutative functions
    // ---------------------------------------------------------------

    function registerPool(
        uint256 poolId,
        string calldata category,
        uint256 minTrustScore
    ) external whenNotPaused {
        require(!_isListed[poolId], "Pool already registered");
        require(validCategories[category], "Invalid category");

        // Verify caller is pool creator
        ITandaPool.Pool memory pool = ITandaPool(tandaPool).getPool(poolId);
        require(pool.creator == msg.sender, "Not pool creator");
        require(pool.status == ITandaPool.PoolStatus.Created, "Pool not in Created status");

        // Create listing
        _listings[poolId] = PoolListing({
            poolId: poolId,
            category: category,
            minTrustScore: minTrustScore,
            memberCount: 0,
            maxMembers: pool.maxMembers,
            contributionAmount: pool.contributionAmount,
            paymentToken: pool.paymentToken,
            isActive: true
        });

        _isListed[poolId] = true;
        listedPoolIds.push(poolId);
        _categoryPools[category].push(poolId);
        listedCount++;

        emit PoolRegistered(poolId, category, minTrustScore);
    }

    function delistPool(uint256 poolId) external {
        require(_isListed[poolId], "Pool not registered");

        ITandaPool.Pool memory pool = ITandaPool(tandaPool).getPool(poolId);
        require(pool.creator == msg.sender || msg.sender == owner(), "Not authorized");

        _listings[poolId].isActive = false;
        _isListed[poolId] = false;
        listedCount--;

        emit PoolDelisted(poolId);
    }

    // ---------------------------------------------------------------
    // View functions
    // ---------------------------------------------------------------

    /// @notice Search pools by category with pagination
    /// @dev Gas-expensive on-chain search — MVP only. Production uses The Graph.
    function search(
        string calldata category,
        uint256 offset,
        uint256 limit
    ) external view returns (PoolListing[] memory) {
        uint256[] storage poolIds = _categoryPools[category];
        return _paginateFromIds(poolIds, offset, limit);
    }

    /// @notice Return all active listed pools with pagination
    function getListedPools(
        uint256 offset,
        uint256 limit
    ) external view returns (PoolListing[] memory) {
        return _paginateFromIds(listedPoolIds, offset, limit);
    }

    /// @notice Get a single pool listing
    function getPoolListing(uint256 poolId) external view returns (PoolListing memory) {
        return _listings[poolId];
    }

    /// @notice Check whether a pool is currently listed
    function isPoolListed(uint256 poolId) external view returns (bool) {
        return _isListed[poolId];
    }

    /// @notice Return all pool IDs in a given category
    function getPoolsByCategory(string calldata category) external view returns (uint256[] memory) {
        return _categoryPools[category];
    }

    /// @notice Total number of currently listed pools
    function totalListedPools() external view returns (uint256) {
        return listedCount;
    }

    // ---------------------------------------------------------------
    // Admin functions
    // ---------------------------------------------------------------

    function addCategory(string calldata category) external onlyOwner {
        _addCategory(category);
    }

    function setTandaPool(address _tandaPool) external onlyOwner {
        require(_tandaPool != address(0), "Invalid address");
        tandaPool = _tandaPool;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------

    function _addCategory(string memory category) internal {
        require(!validCategories[category], "Category exists");
        validCategories[category] = true;
        categories.push(category);
        emit CategoryAdded(category);
    }

    /// @dev Paginate over a uint256[] of pool IDs, returning only active listings.
    function _paginateFromIds(
        uint256[] storage poolIds,
        uint256 offset,
        uint256 limit
    ) internal view returns (PoolListing[] memory) {
        // First pass: count active listings to know total available
        uint256 totalActive = 0;
        for (uint256 i = 0; i < poolIds.length; i++) {
            if (_listings[poolIds[i]].isActive) {
                totalActive++;
            }
        }

        // Determine result size
        if (offset >= totalActive) {
            return new PoolListing[](0);
        }
        uint256 remaining = totalActive - offset;
        uint256 resultSize = remaining < limit ? remaining : limit;

        PoolListing[] memory results = new PoolListing[](resultSize);
        uint256 activeIndex = 0; // tracks how many active items we've seen
        uint256 added = 0;

        for (uint256 i = 0; i < poolIds.length && added < resultSize; i++) {
            if (_listings[poolIds[i]].isActive) {
                if (activeIndex >= offset) {
                    results[added] = _listings[poolIds[i]];
                    added++;
                }
                activeIndex++;
            }
        }

        return results;
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // Storage gap for future upgrades
    uint256[50] private __gap;
}
