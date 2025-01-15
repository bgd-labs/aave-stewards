// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {IPool, IAToken, DataTypes} from "aave-address-book/AaveV3.sol";
import {AaveV3Avalanche, AaveV3AvalancheAssets} from "aave-address-book/AaveV3Avalanche.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";

import {IBatchRepayBadDebtSteward} from "../../../src/maintenance/interfaces/IBatchRepayBadDebtSteward.sol";
import {BatchRepayBadDebtSteward} from "../../../src/maintenance/BatchRepayBadDebtSteward.sol";

contract BatchRepayBadDebtStewardTest is Test {
  BatchRepayBadDebtSteward public steward;

  address public assetUnderlying = AaveV3AvalancheAssets.BTCb_UNDERLYING;
  address public assetDebtToken = AaveV3AvalancheAssets.BTCb_V_TOKEN;

  address[] public usersWithBadDebt = [
    0x233bA87Cb5180fcCf86ac8Dd19CE07d09732DD39,
    0x20Bb103F0688D434d80336010b7F5feA22B8480E,
    0x9D4Ad74b46675998321101b2a49a4D66ac7509Ea,
    0xCb87dD67Fe09121abd335044a1e0d6bf44C915FB,
    0xd3D97E2cbF1fc09528830F58BCA6DbC4cc74bA14,
    0xd80aC14a778f4A708dcda53D9B03e1A66B551872
  ];
  uint256 totalBadDebt;
  uint256[] public usersBadDebtAmounts;

  address public repayer = address(0x100);

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("avalanche"), 55793443); // https://snowscan.xyz/block/55793443

    steward = new BatchRepayBadDebtSteward(address(AaveV3Avalanche.POOL));

    vm.label(address(AaveV3Avalanche.POOL), "Pool");
    vm.label(address(steward), "BatchRepayBadDebtSteward");
    vm.label(repayer, "Repayer");
  }

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

  function _callGetBadDebtAmountWithNumberOfUsers(uint256 userAmount) private view {
    address[] memory users = new address[](userAmount);
    for (uint256 i = 0; i < userAmount; ++i) {
      users[i] = usersWithBadDebt[i];
    }

    steward.getBadDebtAmount(assetUnderlying, users);
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
}
