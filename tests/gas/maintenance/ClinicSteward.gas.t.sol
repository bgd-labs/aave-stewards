// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {IPool, IAToken, DataTypes} from "aave-address-book/AaveV3.sol";
import {AaveV3Avalanche, AaveV3AvalancheAssets} from "aave-address-book/AaveV3Avalanche.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IClinicSteward} from "../../../src/maintenance/interfaces/IClinicSteward.sol";
import {ClinicSteward} from "../../../src/maintenance/ClinicSteward.sol";

import {ClinicStewardBaseTest} from "../../maintenance/ClinicSteward.t.sol";

/// forge-config: default.isolate = true
contract ClinicStewardGasTest is ClinicStewardBaseTest {
  function test_getBadDebtAmount_zero_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(0);

    vm.snapshotGasLastCall("ClinicSteward", "function getBadDebtAmount: with 0 users");
  }

  function test_getBadDebtAmount_one_user() public {
    _callGetBadDebtAmountWithNumberOfUsers(1);

    vm.snapshotGasLastCall("ClinicSteward", "function getBadDebtAmount: with 1 user");
  }

  function test_getBadDebtAmount_two_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(2);

    vm.snapshotGasLastCall("ClinicSteward", "function getBadDebtAmount: with 2 users");
  }

  function test_getBadDebtAmount_three_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(3);

    vm.snapshotGasLastCall("ClinicSteward", "function getBadDebtAmount: with 2 users");
  }

  function test_getBadDebtAmount_four_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(4);

    vm.snapshotGasLastCall("ClinicSteward", "function getBadDebtAmount: with 4 users");
  }

  function test_getBadDebtAmount_five_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(5);

    vm.snapshotGasLastCall("ClinicSteward", "function getBadDebtAmount: with 5 users");
  }

  function test_getBadDebtAmount_six_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(6);

    vm.snapshotGasLastCall("ClinicSteward", "function getBadDebtAmount: with 6 users");
  }

  function test_getDebtAmount_zero_users() public {
    _callGetDebtAmountWithNumberOfUsers(0);

    vm.snapshotGasLastCall("ClinicSteward", "function getDebtAmount: with 0 users");
  }

  function test_getDebtAmount_one_user() public {
    _callGetDebtAmountWithNumberOfUsers(1);

    vm.snapshotGasLastCall("ClinicSteward", "function getDebtAmount: with 1 user");
  }

  function test_getDebtAmount_two_users() public {
    _callGetBadDebtAmountWithNumberOfUsers(2);

    vm.snapshotGasLastCall("ClinicSteward", "function getDebtAmount: with 2 users");
  }

  function test_getDebtAmount_three_users() public {
    _callGetDebtAmountWithNumberOfUsers(3);

    vm.snapshotGasLastCall("ClinicSteward", "function getDebtAmount: with 2 users");
  }

  function test_getDebtAmount_four_users() public {
    _callGetDebtAmountWithNumberOfUsers(4);

    vm.snapshotGasLastCall("ClinicSteward", "function getDebtAmount: with 4 users");
  }

  function test_getDebtAmount_five_users() public {
    _callGetDebtAmountWithNumberOfUsers(5);

    vm.snapshotGasLastCall("ClinicSteward", "function getDebtAmount: with 5 users");
  }

  function test_getDebtAmount_six_users() public {
    _callGetDebtAmountWithNumberOfUsers(6);

    vm.snapshotGasLastCall("ClinicSteward", "function getDebtAmount: with 6 users");
  }

  function test_batchRepayBadDebt_zero_users() public {
    _callClinicStewardWithNumberOfUsers(0);

    vm.snapshotGasLastCall("ClinicSteward", "function batchRepayBadDebt: with 0 users");
  }

  function test_batchRepayBadDebt_one_user() public {
    _callClinicStewardWithNumberOfUsers(1);

    vm.snapshotGasLastCall("ClinicSteward", "function batchRepayBadDebt: with 1 user");
  }

  function test_batchRepayBadDebt_two_users() public {
    _callClinicStewardWithNumberOfUsers(2);

    vm.snapshotGasLastCall("ClinicSteward", "function batchRepayBadDebt: with 2 users");
  }

  function test_batchRepayBadDebt_three_users() public {
    _callClinicStewardWithNumberOfUsers(3);

    vm.snapshotGasLastCall("ClinicSteward", "function batchRepayBadDebt: with 3 users");
  }

  function test_batchRepayBadDebt_four_users() public {
    _callClinicStewardWithNumberOfUsers(4);

    vm.snapshotGasLastCall("ClinicSteward", "function batchRepayBadDebt: with 4 users");
  }

  function test_batchRepayBadDebt_five_users() public {
    _callClinicStewardWithNumberOfUsers(5);

    vm.snapshotGasLastCall("ClinicSteward", "function batchRepayBadDebt: with 5 users");
  }

  function test_batchRepayBadDebt_six_users() public {
    _callClinicStewardWithNumberOfUsers(6);

    vm.snapshotGasLastCall("ClinicSteward", "function batchRepayBadDebt: with 6 users");
  }

  function test_batchLiquidate_zero_users() public {
    _callBatchLiquidateWithNumberOfUsers(0);

    vm.snapshotGasLastCall("ClinicSteward", "function batchLiquidate: with 0 users");
  }

  function test_batchLiquidate_one_user() public {
    _callBatchLiquidateWithNumberOfUsers(1);

    vm.snapshotGasLastCall("ClinicSteward", "function batchLiquidate: with 1 user");
  }

  function test_batchLiquidate_two_users() public {
    _callBatchLiquidateWithNumberOfUsers(2);

    vm.snapshotGasLastCall("ClinicSteward", "function batchLiquidate: with 2 users");
  }

  function test_batchLiquidate_three_users() public {
    _callBatchLiquidateWithNumberOfUsers(3);

    vm.snapshotGasLastCall("ClinicSteward", "function batchLiquidate: with 3 users");
  }

  function test_batchLiquidate_four_users() public {
    _callBatchLiquidateWithNumberOfUsers(4);

    vm.snapshotGasLastCall("ClinicSteward", "function batchLiquidate: with 4 users");
  }

  function test_batchLiquidate_five_users() public {
    _callBatchLiquidateWithNumberOfUsers(5);

    vm.snapshotGasLastCall("ClinicSteward", "function batchLiquidate: with 5 users");
  }

  function test_batchLiquidate_six_users() public {
    _callBatchLiquidateWithNumberOfUsers(6);

    vm.snapshotGasLastCall("ClinicSteward", "function batchLiquidate: with 6 users");
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

  function _callClinicStewardWithNumberOfUsers(uint256 userAmount) private {
    address[] memory users = new address[](userAmount);
    for (uint256 i = 0; i < userAmount; ++i) {
      users[i] = usersWithBadDebt[i];
    }

    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, collector, mintAmount);

    vm.prank(guardian);
    steward.batchRepayBadDebt(assetUnderlying, users, false);
  }

  function _callBatchLiquidateWithNumberOfUsers(uint256 userAmount) private {
    address[] memory users = new address[](userAmount);
    for (uint256 i = 0; i < userAmount; ++i) {
      users[i] = usersEligibleForLiquidations[i];
    }

    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, collector, mintAmount);

    vm.prank(guardian);
    steward.batchLiquidate(assetUnderlying, collateralEligibleForLiquidations, users, false);
  }
}
