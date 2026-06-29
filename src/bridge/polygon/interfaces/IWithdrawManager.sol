// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IWithdrawManager
/// @notice Defines the behaviour of a IWithdrawManager
interface IWithdrawManager {
  /// @dev Last step in exiting a token bridge
  /// @param _token Address of the token being withdrawn
  function processExits(address _token) external;
}
