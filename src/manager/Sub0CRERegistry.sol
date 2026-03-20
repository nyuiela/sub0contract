// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Sub0CRERegistry
 * @notice Lightweight on-chain registry for CRE workflow proof records.
 *
 * Records cryptographic proofs produced inside Chainlink CRE TEE enclaves:
 * - Agent strategy evolution proofs (private RL improvement)
 * - Confidential debate proofs (multi-agent consensus with provenance)
 * - Compliance events (ACE guard decisions)
 * - Live data registry timestamps (DataStreamsRegistry freshness)
 *
 * All write methods are gated by the `onlyAuthorized` modifier.
 * The authorized caller is the backend relay (sub0server) which receives
 * the proof from the CRE workflow and forwards it here.
 *
 * Events emitted by this contract can be used as EVM_LOG triggers for
 * downstream CRE workflows.
 */
contract Sub0CRERegistry {
    address public owner;
    mapping(address => bool) public authorized;

    // ─── Evolution Proofs ─────────────────────────────────────────────────────

    struct EvolutionRecord {
        bytes32 agentHash;
        bytes32 strategyHash;
        uint256 scoreGain;
        uint256 timestamp;
    }

    mapping(bytes32 => EvolutionRecord) public evolutionProofs;
    bytes32[] public evolutionProofKeys;

    event EvolutionProofRecorded(
        bytes32 indexed agentHash,
        bytes32 indexed strategyHash,
        uint256 scoreGain,
        uint256 timestamp
    );

    // ─── Debate Proofs ────────────────────────────────────────────────────────

    struct DebateRecord {
        bytes32 marketHash;
        bytes32 proofHash;
        string provenanceURI;
        uint256 timestamp;
    }

    mapping(bytes32 => DebateRecord) public debateProofs;
    bytes32[] public debateProofKeys;

    event DebateProofRecorded(
        bytes32 indexed marketHash,
        bytes32 indexed proofHash,
        string provenanceURI,
        uint256 timestamp
    );

    // ─── Compliance Events ────────────────────────────────────────────────────

    struct ComplianceRecord {
        address wallet;
        bool allowed;
        string reason;
        uint256 timestamp;
    }

    ComplianceRecord[] public complianceEvents;

    event ComplianceEventRecorded(
        address indexed wallet,
        bool allowed,
        string reason,
        uint256 timestamp
    );

    // ─── Live Registry ────────────────────────────────────────────────────────

    struct RegistrySnapshot {
        bytes data;
        uint256 timestamp;
    }

    RegistrySnapshot public latestRegistrySnapshot;

    event LiveRegistryUpdated(uint256 timestamp, uint256 dataLength);

    // ─── Auth ─────────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "Sub0CRERegistry: not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorized[msg.sender] || msg.sender == owner, "Sub0CRERegistry: not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
        authorized[msg.sender] = true;
    }

    function setAuthorized(address caller, bool status) external onlyOwner {
        authorized[caller] = status;
    }

    // ─── Write Methods ────────────────────────────────────────────────────────

    /**
     * @notice Record an agent strategy evolution proof from the CRE TEE enclave.
     * @param agentHash    keccak256 of the agent ID
     * @param strategyHash keccak256 of the evolved strategy fingerprint
     * @param scoreGain    strategy score improvement * 1e6 (fixed-point)
     */
    function recordEvolutionProof(
        bytes32 agentHash,
        bytes32 strategyHash,
        uint256 scoreGain
    ) external onlyAuthorized {
        EvolutionRecord memory record = EvolutionRecord({
            agentHash: agentHash,
            strategyHash: strategyHash,
            scoreGain: scoreGain,
            timestamp: block.timestamp
        });
        bytes32 key = keccak256(abi.encodePacked(agentHash, strategyHash, block.timestamp));
        evolutionProofs[key] = record;
        evolutionProofKeys.push(key);
        emit EvolutionProofRecorded(agentHash, strategyHash, scoreGain, block.timestamp);
    }

    /**
     * @notice Record a confidential debate proof from the CRE TEE enclave.
     * @param marketHash    keccak256 of the market ID
     * @param proofHash     debate outcome proof hash from the TEE
     * @param provenanceURI IPFS-style URI pointing to the sealed debate transcript
     */
    function recordDebateProof(
        bytes32 marketHash,
        bytes32 proofHash,
        string calldata provenanceURI
    ) external onlyAuthorized {
        DebateRecord memory record = DebateRecord({
            marketHash: marketHash,
            proofHash: proofHash,
            provenanceURI: provenanceURI,
            timestamp: block.timestamp
        });
        debateProofs[marketHash] = record;
        debateProofKeys.push(marketHash);
        emit DebateProofRecorded(marketHash, proofHash, provenanceURI, block.timestamp);
    }

    /**
     * @notice Record an ACE compliance decision from the CRE compliance guard.
     * @param wallet  agent wallet address that was checked
     * @param allowed whether the action was permitted
     * @param reason  short reason string
     */
    function recordComplianceEvent(
        address wallet,
        bool allowed,
        string calldata reason
    ) external onlyAuthorized {
        complianceEvents.push(ComplianceRecord({
            wallet: wallet,
            allowed: allowed,
            reason: reason,
            timestamp: block.timestamp
        }));
        emit ComplianceEventRecorded(wallet, allowed, reason, block.timestamp);
    }

    /**
     * @notice Update the live data registry snapshot from DataStreamsRegistry workflow.
     * @param data      ABI-encoded macro snapshot bytes
     * @param timestamp UNIX timestamp when data was fetched
     */
    function updateLiveRegistry(
        bytes calldata data,
        uint256 timestamp
    ) external onlyAuthorized {
        latestRegistrySnapshot = RegistrySnapshot({ data: data, timestamp: timestamp });
        emit LiveRegistryUpdated(timestamp, data.length);
    }

    // ─── Read Helpers ─────────────────────────────────────────────────────────

    function evolutionProofCount() external view returns (uint256) {
        return evolutionProofKeys.length;
    }

    function debateProofCount() external view returns (uint256) {
        return debateProofKeys.length;
    }

    function complianceEventCount() external view returns (uint256) {
        return complianceEvents.length;
    }

    function getLatestRegistryTimestamp() external view returns (uint256) {
        return latestRegistrySnapshot.timestamp;
    }
}
