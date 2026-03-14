// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITandaPool.sol";
import "./interfaces/IYieldStrategy.sol";

/**
 * @title TandaPool
 * @dev Implementation of Rotating Savings and Credit Association (ROSCA) for DeFi
 * @notice This contract manages decentralized tanda pools where members contribute
 * periodically and take turns receiving the full pool amount
 */
contract TandaPool is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    ITandaPool
{
    using SafeERC20 for IERC20;

    // State variables
    mapping(uint256 => Pool) public pools;
    mapping(uint256 => Member[]) public poolMembers;
    mapping(uint256 => mapping(address => uint256)) public memberIndex; // Pool ID -> Member address -> Index
    mapping(uint256 => mapping(uint256 => Contribution[])) public poolContributions; // Pool ID -> Round -> Contributions
    mapping(uint256 => mapping(uint256 => Bid[])) public poolBids; // Pool ID -> Round -> Bids

    uint256 public nextPoolId;
    address public platformTreasury;
    uint256 public defaultPlatformFee; // Default platform fee in basis points
    uint256 public constant MAX_PLATFORM_FEE = 1000; // Maximum 10% fee
    uint256 public constant MAX_MEMBERS = 50; // Maximum members per pool
    uint256 public constant MIN_ROUND_DURATION = 1 days;
    uint256 public constant MAX_ROUND_DURATION = 30 days;

    // EIP-712 invite tracking
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) public usedInviteNonces; // poolId -> inviter -> nonce -> used
    bytes32 public constant INVITE_TYPEHASH = keccak256("Invite(uint256 poolId,address invitee,uint256 nonce,uint256 deadline)");

    // Decommission helper: tracks who contributed in a round for O(1) lookup
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) private _roundContributorCheck; // poolId -> round -> member -> contributed

    // Yield strategy
    IYieldStrategy public yieldStrategy;
    mapping(uint256 => uint256) public poolYieldShares; // Pool ID -> shares deposited in yield strategy

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param _platformTreasury Address to receive platform fees
     * @param _defaultPlatformFee Default platform fee in basis points
     */
    function initialize(
        address _platformTreasury,
        uint256 _defaultPlatformFee
    ) public initializer {
        require(_platformTreasury != address(0), "Invalid treasury");
        require(_defaultPlatformFee <= MAX_PLATFORM_FEE, "Fee too high");

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __EIP712_init("TandaPool", "1");

        platformTreasury = _platformTreasury;
        defaultPlatformFee = _defaultPlatformFee;
        nextPoolId = 1;
    }

    /**
     * @dev Create a new tanda pool
     * @param paymentToken Token used for contributions (address(0) for native token)
     * @param contributionAmount Amount each member contributes per round
     * @param maxMembers Maximum number of members
     * @param roundDuration Duration of each round in seconds
     * @param payoutMethod Method for determining payout order
     * @param requiresCollateral Whether members must deposit collateral
     * @param collateralAmount Amount of collateral required if applicable
     * @param metadata JSON metadata for pool
     */
    function createPool(
        address paymentToken,
        uint256 contributionAmount,
        uint256 maxMembers,
        uint256 roundDuration,
        PayoutMethod payoutMethod,
        bool requiresCollateral,
        uint256 collateralAmount,
        string calldata metadata
    ) external whenNotPaused returns (uint256 poolId) {
        require(contributionAmount > 0, "Invalid contribution amount");
        require(maxMembers >= 2 && maxMembers <= MAX_MEMBERS, "Invalid member count");
        require(roundDuration >= MIN_ROUND_DURATION && roundDuration <= MAX_ROUND_DURATION, "Invalid round duration");

        if (requiresCollateral) {
            require(collateralAmount > 0, "Invalid collateral amount");
        }

        poolId = nextPoolId++;

        Pool storage newPool = pools[poolId];
        newPool.id = poolId;
        newPool.creator = msg.sender;
        newPool.paymentToken = paymentToken;
        newPool.contributionAmount = contributionAmount;
        newPool.maxMembers = maxMembers;
        newPool.roundDuration = roundDuration;
        newPool.payoutMethod = payoutMethod;
        newPool.requiresCollateral = requiresCollateral;
        newPool.collateralAmount = collateralAmount;
        newPool.platformFee = defaultPlatformFee;
        newPool.status = PoolStatus.Created;
        newPool.metadata = metadata;

        emit PoolCreated(poolId, msg.sender, contributionAmount, maxMembers, payoutMethod);
    }

    /**
     * @dev Join an existing pool
     * @param poolId ID of the pool to join
     */
    function joinPool(uint256 poolId) external payable nonReentrant whenNotPaused {
        Pool storage pool = pools[poolId];
        require(pool.status == PoolStatus.Created, "Pool not accepting members");
        require(poolMembers[poolId].length < pool.maxMembers, "Pool is full");

        _addMember(poolId, pool);
    }

    /**
     * @dev Redeem an EIP-712 signed invite to join a pool
     * @param poolId ID of the pool to join
     * @param inviteNonce Unique nonce for this invite
     * @param deadline Timestamp after which the invite expires
     * @param signature EIP-712 signature from the pool creator
     */
    function redeemInvite(
        uint256 poolId,
        uint256 inviteNonce,
        uint256 deadline,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused {
        // Verify deadline not passed
        require(block.timestamp <= deadline, "Invite expired");

        Pool storage pool = pools[poolId];
        require(pool.status == PoolStatus.Created, "Pool not accepting members");
        require(poolMembers[poolId].length < pool.maxMembers, "Pool is full");

        // Verify signature: the pool creator signed an invite for msg.sender
        bytes32 structHash = keccak256(abi.encode(INVITE_TYPEHASH, poolId, msg.sender, inviteNonce, deadline));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, signature);

        // Signer must be pool creator
        require(signer == pool.creator, "Invalid signature");

        // Check nonce not used
        require(!usedInviteNonces[poolId][signer][inviteNonce], "Invite already used");
        usedInviteNonces[poolId][signer][inviteNonce] = true;

        emit InviteRedeemed(poolId, msg.sender, signer);

        _addMember(poolId, pool);
    }

    /**
     * @dev Make a contribution to the pool for the current round
     * @param poolId ID of the pool
     */
    function contribute(uint256 poolId) external payable nonReentrant whenNotPaused {
        Pool storage pool = pools[poolId];
        require(pool.status == PoolStatus.Active, "Pool not active");
        require(_isMember(poolId, msg.sender), "Not a pool member");
        require(block.timestamp < pool.nextRoundTimestamp, "Round ended");

        uint256 memberIdx = memberIndex[poolId][msg.sender] - 1;
        Member storage member = poolMembers[poolId][memberIdx];

        require(!_hasContributed(poolId, pool.currentRound, msg.sender), "Already contributed this round");

        uint256 contributionAmount = pool.contributionAmount;

        // Handle payment
        if (pool.paymentToken == address(0)) {
            require(msg.value >= contributionAmount, "Insufficient payment");
            if (msg.value > contributionAmount) {
                (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - contributionAmount}("");
                require(refundSuccess, "ETH transfer failed");
            }
        } else {
            IERC20(pool.paymentToken).safeTransferFrom(msg.sender, address(this), contributionAmount);
        }

        // Record contribution
        Contribution memory newContribution = Contribution({
            member: msg.sender,
            amount: contributionAmount,
            timestamp: block.timestamp,
            round: pool.currentRound
        });

        poolContributions[poolId][pool.currentRound].push(newContribution);
        member.totalContributions += contributionAmount;

        emit ContributionMade(poolId, msg.sender, contributionAmount, pool.currentRound);

        // Check if all members have contributed
        if (poolContributions[poolId][pool.currentRound].length == pool.maxMembers) {
            _processRoundPayout(poolId);
        }
    }

    /**
     * @dev Place a bid for early payout (only for bidding pools)
     * @param poolId ID of the pool
     * @param bidAmount Amount to bid (additional payment to other members)
     */
    function placeBid(uint256 poolId, uint256 bidAmount) external nonReentrant whenNotPaused {
        Pool storage pool = pools[poolId];
        require(pool.status == PoolStatus.Active, "Pool not active");
        require(pool.payoutMethod == PayoutMethod.Bidding, "Not a bidding pool");
        require(_isMember(poolId, msg.sender), "Not a pool member");

        uint256 memberIdx = memberIndex[poolId][msg.sender] - 1;
        Member storage member = poolMembers[poolId][memberIdx];
        require(!member.hasReceivedPayout, "Already received payout");

        // Cap bid to maximum payout (contribution * members minus fees)
        uint256 maxPayout = pool.contributionAmount * pool.maxMembers;
        require(bidAmount > 0 && bidAmount <= maxPayout, "Invalid bid amount");

        Bid memory newBid = Bid({
            bidder: msg.sender,
            amount: bidAmount,
            round: pool.currentRound,
            timestamp: block.timestamp
        });

        poolBids[poolId][pool.currentRound].push(newBid);

        emit BidPlaced(poolId, msg.sender, bidAmount, pool.currentRound);
    }

    /**
     * @dev Deposit idle pool funds into the yield strategy for earning yield
     * @param poolId ID of the pool
     */
    function depositIdleFunds(uint256 poolId) external nonReentrant whenNotPaused {
        require(address(yieldStrategy) != address(0), "No yield strategy set");

        Pool storage pool = pools[poolId];
        require(pool.status == PoolStatus.Active, "Pool not active");
        require(pool.paymentToken != address(0), "Native token yield not supported");

        // Must have all contributions for this round
        require(
            poolContributions[poolId][pool.currentRound].length == pool.maxMembers,
            "Not all members contributed"
        );

        // Cannot deposit if already deposited for this pool
        require(poolYieldShares[poolId] == 0, "Already deposited");

        uint256 totalContributions = pool.contributionAmount * pool.maxMembers;

        // Approve yield strategy to pull tokens
        IERC20(pool.paymentToken).approve(address(yieldStrategy), totalContributions);

        // Deposit into yield strategy
        uint256 shares = yieldStrategy.deposit(pool.paymentToken, totalContributions);
        poolYieldShares[poolId] = shares;

        emit YieldDeposited(poolId, totalContributions);
    }

    /**
     * @dev Process payout for the current round
     * @param poolId ID of the pool
     */
    function _processRoundPayout(uint256 poolId) internal {
        Pool storage pool = pools[poolId];
        uint256 totalContributions = pool.contributionAmount * pool.maxMembers;

        // Calculate platform fee
        uint256 feeAmount = (totalContributions * pool.platformFee) / 10000;
        uint256 payoutAmount = totalContributions - feeAmount;

        // If funds are in yield strategy, withdraw them first
        uint256 yieldEarned = 0;
        if (address(yieldStrategy) != address(0) && poolYieldShares[poolId] > 0) {
            uint256 shares = poolYieldShares[poolId];
            uint256 balanceBefore = IERC20(pool.paymentToken).balanceOf(address(this));
            yieldStrategy.withdraw(pool.paymentToken, shares);
            uint256 balanceAfter = IERC20(pool.paymentToken).balanceOf(address(this));
            uint256 totalWithdrawn = balanceAfter - balanceBefore;

            if (totalWithdrawn > totalContributions) {
                yieldEarned = totalWithdrawn - totalContributions;
            }

            poolYieldShares[poolId] = 0;

            emit YieldWithdrawn(poolId, totalContributions, yieldEarned);
        }

        // Transfer platform fee
        if (feeAmount > 0) {
            if (pool.paymentToken == address(0)) {
                (bool feeSuccess, ) = payable(platformTreasury).call{value: feeAmount}("");
                require(feeSuccess, "ETH transfer failed");
            } else {
                IERC20(pool.paymentToken).safeTransfer(platformTreasury, feeAmount);
            }
        }

        // Determine payout recipient
        address payoutRecipient = _determinePayoutRecipient(poolId);

        // Calculate yield bonus: 80% to recipient, 20% to protocol
        uint256 yieldToRecipient = 0;
        uint256 yieldToProtocol = 0;
        if (yieldEarned > 0) {
            yieldToRecipient = (yieldEarned * 80) / 100;
            yieldToProtocol = yieldEarned - yieldToRecipient;

            // Transfer protocol's yield share
            if (pool.paymentToken == address(0)) {
                (bool yieldFeeSuccess, ) = payable(platformTreasury).call{value: yieldToProtocol}("");
                require(yieldFeeSuccess, "ETH transfer failed");
            } else {
                IERC20(pool.paymentToken).safeTransfer(platformTreasury, yieldToProtocol);
            }
        }

        uint256 totalPayout = payoutAmount + yieldToRecipient;

        // For bidding pools, deduct the winning bid amount from payout
        // The bid represents a discount — how much less the winner accepts
        if (pool.payoutMethod == PayoutMethod.Bidding) {
            Bid[] storage roundBids = poolBids[poolId][pool.currentRound];
            for (uint256 i = 0; i < roundBids.length; i++) {
                if (roundBids[i].bidder == payoutRecipient) {
                    uint256 bidDiscount = roundBids[i].amount;
                    if (bidDiscount > totalPayout) {
                        bidDiscount = totalPayout;
                    }
                    totalPayout -= bidDiscount;
                    // Bid discount stays in contract as protocol revenue
                    break;
                }
            }
        }

        // Transfer payout + yield bonus
        if (pool.paymentToken == address(0)) {
            (bool payoutSuccess, ) = payable(payoutRecipient).call{value: totalPayout}("");
            require(payoutSuccess, "ETH transfer failed");
        } else {
            IERC20(pool.paymentToken).safeTransfer(payoutRecipient, totalPayout);
        }

        // Update member status
        uint256 memberIdx = memberIndex[poolId][payoutRecipient] - 1;
        Member storage member = poolMembers[poolId][memberIdx];
        member.hasReceivedPayout = true;
        member.payoutRound = pool.currentRound;

        emit PayoutDistributed(poolId, payoutRecipient, totalPayout, pool.currentRound);

        // Advance to next round or complete pool
        pool.currentRound++;
        if (pool.currentRound >= pool.maxMembers) {
            _completePool(poolId);
        } else {
            pool.nextRoundTimestamp = block.timestamp + pool.roundDuration;
        }
    }

    /**
     * @dev Determine who receives the payout for the current round
     * @param poolId ID of the pool
     * @return recipient Address of the payout recipient
     */
    function _determinePayoutRecipient(uint256 poolId) internal view returns (address recipient) {
        Pool storage pool = pools[poolId];

        if (pool.payoutMethod == PayoutMethod.Sequential) {
            // Find next member in sequence who hasn't received payout
            for (uint256 i = 0; i < poolMembers[poolId].length; i++) {
                if (!poolMembers[poolId][i].hasReceivedPayout) {
                    return poolMembers[poolId][i].wallet;
                }
            }
        } else if (pool.payoutMethod == PayoutMethod.Lottery) {
            // Lottery requires verifiable randomness (e.g., Chainlink VRF) — not supported in MVP
            revert("Lottery payout not supported");
        } else if (pool.payoutMethod == PayoutMethod.Bidding) {
            // Find highest bidder for this round
            Bid[] storage roundBids = poolBids[poolId][pool.currentRound];
            uint256 highestBid = 0;
            address highestBidder;

            for (uint256 i = 0; i < roundBids.length; i++) {
                uint256 memberIdx = memberIndex[poolId][roundBids[i].bidder] - 1;
                if (!poolMembers[poolId][memberIdx].hasReceivedPayout && roundBids[i].amount > highestBid) {
                    highestBid = roundBids[i].amount;
                    highestBidder = roundBids[i].bidder;
                }
            }

            if (highestBidder != address(0)) {
                return highestBidder;
            }

            // If no bids, fall back to sequential
            for (uint256 i = 0; i < poolMembers[poolId].length; i++) {
                if (!poolMembers[poolId][i].hasReceivedPayout) {
                    return poolMembers[poolId][i].wallet;
                }
            }
        }

        revert("No eligible recipient found");
    }

    /**
     * @dev Start the pool when it's full
     * @param poolId ID of the pool
     */
    function _startPool(uint256 poolId) internal {
        Pool storage pool = pools[poolId];
        pool.status = PoolStatus.Active;
        pool.currentRound = 1;
        pool.nextRoundTimestamp = block.timestamp + pool.roundDuration;
    }

    /**
     * @dev Complete the pool when all rounds are finished
     * @param poolId ID of the pool
     */
    function _completePool(uint256 poolId) internal {
        Pool storage pool = pools[poolId];
        pool.status = PoolStatus.Completed;

        _returnAllCollateral(poolId, pool);

        emit PoolCompleted(poolId);
    }

    /**
     * @dev Check if an address is a member of the pool
     * @param poolId ID of the pool
     * @param member Address to check
     * @return isMember Whether the address is a member
     */
    function _isMember(uint256 poolId, address member) internal view returns (bool isMember) {
        uint256 idx = memberIndex[poolId][member];
        return idx > 0 && poolMembers[poolId][idx - 1].wallet == member;
    }

    /**
     * @dev Check if a member has contributed in a specific round
     * @param poolId ID of the pool
     * @param round Round number
     * @param member Member address
     * @return Whether the member has contributed
     */
    function _hasContributed(uint256 poolId, uint256 round, address member) internal view returns (bool) {
        Contribution[] storage roundContributions = poolContributions[poolId][round];
        for (uint256 i = 0; i < roundContributions.length; i++) {
            if (roundContributions[i].member == member) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Add a member to a pool with collateral handling. Shared by joinPool and redeemInvite.
     * @param poolId ID of the pool
     * @param pool Storage reference to the pool
     */
    function _addMember(uint256 poolId, Pool storage pool) internal {
        require(memberIndex[poolId][msg.sender] == 0 &&
                (poolMembers[poolId].length == 0 || poolMembers[poolId][0].wallet != msg.sender),
                "Already a member");

        uint256 requiredCollateral = pool.requiresCollateral ? pool.collateralAmount : 0;

        if (pool.requiresCollateral) {
            if (pool.paymentToken == address(0)) {
                require(msg.value >= requiredCollateral, "Insufficient collateral");
            } else {
                IERC20(pool.paymentToken).safeTransferFrom(msg.sender, address(this), requiredCollateral);
            }
        }

        Member memory newMember = Member({
            wallet: msg.sender,
            joinedRound: 0,
            payoutRound: 0,
            hasReceivedPayout: false,
            collateralDeposited: requiredCollateral,
            totalContributions: 0,
            missedContributions: 0
        });

        poolMembers[poolId].push(newMember);
        uint256 memberIdx = poolMembers[poolId].length - 1;
        memberIndex[poolId][msg.sender] = memberIdx + 1;

        emit MemberJoined(poolId, msg.sender, memberIdx);

        if (pool.requiresCollateral && requiredCollateral > 0) {
            emit CollateralDeposited(poolId, msg.sender, requiredCollateral);
        }

        if (poolMembers[poolId].length == pool.maxMembers) {
            _startPool(poolId);
        }
    }

    /**
     * @dev Return collateral to all pool members. Shared by _completePool and cancelPool.
     * @param poolId ID of the pool
     * @param pool Storage reference to the pool
     */
    function _returnAllCollateral(uint256 poolId, Pool storage pool) internal {
        if (!pool.requiresCollateral) return;

        for (uint256 i = 0; i < poolMembers[poolId].length; i++) {
            Member storage member = poolMembers[poolId][i];
            if (member.collateralDeposited > 0) {
                uint256 collateral = member.collateralDeposited;
                member.collateralDeposited = 0;
                if (pool.paymentToken == address(0)) {
                    (bool success, ) = payable(member.wallet).call{value: collateral}("");
                    require(success, "ETH transfer failed");
                } else {
                    IERC20(pool.paymentToken).safeTransfer(member.wallet, collateral);
                }
                emit CollateralReturned(poolId, member.wallet, collateral);
            }
        }
    }

    // Admin functions

    /**
     * @dev Set the yield strategy for earning on idle funds
     * @param _strategy Address of the yield strategy contract
     */
    function setYieldStrategy(address _strategy) external onlyOwner {
        address oldStrategy = address(yieldStrategy);
        yieldStrategy = IYieldStrategy(_strategy);
        emit YieldStrategyUpdated(oldStrategy, _strategy);
    }

    /**
     * @dev Cancel a pool (only owner or creator)
     * @param poolId ID of the pool to cancel
     * @param reason Reason for cancellation
     */
    function cancelPool(uint256 poolId, string calldata reason) external {
        Pool storage pool = pools[poolId];
        require(msg.sender == owner() || msg.sender == pool.creator, "Not authorized");
        require(pool.status == PoolStatus.Created || pool.status == PoolStatus.Active, "Cannot cancel");

        pool.status = PoolStatus.Cancelled;

        // Refund current round contributions
        if (pool.currentRound > 0) {
            Contribution[] storage roundContribs = poolContributions[poolId][pool.currentRound];
            for (uint256 i = 0; i < roundContribs.length; i++) {
                address contributor = roundContribs[i].member;
                uint256 refundAmount = roundContribs[i].amount;
                if (refundAmount > 0) {
                    if (pool.paymentToken == address(0)) {
                        (bool refundSuccess, ) = payable(contributor).call{value: refundAmount}("");
                        require(refundSuccess, "ETH transfer failed");
                    } else {
                        IERC20(pool.paymentToken).safeTransfer(contributor, refundAmount);
                    }
                    emit ContributionRefunded(poolId, contributor, refundAmount, pool.currentRound);
                }
            }
        }

        _returnAllCollateral(poolId, pool);

        emit PoolCancelled(poolId, reason);
    }

    /**
     * @dev Update platform treasury
     * @param newTreasury New treasury address
     */
    function setPlatformTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury");
        address oldTreasury = platformTreasury;
        platformTreasury = newTreasury;
        emit PlatformTreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @dev Update default platform fee
     * @param newFee New fee in basis points
     */
    function setDefaultPlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_PLATFORM_FEE, "Fee too high");
        uint256 oldFee = defaultPlatformFee;
        defaultPlatformFee = newFee;
        emit PlatformFeeUpdated(oldFee, newFee);
    }

    // View functions

    /**
     * @dev Get pool details
     * @param poolId ID of the pool
     * @return Pool struct
     */
    function getPool(uint256 poolId) external view returns (Pool memory) {
        return pools[poolId];
    }

    /**
     * @dev Get pool members
     * @param poolId ID of the pool
     * @return Array of Member structs
     */
    function getPoolMembers(uint256 poolId) external view returns (Member[] memory) {
        return poolMembers[poolId];
    }

    /**
     * @dev Get contributions for a specific round
     * @param poolId ID of the pool
     * @param round Round number
     * @return Array of Contribution structs
     */
    function getRoundContributions(uint256 poolId, uint256 round) external view returns (Contribution[] memory) {
        return poolContributions[poolId][round];
    }

    /**
     * @dev Get bids for a specific round
     * @param poolId ID of the pool
     * @param round Round number
     * @return Array of Bid structs
     */
    function getRoundBids(uint256 poolId, uint256 round) external view returns (Bid[] memory) {
        return poolBids[poolId][round];
    }

    /**
     * @dev Check if a member can contribute to current round
     * @param poolId ID of the pool
     * @param member Member address
     * @return canContribute Whether member can contribute
     */
    function canMemberContribute(uint256 poolId, address member) external view returns (bool canContribute) {
        Pool storage pool = pools[poolId];
        if (pool.status != PoolStatus.Active || !_isMember(poolId, member)) {
            return false;
        }

        if (_hasContributed(poolId, pool.currentRound, member)) {
            return false;
        }

        return block.timestamp < pool.nextRoundTimestamp;
    }

    /**
     * @dev Emergency function to recover stuck tokens.
     * Only callable when paused to prevent draining active pool funds.
     * @param token Token address (address(0) for native ETH)
     * @param amount Amount to recover
     */
    function emergencyRecover(address token, uint256 amount) external onlyOwner whenPaused {
        if (token == address(0)) {
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Decommission a pool when a round expires with missing contributions.
     * Permissionless — anyone can call. Refunds contributors, slashes non-contributor
     * collateral and distributes it proportionally to contributors, returns remaining
     * collateral to compliant members, and cancels the pool.
     * @param poolId ID of the pool to decommission
     */
    function decommission(uint256 poolId) external nonReentrant {
        Pool storage _pool = pools[poolId];
        require(_pool.status == PoolStatus.Active, "Pool not active");
        require(block.timestamp > _pool.nextRoundTimestamp, "Round not expired");

        uint256 currentRound = _pool.currentRound;
        uint256 numMembers = poolMembers[poolId].length;
        Contribution[] storage roundContribs = poolContributions[poolId][currentRound];
        uint256 numContributors = roundContribs.length;

        // Must have at least one non-contributor (otherwise all contributed and payout should trigger)
        require(numContributors < numMembers, "All members contributed");

        // Build a set of who contributed this round
        mapping(address => bool) storage _contributed = _roundContributorCheck[poolId][currentRound];
        for (uint256 i = 0; i < numContributors; i++) {
            _contributed[roundContribs[i].member] = true;
        }

        // Track slashed collateral total
        uint256 totalSlashed = 0;

        // Pass 1: Identify non-contributors, update missedContributions, slash collateral
        for (uint256 i = 0; i < numMembers; i++) {
            Member storage member = poolMembers[poolId][i];
            if (!_contributed[member.wallet]) {
                member.missedContributions++;
                emit MissedContribution(poolId, member.wallet, currentRound);

                // Slash collateral if pool requires it
                if (_pool.requiresCollateral && member.collateralDeposited > 0) {
                    totalSlashed += member.collateralDeposited;
                    emit CollateralSlashed(poolId, member.wallet, member.collateralDeposited);
                    member.collateralDeposited = 0;
                }
            }
        }

        // Pass 2: Refund contributions + distribute slashed collateral + return collateral
        for (uint256 i = 0; i < numMembers; i++) {
            Member storage member = poolMembers[poolId][i];
            if (_contributed[member.wallet]) {
                uint256 refund = _pool.contributionAmount;

                // Proportional share of slashed collateral
                uint256 slashShare = 0;
                if (totalSlashed > 0 && numContributors > 0) {
                    slashShare = totalSlashed / numContributors;
                }

                // Return own collateral
                uint256 collateralReturn = member.collateralDeposited;
                if (collateralReturn > 0) {
                    member.collateralDeposited = 0;
                    emit CollateralReturned(poolId, member.wallet, collateralReturn);
                }

                uint256 totalRefund = refund + slashShare + collateralReturn;
                if (totalRefund > 0) {
                    if (_pool.paymentToken == address(0)) {
                        (bool decommSuccess, ) = payable(member.wallet).call{value: totalRefund}("");
                        require(decommSuccess, "ETH transfer failed");
                    } else {
                        IERC20(_pool.paymentToken).safeTransfer(member.wallet, totalRefund);
                    }
                }
            }
        }

        // Calculate completed rounds (currentRound is 1-based, so rounds completed = currentRound - 1)
        uint256 completedRounds = currentRound > 1 ? currentRound - 1 : 0;

        _pool.status = PoolStatus.Cancelled;
        emit PoolDecommissioned(poolId, completedRounds, _pool.maxMembers);
    }

    // ---------------------------------------------------------------
    // UUPS upgrade authorization
    // ---------------------------------------------------------------

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ---------------------------------------------------------------
    // Storage gap for future upgrades
    // ---------------------------------------------------------------

    uint256[50] private __gap;
}
