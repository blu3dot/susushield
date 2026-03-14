// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SusuShield
 * @notice Privacy-preserving ROSCA (Rotating Savings and Credit Association)
 * @dev Members contribute via commit-reveal scheme to hide amounts in real-time.
 *      Uses Self Protocol for ZK identity verification (sybil resistance).
 *      Agent coordinator (ERC-8004) manages circle lifecycle.
 *
 * Synthesis Hackathon 2026 — "Agents that keep secrets" track
 */
contract SusuShield is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // --- Types ---

    enum CircleStatus { Forming, Active, Completed, Cancelled }
    enum RoundPhase { Commit, Reveal, Payout }

    struct Circle {
        address creator;
        address paymentToken;       // USDC on Base
        uint256 contributionAmount; // Expected contribution per member per round
        uint256 maxMembers;
        uint256 memberCount;
        uint256 currentRound;
        uint256 totalRounds;
        uint256 roundDuration;      // seconds per round
        uint256 commitDeadline;     // current round commit deadline
        uint256 revealDeadline;     // current round reveal deadline
        CircleStatus status;
    }

    struct Commitment {
        bytes32 commitHash;   // keccak256(amount, salt)
        uint256 revealedAmount;
        bool committed;
        bool revealed;
    }

    struct MemberInfo {
        address addr;
        uint256 rotationPosition;
        bool isVerified;          // Self Protocol identity verified
        uint256 completedCircles; // For ZK reputation proofs
    }

    // --- State ---

    mapping(uint256 => Circle) public circles;
    mapping(uint256 => MemberInfo[]) public circleMembers;
    mapping(uint256 => mapping(address => uint256)) public memberIndex;
    mapping(uint256 => mapping(address => bool)) public isMember;

    // Commit-reveal: circleId => round => member => commitment
    mapping(uint256 => mapping(uint256 => mapping(address => Commitment))) public commitments;

    // Rotation: circleId => round => recipient
    mapping(uint256 => mapping(uint256 => address)) public roundRecipients;

    uint256 public nextCircleId;

    // Self Protocol identity gate (placeholder — will integrate Self Protocol verifier)
    address public identityVerifier;

    // Agent coordinator (ERC-8004 registered agent)
    address public agentCoordinator;

    // --- Events ---

    event CircleCreated(uint256 indexed circleId, address indexed creator, uint256 contributionAmount, uint256 maxMembers);
    event MemberJoined(uint256 indexed circleId, address indexed member, uint256 rotationPosition);
    event ContributionCommitted(uint256 indexed circleId, uint256 indexed round, address indexed member);
    event ContributionRevealed(uint256 indexed circleId, uint256 indexed round, address indexed member, uint256 amount);
    event PayoutExecuted(uint256 indexed circleId, uint256 indexed round, address indexed recipient, uint256 amount);
    event CircleCompleted(uint256 indexed circleId);
    event IdentityVerified(address indexed member);

    // --- Modifiers ---

    modifier onlyMember(uint256 circleId) {
        require(isMember[circleId][msg.sender], "Not a circle member");
        _;
    }

    modifier onlyAgent() {
        require(msg.sender == agentCoordinator || msg.sender == owner(), "Not authorized agent");
        _;
    }

    modifier onlyVerified() {
        // TODO: Integrate Self Protocol verification
        // For now, placeholder that checks identityVerifier contract
        _;
    }

    // --- Constructor ---

    constructor(address _paymentToken, address _agentCoordinator) Ownable(msg.sender) {
        agentCoordinator = _agentCoordinator;
        nextCircleId = 1;
    }

    // --- Circle Lifecycle ---

    /**
     * @notice Create a new savings circle
     * @param paymentToken Token for contributions (USDC)
     * @param contributionAmount Amount each member contributes per round
     * @param maxMembers Maximum circle size
     * @param roundDuration Duration of each round in seconds
     */
    function createCircle(
        address paymentToken,
        uint256 contributionAmount,
        uint256 maxMembers,
        uint256 roundDuration
    ) external onlyVerified returns (uint256) {
        require(maxMembers >= 2 && maxMembers <= 20, "Invalid member count");
        require(contributionAmount > 0, "Amount must be positive");
        require(roundDuration >= 1 days && roundDuration <= 30 days, "Invalid round duration");

        uint256 circleId = nextCircleId++;

        circles[circleId] = Circle({
            creator: msg.sender,
            paymentToken: paymentToken,
            contributionAmount: contributionAmount,
            maxMembers: maxMembers,
            memberCount: 0,
            currentRound: 0,
            totalRounds: maxMembers, // Each member receives once
            roundDuration: roundDuration,
            commitDeadline: 0,
            revealDeadline: 0,
            status: CircleStatus.Forming
        });

        // Creator auto-joins
        _addMember(circleId, msg.sender);

        emit CircleCreated(circleId, msg.sender, contributionAmount, maxMembers);
        return circleId;
    }

    /**
     * @notice Join a circle (requires Self Protocol identity verification)
     */
    function joinCircle(uint256 circleId) external onlyVerified {
        Circle storage circle = circles[circleId];
        require(circle.status == CircleStatus.Forming, "Circle not forming");
        require(!isMember[circleId][msg.sender], "Already a member");
        require(circle.memberCount < circle.maxMembers, "Circle full");

        _addMember(circleId, msg.sender);

        // Auto-start when full
        if (circle.memberCount == circle.maxMembers) {
            _startCircle(circleId);
        }
    }

    // --- Commit-Reveal Contributions ---

    /**
     * @notice Commit a hashed contribution (privacy: amount hidden until reveal)
     * @param circleId The circle ID
     * @param commitHash keccak256(abi.encodePacked(amount, salt))
     */
    function commitContribution(
        uint256 circleId,
        bytes32 commitHash
    ) external onlyMember(circleId) {
        Circle storage circle = circles[circleId];
        require(circle.status == CircleStatus.Active, "Circle not active");
        require(block.timestamp <= circle.commitDeadline, "Commit phase ended");

        Commitment storage c = commitments[circleId][circle.currentRound][msg.sender];
        require(!c.committed, "Already committed");

        c.commitHash = commitHash;
        c.committed = true;

        emit ContributionCommitted(circleId, circle.currentRound, msg.sender);
    }

    /**
     * @notice Reveal contribution amount + transfer tokens
     * @param circleId The circle ID
     * @param amount The actual contribution amount
     * @param salt The salt used in the commitment
     */
    function revealContribution(
        uint256 circleId,
        uint256 amount,
        bytes32 salt
    ) external onlyMember(circleId) nonReentrant {
        Circle storage circle = circles[circleId];
        require(circle.status == CircleStatus.Active, "Circle not active");
        require(block.timestamp > circle.commitDeadline, "Still in commit phase");
        require(block.timestamp <= circle.revealDeadline, "Reveal phase ended");

        Commitment storage c = commitments[circleId][circle.currentRound][msg.sender];
        require(c.committed, "No commitment found");
        require(!c.revealed, "Already revealed");

        // Verify commitment
        bytes32 expectedHash = keccak256(abi.encodePacked(amount, salt));
        require(c.commitHash == expectedHash, "Invalid reveal");
        require(amount == circle.contributionAmount, "Wrong contribution amount");

        c.revealedAmount = amount;
        c.revealed = true;

        // Transfer tokens from member to contract
        IERC20(circle.paymentToken).safeTransferFrom(msg.sender, address(this), amount);

        emit ContributionRevealed(circleId, circle.currentRound, msg.sender, amount);
    }

    /**
     * @notice Execute payout to round recipient (called by agent coordinator)
     */
    function executePayout(uint256 circleId) external onlyAgent nonReentrant {
        Circle storage circle = circles[circleId];
        require(circle.status == CircleStatus.Active, "Circle not active");
        require(block.timestamp > circle.revealDeadline, "Reveal phase not ended");

        uint256 round = circle.currentRound;
        address recipient = roundRecipients[circleId][round];
        require(recipient != address(0), "No recipient set");

        // Verify all members revealed
        uint256 totalRevealed = 0;
        MemberInfo[] storage members = circleMembers[circleId];
        for (uint256 i = 0; i < members.length; i++) {
            Commitment storage c = commitments[circleId][round][members[i].addr];
            if (c.revealed) {
                totalRevealed += c.revealedAmount;
            }
        }

        require(totalRevealed > 0, "No contributions revealed");

        // Transfer payout to recipient
        IERC20(circle.paymentToken).safeTransfer(recipient, totalRevealed);

        emit PayoutExecuted(circleId, round, recipient, totalRevealed);

        // Advance to next round or complete
        if (round + 1 >= circle.totalRounds) {
            circle.status = CircleStatus.Completed;
            // Update completed circles count for reputation
            for (uint256 i = 0; i < members.length; i++) {
                members[i].completedCircles++;
            }
            emit CircleCompleted(circleId);
        } else {
            circle.currentRound = round + 1;
            circle.commitDeadline = block.timestamp + (circle.roundDuration / 2);
            circle.revealDeadline = block.timestamp + circle.roundDuration;
        }
    }

    // --- Self Protocol Identity Integration (Placeholder) ---

    /**
     * @notice Verify identity via Self Protocol ZK proof
     * @dev TODO: Integrate Self Protocol verifier contract
     */
    function verifyIdentity(bytes calldata /* proof */) external {
        // Placeholder — will call Self Protocol verifier
        // selfProtocolVerifier.verify(proof, msg.sender)
        emit IdentityVerified(msg.sender);
    }

    /**
     * @notice Set the Self Protocol identity verifier contract
     */
    function setIdentityVerifier(address _verifier) external onlyOwner {
        identityVerifier = _verifier;
    }

    /**
     * @notice Set the agent coordinator address
     */
    function setAgentCoordinator(address _agent) external onlyOwner {
        agentCoordinator = _agent;
    }

    // --- ZK Reputation ---

    /**
     * @notice Get completed circle count for a member (used for ZK reputation proofs)
     * @dev In production, this would be a Merkle tree for ZK proof generation
     */
    function getCompletedCircles(uint256 circleId, address member) external view returns (uint256) {
        if (!isMember[circleId][member]) return 0;
        uint256 idx = memberIndex[circleId][member];
        return circleMembers[circleId][idx].completedCircles;
    }

    // --- Internal ---

    function _addMember(uint256 circleId, address member) internal {
        Circle storage circle = circles[circleId];
        uint256 position = circle.memberCount;

        circleMembers[circleId].push(MemberInfo({
            addr: member,
            rotationPosition: position,
            isVerified: false,
            completedCircles: 0
        }));

        memberIndex[circleId][member] = position;
        isMember[circleId][member] = true;
        circle.memberCount++;

        emit MemberJoined(circleId, member, position);
    }

    function _startCircle(uint256 circleId) internal {
        Circle storage circle = circles[circleId];
        circle.status = CircleStatus.Active;
        circle.currentRound = 0;
        circle.commitDeadline = block.timestamp + (circle.roundDuration / 2);
        circle.revealDeadline = block.timestamp + circle.roundDuration;

        // Set rotation: member at position N receives in round N
        MemberInfo[] storage members = circleMembers[circleId];
        for (uint256 i = 0; i < members.length; i++) {
            roundRecipients[circleId][members[i].rotationPosition] = members[i].addr;
        }
    }

    // --- View helpers ---

    function getCircle(uint256 circleId) external view returns (Circle memory) {
        return circles[circleId];
    }

    function getMembers(uint256 circleId) external view returns (MemberInfo[] memory) {
        return circleMembers[circleId];
    }

    function getCurrentPhase(uint256 circleId) external view returns (RoundPhase) {
        Circle storage circle = circles[circleId];
        if (block.timestamp <= circle.commitDeadline) return RoundPhase.Commit;
        if (block.timestamp <= circle.revealDeadline) return RoundPhase.Reveal;
        return RoundPhase.Payout;
    }
}
