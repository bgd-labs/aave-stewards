// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool, DataTypes} from "aave-address-book/AaveV3.sol";

import {UserConfiguration} from "aave-v3-origin/contracts/protocol/libraries/configuration/UserConfiguration.sol";

import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {SafeERC20} from "solidity-utils/contracts/oz-common/SafeERC20.sol";

import {IRescuableBase} from "solidity-utils/contracts/utils/interfaces/IRescuableBase.sol";
import {RescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";

import {IBatchRepayBadDebtSteward} from "./interfaces/IBatchRepayBadDebtSteward.sol";

/// @title BatchRepayBadDebtSteward
/// @author BGD Labs
/// @notice This contract allows to repay all the bad debt of a list of users
/// @dev Only allowed those users that have some debt and doesn't have any collateral
contract BatchRepayBadDebtSteward is IBatchRepayBadDebtSteward, RescuableBase, OwnableWithGuardian {
  using SafeERC20 for IERC20;
  using UserConfiguration for DataTypes.UserConfigurationMap;

  /* PUBLIC GLOBAL VARIABLES */

  /// @inheritdoc IBatchRepayBadDebtSteward
  IPool public immutable override POOL;

  /* CONSTRUCTOR */

  constructor(address _pool, address _guardian, address _owner) {
    POOL = IPool(_pool);

    if (msg.sender != _guardian) {
      _updateGuardian(_guardian);
    }

    if (msg.sender != _owner) {
      _transferOwnership(_owner);
    }
  }

  /* EXTERNAL FUNCTIONS */

  /// @inheritdoc IBatchRepayBadDebtSteward
  function batchLiquidate(address debtAsset, address[] memory collateralAssets, address[] memory users)
    external
    override
  {
    (uint256 totalDebtAmount,) = getDebtAmount(debtAsset, users);

    IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), totalDebtAmount);
    IERC20(debtAsset).forceApprove(address(POOL), totalDebtAmount);

    uint256 length = users.length;
    for (uint256 i = 0; i < length; i++) {
      POOL.liquidationCall({
        collateralAsset: collateralAssets[i],
        debtAsset: debtAsset,
        user: users[i],
        debtToCover: type(uint256).max,
        receiveAToken: true
      });
    }
  }

  /// @inheritdoc IBatchRepayBadDebtSteward
  function batchRepayBadDebt(address asset, address[] memory users) external override {
    (uint256 totalDebtAmount, uint256[] memory debtAmounts) = getBadDebtAmount(asset, users);

    IERC20(asset).safeTransferFrom(msg.sender, address(this), totalDebtAmount);
    IERC20(asset).forceApprove(address(POOL), totalDebtAmount);

    uint256 length = users.length;
    for (uint256 i = 0; i < length; i++) {
      POOL.repay({asset: asset, amount: debtAmounts[i], interestRateMode: 2, onBehalfOf: users[i]});
    }
  }

  function rescueToken(address token, address to) external onlyOwnerOrGuardian {
    _emergencyTokenTransfer(token, to, type(uint256).max);
  }

  function rescueEth(address to) external onlyOwnerOrGuardian {
    _emergencyEtherTransfer(to, address(this).balance);
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

    DataTypes.ReserveDataLegacy memory reserveData = POOL.getReserveData(asset);

    for (uint256 i = 0; i < length; i++) {
      address user = users[i];

      for (uint256 j = i + 1; j < length; j++) {
        if (user == users[j]) {
          revert UsersShouldBeDifferent(user);
        }
      }

      DataTypes.UserConfigurationMap memory userConfiguration = POOL.getUserConfiguration(user);

      if (!usersCanHaveCollateral && userConfiguration.isUsingAsCollateralAny()) {
        revert UserHasSomeCollateral(user);
      }

      totalDebtAmount += debtAmounts[i] = IERC20(reserveData.variableDebtTokenAddress).balanceOf(user);
    }

    return (totalDebtAmount, debtAmounts);
  }
}
