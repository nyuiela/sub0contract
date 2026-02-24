// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from
    "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 private _decimals;
    string private _description;
    uint256 private _version;
    int256 private _latestAnswer;
    uint80 private _latestRoundId;
    uint256 private _latestStartedAt;
    uint256 private _latestUpdatedAt;
    uint80 private _latestAnsweredInRound;

    mapping(uint80 => RoundData) private _roundData;

    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    constructor(uint8 decimals_, string memory description_, uint256 version_) {
        _decimals = decimals_;
        _description = description_;
        _version = version_;
        _latestRoundId = 1;
        _latestStartedAt = block.timestamp;
        _latestUpdatedAt = block.timestamp;
        _latestAnsweredInRound = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external view override returns (uint256) {
        return _version;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory data = _roundData[_roundId];
        if (data.roundId == 0 && _roundId == _latestRoundId) {
            return (_latestRoundId, _latestAnswer, _latestStartedAt, _latestUpdatedAt, _latestAnsweredInRound);
        }
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_latestRoundId, _latestAnswer, _latestStartedAt, _latestUpdatedAt, _latestAnsweredInRound);
    }

    function setLatestAnswer(int256 answer) external {
        _latestAnswer = answer;
        _latestUpdatedAt = block.timestamp;
        _latestRoundId++;
        _latestAnsweredInRound = _latestRoundId;
    }

    function setRoundData(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
        external
    {
        _roundData[roundId] = RoundData({
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound
        });
    }

    function updateRoundData(uint80 roundId, int256 answer, uint256 updatedAt) external {
        RoundData storage data = _roundData[roundId];
        require(data.roundId != 0, "Round does not exist");
        data.answer = answer;
        data.updatedAt = updatedAt;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setDescription(string memory description_) external {
        _description = description_;
    }

    function setVersion(uint256 version_) external {
        _version = version_;
    }
}
