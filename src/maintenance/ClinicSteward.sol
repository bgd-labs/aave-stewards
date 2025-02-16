// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool, DataTypes} from "aave-address-book/AaveV3.sol";

import {UserConfiguration} from "aave-v3-origin/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {ICollector, IERC20 as IERC20Col} from "aave-v3-origin/contracts/treasury/ICollector.sol";

import {IRescuableBase} from "solidity-utils/contracts/utils/interfaces/IRescuableBase.sol";
import {RescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IClinicSteward} from "./interfaces/IClinicSteward.sol";

/**
 * @title ClinicSteward
 * @author BGD Labs
 * @notice This contract helps with the liquidation or repayment of bad debt for
 * a list of users within the Aave V3 protocol.
 * All funds for those operations are pulled from the Aave Collector.
 *
 * Repayment of bad debt is permitted only for users without any collateral.
 * If a user has collateral, a liquidation should be performed instead.
 *
 * The contract inherits from `Multicall`. Using the `multicall` function from this contract\
 * multiple liquidation or repayment operations could be bundled into a single transaction.
 *
 * -- Security Considerations --
 *
 * The contract is not upgradable and should never hold any funds.
 * If for any reason funds are stuck on the contract, they are rescuable to the Aave Collector (the recipient address cannot be changed).
 * This can be done by calling the `rescueToken` or `rescueEth` functions that are open to everyone.
 *
 * The contract can only:
 * - repay a pure bad debt (the debt without any collateral)
 * - liquidate users that are already eligible for a liquidation
 *
 * Therefore even when there is a certain level of trust given to the permissioned entity, there is no
 * possibility for any actor to enrich themselves.
 *
 * --- Access control
 * Upon creation, a DAO-permitted entity is configured as the AccessControl default admin.
 * For operational flexibility, this entity can give permissions to other addresses (`CLEANUP_ROLE` role).
 */
contract ClinicSteward is IClinicSteward, RescuableBase, Multicall, AccessControl {
  using SafeERC20 for IERC20;
  using UserConfiguration for DataTypes.UserConfigurationMap;

  /* PUBLIC GLOBAL VARIABLES */

  /// @inheritdoc IClinicSteward
  bytes32 public constant CLEANUP_ROLE = keccak256("CLEANUP_ROLE");

  /// @inheritdoc IClinicSteward
  IPool public immutable override POOL;

  /// @inheritdoc IClinicSteward
  address public immutable override COLLECTOR;

  /* CONSTRUCTOR */

  constructor(address pool, address collector, address admin, address cleanupRoleRecipient) {
    if (pool == address(0) || collector == address(0) || admin == address(0) || cleanupRoleRecipient == address(0)) {
      revert ZeroAddress();
    }

    POOL = IPool(pool);
    COLLECTOR = collector;

    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(CLEANUP_ROLE, cleanupRoleRecipient);
  }

  /* EXTERNAL FUNCTIONS */
  /// @inheritdoc IClinicSteward
  function batchRepayBadDebt(address asset, address[] memory users, bool useATokens)
    external
    override
    onlyRole(CLEANUP_ROLE)
  {
    (uint256 totalDebtAmount, uint256[] memory debtAmounts) = getBadDebtAmount(asset, users);
    _pullFundsAndApprove(asset, totalDebtAmount, useATokens);

    for (uint256 i = 0; i < users.length; i++) {
      if (debtAmounts[i] != 0) {
        POOL.repay({asset: asset, amount: debtAmounts[i], interestRateMode: 2, onBehalfOf: users[i]});
      }
    }

    _transferExcessToCollector(asset);
    IERC20(asset).forceApprove(address(POOL), 0);
  }

  /// @inheritdoc IClinicSteward
  function batchLiquidate(address debtAsset, address collateralAsset, address[] memory users, bool useAToken)
    external
    override
    onlyRole(CLEANUP_ROLE)
  {
    // this is an over approximation as not necessarily all bad debt can be liquidated
    // the excess is transfered back to the collector
    (uint256 maxDebtAmount,) = getDebtAmount(debtAsset, users);
    _pullFundsAndApprove(debtAsset, maxDebtAmount, useAToken);

    for (uint256 i = 0; i < users.length; i++) {
      try POOL.liquidationCall({
        collateralAsset: collateralAsset,
        debtAsset: debtAsset,
        user: users[i],
        debtToCover: type(uint256).max,
        receiveAToken: true
      }) {} catch {}
    }

    // the excess is always in the underlying
    _transferExcessToCollector(debtAsset);

    // transfer back liquidated assets
    address collateralAToken = POOL.getReserveAToken(collateralAsset);
    _transferExcessToCollector(collateralAToken);
    IERC20(debtAsset).forceApprove(address(POOL), 0);
  }

  /// @inheritdoc IClinicSteward
  function rescueToken(address token) external override {
    _emergencyTokenTransfer(token, COLLECTOR, type(uint256).max);
  }

  /// @inheritdoc IClinicSteward
  function rescueEth() external override {
    _emergencyEtherTransfer(COLLECTOR, address(this).balance);
  }

  /* PUBLIC VIEW FUNCTIONS */

  /// @inheritdoc IClinicSteward
  function getDebtAmount(address asset, address[] memory users)
    public
    view
    override
    returns (uint256, uint256[] memory)
  {
    return _getUsersDebtAmounts({asset: asset, users: users, usersCanHaveCollateral: true});
  }

  /// @inheritdoc IClinicSteward
  function getBadDebtAmount(address asset, address[] memory users)
    public
    view
    override
    returns (uint256, uint256[] memory)
  {
    return _getUsersDebtAmounts({asset: asset, users: users, usersCanHaveCollateral: false});
  }

  /// @inheritdoc IRescuableBase
  function maxRescue(address erc20Token) public view virtual override(IRescuableBase, RescuableBase) returns (uint256) {
    return IERC20(erc20Token).balanceOf(address(this));
  }

  /* PRIVATE VIEW FUNCTIONS */

  function _getUsersDebtAmounts(address asset, address[] memory users, bool usersCanHaveCollateral)
    private
    view
    returns (uint256, uint256[] memory)
  {
    uint256 totalDebtAmount;
    uint256[] memory debtAmounts = new uint256[](users.length);

    address variableDebtTokenAddress = POOL.getReserveVariableDebtToken(asset);

    address user;
    for (uint256 i = 0; i < users.length; i++) {
      user = users[i];

      if (!usersCanHaveCollateral) {
        DataTypes.UserConfigurationMap memory userConfiguration = POOL.getUserConfiguration(user);

        if (userConfiguration.isUsingAsCollateralAny()) {
          continue;
        }
      }

      totalDebtAmount += debtAmounts[i] = IERC20(variableDebtTokenAddress).balanceOf(user);
    }

    return (totalDebtAmount, debtAmounts);
  }

  function _pullFundsAndApprove(address asset, uint256 amount, bool useAToken) internal {
    if (useAToken) {
      address aToken = POOL.getReserveAToken(asset);
      // 1 wei surplus to account for rounding on multiple operations
      ICollector(COLLECTOR).transfer(IERC20Col(aToken), address(this), amount + 1);
      POOL.withdraw(asset, type(uint256).max, address(this));
    } else {
      ICollector(COLLECTOR).transfer(IERC20Col(asset), address(this), amount);
    }
    IERC20(asset).forceApprove(address(POOL), amount);
  }

  function _transferExcessToCollector(address asset) internal {
    uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
    if (balanceAfter != 0) {
      IERC20(asset).safeTransfer(COLLECTOR, balanceAfter);
    }
  }
}
