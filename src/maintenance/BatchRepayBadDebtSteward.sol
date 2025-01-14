// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool, DataTypes} from "aave-address-book/AaveV3.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {SafeERC20} from "solidity-utils/contracts/oz-common/SafeERC20.sol";

import {IBatchRepayBadDebtSteward} from "./interfaces/IBatchRepayBadDebtSteward.sol";

/// @title BatchRepayBadDebtSteward
/// @author BGD Labs
/// @notice This contract allows to repay all the bad debt of a list of users
/// @dev Only allowed those users that have some debt and doesn't have any collateral
contract BatchRepayBadDebtSteward is IBatchRepayBadDebtSteward {
  using SafeERC20 for IERC20;

  /* PUBLIC GLOBAL VARIABLES */

  /// @inheritdoc IBatchRepayBadDebtSteward
  IPool public immutable override POOL;

  /* CONSTRUCTOR */

  constructor(address _pool) {
    POOL = IPool(_pool);
  }

  /* EXTERNAL FUNCTIONS */

  /// @inheritdoc IBatchRepayBadDebtSteward
  function batchRepayBadDebt(address asset, address[] memory users) external override {
    (uint256 totalDebtAmount, uint256[] memory debtAmounts) = getBadDebtAmount(asset, users);

    IERC20(asset).safeTransferFrom(msg.sender, address(this), totalDebtAmount);
    IERC20(asset).forceApprove(address(POOL), totalDebtAmount);

    uint256 length = users.length;
    for (uint256 i = 0; i < length; i++) {
      POOL.repay({asset: asset, amount: debtAmounts[i], interestRateMode: 2, onBehalfOf: users[i]});

      emit UserBadDebtRepaid({user: users[i], asset: asset, amount: debtAmounts[i]});
    }
  }

  /* PUBLIC VIEW FUNCTIONS */

  /// @inheritdoc IBatchRepayBadDebtSteward
  function getBadDebtAmount(address asset, address[] memory users)
    public
    view
    override
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

      (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = POOL.getUserAccountData(user);

      if (totalCollateralBase > 0) {
        revert UserHasSomeCollateral(user);
      }

      if (totalDebtBase == 0) {
        revert UserHasNoDebt(user);
      }

      totalDebtAmount += debtAmounts[i] = IERC20(reserveData.variableDebtTokenAddress).balanceOf(user);
    }

    return (totalDebtAmount, debtAmounts);
  }
}
