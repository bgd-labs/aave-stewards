// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IERC20PredicateBurnOnly
/// @notice Defines the behavior of a IERC20PredicateBurnOnly
interface IERC20PredicateBurnOnly {
  /// @dev Function needs to be called in order to confirm a withdrawal
  /// @param data The generated proof to confirm a withdrawal transaction
  function startExitWithBurntTokens(bytes calldata data) external;
}
