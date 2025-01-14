// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "aave-address-book/AaveV3.sol";

interface IBatchRepayBadDebtSteward {
  /* EVENTS */

  /// @notice Emitted when a user has been repaid his bad debt
  /// @param user The address of the user
  /// @param asset The address of the asset
  /// @param amount The amount repaid
  event UserBadDebtRepaid(address indexed user, address indexed asset, uint256 amount);

  /* ERRORS */

  /// @notice Thrown when a user has some collateral
  /// @param user The address of the user
  error UserHasSomeCollateral(address user);

  /// @notice Thrown when a user has no debt
  /// @param user The address of the user
  error UserHasNoDebt(address user);

  /// @notice Thrown when an array contains two users with the same address
  /// @param user The address of the user
  error UsersShouldBeDifferent(address user);

  /* GLOBAL VARIABLES */

  /// @notice The Aave pool
  function POOL() external view returns (IPool);

  /* EXTERNAL FUNCTIONS */

  /// @notice Repays all the bad debt of the users
  /// @dev Will fail if the user has some collateral or no debt
  /// @param asset The address of the asset to repay
  /// @param users The addresses of the users to repay
  function batchRepayBadDebt(address asset, address[] calldata users) external;

  /* EXTERNAL VIEW FUNCTIONS */

  /// @notice Returns the total bad debt amount and the debt amounts of users
  /// @dev Will fail if the user has some collateral or no debt
  /// @param asset The address of the asset to repay
  /// @param users The addresses of the users to repay
  /// @return totalDebtAmount The total debt amount
  /// @return debtAmounts The debt amounts of the users
  function getBadDebtAmount(address asset, address[] memory users)
    external
    view
    returns (uint256 totalDebtAmount, uint256[] memory debtAmounts);
}
