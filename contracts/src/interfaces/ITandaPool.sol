// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITandaPool {
    // Enums
    enum PoolStatus { Created, Active, Completed, Cancelled }
    enum PayoutMethod { Sequential, Lottery, Bidding }

    // Structs
    struct Pool {
        uint256 id;
        address creator;
        address paymentToken;
        uint256 contributionAmount;
        uint256 maxMembers;
        uint256 currentRound;
        uint256 roundDuration;
        uint256 nextRoundTimestamp;
        PoolStatus status;
        PayoutMethod payoutMethod;
        bool requiresCollateral;
        uint256 collateralAmount;
        uint256 platformFee;
        string metadata;
    }

    struct Member {
        address wallet;
        uint256 joinedRound;
        uint256 payoutRound;
        bool hasReceivedPayout;
        uint256 collateralDeposited;
        uint256 totalContributions;
        uint256 missedContributions;
    }

    struct Contribution {
        address member;
        uint256 amount;
        uint256 timestamp;
        uint256 round;
    }

    struct Bid {
        address bidder;
        uint256 amount;
        uint256 round;
        uint256 timestamp;
    }

    // Events
    event PoolCreated(uint256 indexed poolId, address indexed creator, uint256 contributionAmount, uint256 maxMembers, PayoutMethod payoutMethod);
    event MemberJoined(uint256 indexed poolId, address indexed member, uint256 memberIndex);
    event ContributionMade(uint256 indexed poolId, address indexed member, uint256 amount, uint256 round);
    event PayoutDistributed(uint256 indexed poolId, address indexed recipient, uint256 amount, uint256 round);
    event PoolCompleted(uint256 indexed poolId);
    event PoolCancelled(uint256 indexed poolId, string reason);
    event BidPlaced(uint256 indexed poolId, address indexed bidder, uint256 bidAmount, uint256 round);
    event CollateralDeposited(uint256 indexed poolId, address indexed member, uint256 amount);
    event CollateralReturned(uint256 indexed poolId, address indexed member, uint256 amount);
    event InviteRedeemed(uint256 indexed poolId, address indexed invitee, address indexed inviter);
    event PoolDecommissioned(uint256 indexed poolId, uint256 completedRounds, uint256 totalRounds);
    event CollateralSlashed(uint256 indexed poolId, address indexed member, uint256 amount);
    event MissedContribution(uint256 indexed poolId, address indexed member, uint256 round);
    event YieldDeposited(uint256 indexed poolId, uint256 amount);
    event YieldWithdrawn(uint256 indexed poolId, uint256 amount, uint256 yieldEarned);
    event YieldStrategyUpdated(address indexed oldStrategy, address indexed newStrategy);
    event PlatformTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event ContributionRefunded(uint256 indexed poolId, address indexed member, uint256 amount, uint256 round);

    // Errors
    error InvalidContributionAmount();
    error InvalidMemberCount();
    error InvalidRoundDuration();
    error InvalidCollateralAmount();
    error PoolNotAcceptingMembers();
    error PoolFull();
    error AlreadyMember();
    error InsufficientCollateral();
    error PoolNotActive();
    error NotPoolMember();
    error RoundEnded();
    error AlreadyContributed();
    error InsufficientPayment();
    error NotBiddingPool();
    error AlreadyReceivedPayout();
    error NotAuthorized();
    error CannotCancel();
    error InvalidSignature();
    error InviteAlreadyUsed();
    error InviteExpired();
    error RoundNotExpired();
    error AllMembersContributed();
    error PoolNotDecommissionable();

    // External functions
    function createPool(address paymentToken, uint256 contributionAmount, uint256 maxMembers, uint256 roundDuration, PayoutMethod payoutMethod, bool requiresCollateral, uint256 collateralAmount, string calldata metadata) external returns (uint256 poolId);
    function joinPool(uint256 poolId) external payable;
    function contribute(uint256 poolId) external payable;
    function placeBid(uint256 poolId, uint256 bidAmount) external;
    function cancelPool(uint256 poolId, string calldata reason) external;
    function redeemInvite(uint256 poolId, uint256 nonce, uint256 deadline, bytes calldata signature) external payable;
    function decommission(uint256 poolId) external;

    // View functions
    function getPool(uint256 poolId) external view returns (Pool memory);
    function getPoolMembers(uint256 poolId) external view returns (Member[] memory);
    function getRoundContributions(uint256 poolId, uint256 round) external view returns (Contribution[] memory);
    function getRoundBids(uint256 poolId, uint256 round) external view returns (Bid[] memory);
    function canMemberContribute(uint256 poolId, address member) external view returns (bool);
}
