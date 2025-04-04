// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "aave-address-book/AaveV3.sol";

import {IRescuableBase} from "solidity-utils/contracts/utils/interfaces/IRescuableBase.sol";

import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

interface IClinicSteward is IRescuableBase, IAccessControl {
  /* ERRORS */

  /// @notice Thrown when passed address is zero
  error ZeroAddress();

  /// @notice Thrown when an attempt is made to pull more funds (in dollar value) than the available budget allows.
  /// @param asset The asset being pulled.
  /// @param assetAmount The amount of the asset being pulled.
  /// @param dollarAmount The equivalent dollar value of the assetAmount.
  /// @param availableBudget The available budget.
  error AvailableBudgetExceeded(address asset, uint256 assetAmount, uint256 dollarAmount, uint256 availableBudget);

  /* EVENTS */

  /// @notice Emitted when the available budget is changed.
  /// @param oldValue The previous available budget.
  /// @param newValue The new available budget.
  event AvailableBudgetChanged(uint256 oldValue, uint256 newValue);

  /* GLOBAL VARIABLES */

  /// @notice The role that allows to call the `batchLiquidate` and `batchRepayBadDebt` functions
  function CLEANUP_ROLE() external view returns (bytes32);

  /// @notice The Aave pool
  function POOL() external view returns (IPool);

  /// @notice The Aave collector
  function COLLECTOR() external view returns (address);

  /// @notice The Aave oracle
  function ORACLE() external view returns (address);

  /// @notice The available budget for the contract, in dollar value (8 decimals).
  function availableBudget() external view returns (uint256);

  /* EXTERNAL FUNCTIONS */

  /// @notice Liquidates all the users with a max debt amount to be liquidated
  /// @param debtAsset The address of the debt asset
  /// @param collateralAsset The address of the collateral asset that will be liquidated
  /// @param users The addresses of the users to liquidate
  /// @param useATokens If true the token will pull aTokens from the collector.
  ///                   If false it will pull the underlying.
  function batchLiquidate(address debtAsset, address collateralAsset, address[] memory users, bool useATokens) external;

  /// @notice Repays all the bad debt of users
  /// @dev Will revert if the user has a collateral or no debt.
  ///      Repayed amount is pulled from the Aave collector. The contract sends
  ///      any surplus back to the collector.
  /// @param asset The address of an asset to repay
  /// @param users The addresses of users to repay
  /// @param useATokens If true the token will pull aTokens from the collector.
  ///                   If false it will pull the underlying.
  function batchRepayBadDebt(address asset, address[] calldata users, bool useATokens) external;

  /// @notice Sets the available budget for the contract.
  /// @param newAvailableBudget The new available budget, in dollar value (with 8 decimals).
  function setAvailableBudget(uint256 newAvailableBudget) external;

  /// @notice Rescues the tokens
  /// @param token The address of the token to rescue
  function rescueToken(address token) external;

  /// @notice Rescues the ETH
  function rescueEth() external;

  /// @notice Infinite approves an asset to the pool
  function renewAllowance(address asset) external;

  /* EXTERNAL VIEW FUNCTIONS */

  /// @notice Returns the total debt amount and the debt amounts of users
  /// @param asset The address of the asset to repay
  /// @param users The addresses of the users to repay
  /// @return totalDebtAmount The total debt amount
  /// @return debtAmounts The debt amounts of the users
  function getDebtAmount(address asset, address[] memory users)
    external
    view
    returns (uint256 totalDebtAmount, uint256[] memory debtAmounts);

  /// @notice Returns the total bad debt amount and the debt amounts of users
  /// @dev Will revert if the user has a collateral or no debt.
  /// @param asset The address of the asset to repay
  /// @param users The addresses of the users to repay
  /// @return totalDebtAmount The total debt amount
  /// @return debtAmounts The debt amounts of the users
  function getBadDebtAmount(address asset, address[] memory users)
    external
    view
    returns (uint256 totalDebtAmount, uint256[] memory debtAmounts);
}
