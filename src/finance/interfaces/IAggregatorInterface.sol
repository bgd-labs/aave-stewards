// SPDX-License-Identifier: MIT
// Chainlink Contracts v0.8

pragma solidity ^0.8.0;

interface IAggregatorInterface {
  function decimals() external view returns (uint8);

  function latestAnswer() external view returns (int256);

  function latestTimestamp() external view returns (uint256);

  function latestRound() external view returns (uint256);

  function getAnswer(uint256 roundId) external view returns (int256);

  function getTimestamp(uint256 roundId) external view returns (uint256);
}
