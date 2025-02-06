// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "aave-address-book/AaveV3.sol";

import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IRescuableBase} from "solidity-utils/contracts/utils/interfaces/IRescuableBase.sol";

import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

interface IBatchRepayBadDebtSteward is IRescuableBase, IWithGuardian, IAccessControl {
  /* ERRORS */

  /// @notice Thrown when a user has some collateral
  /// @param user The address of the user
  error UserHasSomeCollateral(address user);

  /// @notice Thrown when an array contains two users with the same address
  /// @param user The address of the user
  error UsersShouldBeDifferent(address user);

  error ZeroAddress();

  /* GLOBAL VARIABLES */

  /// @notice The role that allows to call the `batchLiquidate` and `batchRepayBadDebt` functions
  function CLEANUP() external view returns (bytes32);

  /// @notice The Aave pool
  function POOL() external view returns (IPool);

  /// @notice The Aave collector
  function COLLECTOR() external view returns (address);

  /* EXTERNAL FUNCTIONS */

  /// @notice Liquidates all the users
  /// @param debtAsset The address of the debt asset
  /// @param collateralAsset The address of the collateral asset that will be liquidated
  /// @param users The addresses of the users to liquidate
  function batchLiquidate(address debtAsset, address collateralAsset, address[] memory users) external;

  /// @notice Liquidates all the users with a max debt amount to be liquidated
  /// @param debtAsset The address of the debt asset
  /// @param collateralAsset The address of the collateral asset that will be liquidated
  /// @param users The addresses of the users to liquidate
  /// @param maxDebtTokenAmount The maximum amount of debt tokens to be liquidated
  /// @dev this is the amount being pulled from the collector. The contract will send the surplus back to the collector.
  function batchLiquidateWithMaxCap(
    address debtAsset,
    address collateralAsset,
    address[] memory users,
    uint256 maxDebtTokenAmount
  ) external;

  /// @notice Repays all the bad debt of the users
  /// @dev Will fail if the user has some collateral or no debt
  /// @param asset The address of the asset to repay
  /// @param users The addresses of the users to repay
  function batchRepayBadDebt(address asset, address[] calldata users) external;

  /// @notice Rescues the tokens
  /// @param token The address of the token to rescue
  function rescueToken(address token) external;

  /// @notice Rescues the ETH
  function rescueEth() external;

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
