// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool, DataTypes} from "aave-address-book/AaveV3.sol";

import {UserConfiguration} from "aave-v3-origin/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {ICollector, IERC20 as IERC20Col} from "aave-v3-origin/contracts/treasury/ICollector.sol";

import {IRescuableBase} from "solidity-utils/contracts/utils/interfaces/IRescuableBase.sol";
import {RescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IBatchRepayBadDebtSteward} from "./interfaces/IBatchRepayBadDebtSteward.sol";

/**
 * @title BatchRepayBadDebtSteward
 * @author BGD Labs
 * @notice This contract allows to repay all the bad debt of a list of users
 * @dev Only allowed those users that have some debt and doesn't have any collateral
 */
contract BatchRepayBadDebtSteward is
  IBatchRepayBadDebtSteward,
  RescuableBase,
  OwnableWithGuardian,
  Multicall,
  AccessControl
{
  using SafeERC20 for IERC20;
  using UserConfiguration for DataTypes.UserConfigurationMap;

  /* PUBLIC GLOBAL VARIABLES */

  /// @inheritdoc IBatchRepayBadDebtSteward
  bytes32 public constant CLEANUP = keccak256("CLEANUP");

  /// @inheritdoc IBatchRepayBadDebtSteward
  IPool public immutable override POOL;

  /// @inheritdoc IBatchRepayBadDebtSteward
  address public immutable override COLLECTOR;

  /* CONSTRUCTOR */

  constructor(address _pool, address _guardian, address _owner, address _collector)
    OwnableWithGuardian(_owner, _guardian)
  {
    if (_pool == address(0) || _collector == address(0)) {
      revert ZeroAddress();
    }

    POOL = IPool(_pool);
    COLLECTOR = _collector;

    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(CLEANUP, _guardian);
  }

  /* EXTERNAL FUNCTIONS */

  /// @inheritdoc IBatchRepayBadDebtSteward
  function batchLiquidate(address debtAsset, address collateralAsset, address[] memory users) external override {
    (uint256 maxDebtAmount,) = getDebtAmount(debtAsset, users);

    batchLiquidateWithMaxCap(debtAsset, collateralAsset, users, maxDebtAmount);
  }

  /// @inheritdoc IBatchRepayBadDebtSteward
  function batchLiquidateWithMaxCap(
    address debtAsset,
    address collateralAsset,
    address[] memory users,
    uint256 maxDebtTokenAmount
  ) public override onlyRole(CLEANUP) {
    ICollector(COLLECTOR).transfer(IERC20Col(debtAsset), address(this), maxDebtTokenAmount);
    IERC20(debtAsset).forceApprove(address(POOL), maxDebtTokenAmount);

    for (uint256 i = 0; i < users.length; i++) {
      POOL.liquidationCall({
        collateralAsset: collateralAsset,
        debtAsset: debtAsset,
        user: users[i],
        debtToCover: type(uint256).max,
        receiveAToken: true
      });
    }

    // transfer back surplus
    uint256 balanceAfter = IERC20(debtAsset).balanceOf(address(this));
    if (balanceAfter != 0) {
      IERC20(debtAsset).safeTransfer(COLLECTOR, balanceAfter);
    }

    // transfer back liquidated assets
    IERC20(POOL.getReserveAToken(collateralAsset)).safeTransfer(COLLECTOR, type(uint256).max);
  }

  /// @inheritdoc IBatchRepayBadDebtSteward
  function batchRepayBadDebt(address asset, address[] memory users) external override onlyRole(CLEANUP) {
    (uint256 totalDebtAmount, uint256[] memory debtAmounts) = getBadDebtAmount(asset, users);

    ICollector(COLLECTOR).transfer(IERC20Col(asset), address(this), totalDebtAmount);
    IERC20(asset).forceApprove(address(POOL), totalDebtAmount);

    for (uint256 i = 0; i < users.length; i++) {
      POOL.repay({asset: asset, amount: debtAmounts[i], interestRateMode: 2, onBehalfOf: users[i]});
    }

    uint256 balanceLeft = IERC20(asset).balanceOf(address(this));
    if (balanceLeft != 0) IERC20(asset).transfer(COLLECTOR, balanceLeft);
  }

  /// @inheritdoc IBatchRepayBadDebtSteward
  function rescueToken(address token) external override {
    _emergencyTokenTransfer(token, COLLECTOR, type(uint256).max);
  }

  /// @inheritdoc IBatchRepayBadDebtSteward
  function rescueEth() external override {
    _emergencyEtherTransfer(COLLECTOR, address(this).balance);
  }

  /* PUBLIC VIEW FUNCTIONS */

  /// @inheritdoc IBatchRepayBadDebtSteward
  function getDebtAmount(address asset, address[] memory users)
    public
    view
    override
    returns (uint256, uint256[] memory)
  {
    return _getUsersDebtAmounts({asset: asset, users: users, usersCanHaveCollateral: true});
  }

  /// @inheritdoc IBatchRepayBadDebtSteward
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
    uint256 length = users.length;

    uint256 totalDebtAmount;
    uint256[] memory debtAmounts = new uint256[](length);

    address variableDebtTokenAddress = POOL.getReserveVariableDebtToken(asset);

    address user;
    for (uint256 i = 0; i < length; i++) {
      user = users[i];

      if (!usersCanHaveCollateral) {
        DataTypes.UserConfigurationMap memory userConfiguration = POOL.getUserConfiguration(user);
        if (userConfiguration.isUsingAsCollateralAny()) {
          revert UserHasSomeCollateral(user);
        }
      }

      totalDebtAmount += debtAmounts[i] = IERC20(variableDebtTokenAddress).balanceOf(user);
    }

    return (totalDebtAmount, debtAmounts);
  }
}
