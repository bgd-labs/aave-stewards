// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {IPool, IAToken, DataTypes} from "aave-address-book/AaveV3.sol";
import {AaveV3Avalanche, AaveV3AvalancheAssets} from "aave-address-book/AaveV3Avalanche.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";

import {IBatchRepayBadDebtSteward} from "../../../src/maintenance/interfaces/IBatchRepayBadDebtSteward.sol";
import {BatchRepayBadDebtSteward} from "../../../src/maintenance/BatchRepayBadDebtSteward.sol";

import {BatchRepayBadDebtStewardBaseTest} from "../../maintenance/BatchRepayBadDebtSteward.t.sol";

contract BatchRepayBadDebtStewardTest is BatchRepayBadDebtStewardBaseTest {
  function test_getBadDebtAmount_zero_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(0);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getBadDebtAmount: with 0 users");
  }

  function test_getBadDebtAmount_one_user() public {
    _callGetBadDebtAmountWithNumberOfUsers(1);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getBadDebtAmount: with 1 user");
  }

  function test_getBadDebtAmount_two_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(2);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getBadDebtAmount: with 2 users");
  }

  function test_getBadDebtAmount_three_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(3);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getBadDebtAmount: with 2 users");
  }

  function test_getBadDebtAmount_four_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(4);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getBadDebtAmount: with 4 users");
  }

  function test_getBadDebtAmount_five_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(5);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getBadDebtAmount: with 5 users");
  }

  function test_getBadDebtAmount_six_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(6);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getBadDebtAmount: with 6 users");
  }

  function test_getDebtAmount_zero_users() public {
    _callGetDebtAmountWithNumberOfUsers(0);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getDebtAmount: with 0 users");
  }

  function test_getDebtAmount_one_user() public {
    _callGetDebtAmountWithNumberOfUsers(1);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getDebtAmount: with 1 user");
  }

  function test_getDebtAmount_two_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(2);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getDebtAmount: with 2 users");
  }

  function test_getDebtAmount_three_users() public {
    _callGetDebtAmountWithNumberOfUsers(3);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getDebtAmount: with 2 users");
  }

  function test_getDebtAmount_four_users() public {
    _callGetDebtAmountWithNumberOfUsers(4);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getDebtAmount: with 4 users");
  }

  function test_getDebtAmount_five_users() public {
    _callGetDebtAmountWithNumberOfUsers(5);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getDebtAmount: with 5 users");
  }

  function test_getDebtAmount_six_users() public {
    _callGetDebtAmountWithNumberOfUsers(6);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function getDebtAmount: with 6 users");
  }

  function test_batchRepayBadDebt_zero_users() public {
    _callBatchRepayBadDebtWithNumberOfUsers(0);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchRepayBadDebt: with 0 users");
  }

  function test_batchRepayBadDebt_one_user() public {
    _callBatchRepayBadDebtWithNumberOfUsers(1);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchRepayBadDebt: with 1 user");
  }

  function test_batchRepayBadDebt_two_users() public {
    _callBatchRepayBadDebtWithNumberOfUsers(2);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchRepayBadDebt: with 2 users");
  }

  function test_batchRepayBadDebt_three_users() public {
    _callBatchRepayBadDebtWithNumberOfUsers(3);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchRepayBadDebt: with 3 users");
  }

  function test_batchRepayBadDebt_four_users() public {
    _callBatchRepayBadDebtWithNumberOfUsers(4);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchRepayBadDebt: with 4 users");
  }

  function test_batchRepayBadDebt_five_users() public {
    _callBatchRepayBadDebtWithNumberOfUsers(5);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchRepayBadDebt: with 5 users");
  }

  function test_batchRepayBadDebt_six_users() public {
    _callBatchRepayBadDebtWithNumberOfUsers(6);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchRepayBadDebt: with 6 users");
  }

  function test_batchLiquidate_zero_users() public {
    _callBatchLiquidateWithNumberOfUsers(0);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchLiquidate: with 0 users");
  }

  function test_batchLiquidate_one_user() public {
    _callBatchLiquidateWithNumberOfUsers(1);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchLiquidate: with 1 user");
  }

  function test_batchLiquidate_two_users() public {
    _callBatchLiquidateWithNumberOfUsers(2);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchLiquidate: with 2 users");
  }

  function test_batchLiquidate_three_users() public {
    _callBatchLiquidateWithNumberOfUsers(3);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchLiquidate: with 3 users");
  }

  function test_batchLiquidate_four_users() public {
    _callBatchLiquidateWithNumberOfUsers(4);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchLiquidate: with 4 users");
  }

  function test_batchLiquidate_five_users() public {
    _callBatchLiquidateWithNumberOfUsers(5);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchLiquidate: with 5 users");
  }

  function test_batchLiquidate_six_users() public {
    _callBatchLiquidateWithNumberOfUsers(6);

    vm.snapshotGasLastCall("BatchRepayBadDebtSteward", "function batchLiquidate: with 6 users");
  }

  function _callGetBadDebtAmountWithNumberOfUsers(uint256 userAmount) private view {
    address[] memory users = new address[](userAmount);
    for (uint256 i = 0; i < userAmount; ++i) {
      users[i] = usersWithBadDebt[i];
    }

    steward.getBadDebtAmount(assetUnderlying, users);
  }

  function _callGetDebtAmountWithNumberOfUsers(uint256 userAmount) private view {
    address[] memory users = new address[](userAmount);
    for (uint256 i = 0; i < userAmount; ++i) {
      users[i] = usersEligibleForLiquidations[i];
    }

    steward.getDebtAmount(assetUnderlying, users);
  }

  function _callBatchRepayBadDebtWithNumberOfUsers(uint256 userAmount) private {
    address[] memory users = new address[](userAmount);
    for (uint256 i = 0; i < userAmount; ++i) {
      users[i] = usersWithBadDebt[i];
    }

    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, repayer, mintAmount);

    vm.startPrank(repayer);

    IERC20(assetUnderlying).approve(address(steward), mintAmount);

    steward.batchRepayBadDebt(assetUnderlying, users);

    vm.stopPrank();
  }

  function _callBatchLiquidateWithNumberOfUsers(uint256 userAmount) private {
    address[] memory users = new address[](userAmount);
    for (uint256 i = 0; i < userAmount; ++i) {
      users[i] = usersEligibleForLiquidations[i];
    }

    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, repayer, mintAmount);

    vm.startPrank(repayer);

    IERC20(assetUnderlying).approve(address(steward), mintAmount);

    steward.batchLiquidate(assetUnderlying, collateralsEligibleForLiquidations, usersEligibleForLiquidations);

    vm.stopPrank();
  }
}
