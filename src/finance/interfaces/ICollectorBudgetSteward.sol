// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {IPool} from "aave-address-book/AaveV3.sol";
import {ILendingPool} from "aave-address-book/AaveV2.sol";

interface ICollectorBudgetSteward {
  /// @dev Amount cannot be zero
  error InvalidZeroAmount();

  /// @dev Address has not been previously approved as transfer recipient
  error UnrecognizedReceiver();

  /// @dev Transfer amount exceeds available balance
  error ExceedsBalance();

  /// @dev Transfer amount exceeds allowed budget for token
  /// @param remainingBudget The remaining budget left for the token
  error ExceedsBudget(uint256 remainingBudget);

  /// @notice Emitted when the budget for a token is updated
  /// @param token The address of the token
  /// @param newAmount The new budget amount
  event BudgetUpdate(address indexed token, uint256 newAmount);

  /// @notice Emitted when an address is whitelisted as a receiver for transfers
  /// @param receiver The address that has been whitelisted
  event ReceiverWhitelisted(address indexed receiver);

  /// @notice Returns instance of Aave V3 Collector
  function COLLECTOR() external view returns (ICollector);

  /// @notice Returns whether receiver is approved to be transferred funds
  /// @param receiver Address of the user to receive funds
  function transferApprovedReceiver(address receiver) external view returns (bool);

  /// @notice Returns remaining budget for FinanceSteward to use with respective token
  /// @param token Address of the token to swap/transfer
  function tokenBudget(address token) external view returns (uint256);

  /// @notice Transfers a specified amount of a token to a recipient
  /// @param token The address of the token to transfer
  /// @param to The address of the recipient
  /// @param amount The amount of the token to transfer
  function transfer(address token, address to, uint256 amount) external;

  /// @notice Increases the budget for a specified token by a specified amount
  /// @param token The address of the token
  /// @param amount The amount to increase the budget by
  function increaseBudget(address token, uint256 amount) external;

  /// @notice Decreases the budget for a specified token by a specified amount
  /// @param token The address of the token
  /// @param amount The amount to decrease the budget by
  function decreaseBudget(address token, uint256 amount) external;

  /// @notice Sets an address as a whitelisted receiver for transfers
  /// @param to The address to whitelist
  function setWhitelistedReceiver(address to) external;
}
