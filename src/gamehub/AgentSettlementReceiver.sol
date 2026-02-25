// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReceiverTemplate} from "../interfaces/ReceiverTemplate.sol";
import {ISub0Settlement} from "../interfaces/ISub0Settlement.sol";

/**
 * @title AgentSettlementReceiver
 * @notice CRE receiver for agent settlement: decodes report (questionId, payouts) and calls Sub0.resolve.
 * @dev Deploy this contract, set it as the oracle for agent-settled markets, and set CRE forwarder.
 *      Report = abi.encode(bytes32 questionId, uint256[] payouts).
 */
contract AgentSettlementReceiver is Initializable, ReceiverTemplate {
    ISub0Settlement private s_sub0;

    error ZeroSub0();

    event SettlementResolved(bytes32 indexed questionId, uint256[] payouts);

    /// @param _owner Owner (e.g. protocol)
    /// @param _forwarder CRE forwarder address (only this can call onReport)
    /// @param _sub0 Sub0 contract address
    function initialize(
        address _owner,
        address _forwarder,
        address _sub0
    ) external initializer {
        if (_sub0 == address(0)) revert ZeroSub0();
        __ReceiverTemplate_init(_owner, _forwarder);
        s_sub0 = ISub0Settlement(_sub0);
    }

    function getSub0() external view returns (address) {
        return address(s_sub0);
    }

    /// @inheritdoc ReceiverTemplate
    /// @dev Report = abi.encode(bytes32 questionId, uint256[] payouts). If CRE sends selector+payload (report.length > 4), decode from byte 4.
    function _processReport(bytes calldata report) internal override {
        bytes calldata payload = report.length > 4 ? report[4:] : report;
        (bytes32 questionId, uint256[] memory payouts) = abi.decode(payload, (bytes32, uint256[]));
        s_sub0.resolve(questionId, payouts);
        emit SettlementResolved(questionId, payouts);
    }
}
