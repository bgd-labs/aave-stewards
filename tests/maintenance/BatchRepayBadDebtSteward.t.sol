// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {IPool, IAToken, DataTypes} from "aave-address-book/AaveV3.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";

import {IBatchRepayBadDebtSteward} from "../../src/maintenance/interfaces/IBatchRepayBadDebtSteward.sol";
import {BatchRepayBadDebtSteward} from "../../src/maintenance/BatchRepayBadDebtSteward.sol";

contract BatchRepayBadDebtStewardTest is Test {
  BatchRepayBadDebtSteward public steward;

  address public assetUnderlying = AaveV3EthereumAssets.WETH_UNDERLYING;
  address public assetDebtToken = AaveV3EthereumAssets.WETH_V_TOKEN;

  address[] public usersWithBadDebt = [0x2882ddAF89baca105E704C01d20F80227F9aD3ed];
  uint256 totalBadDebt;
  uint256[] public usersBadDebtAmounts;

  address[] public usersWithGoodDebt = [
    0x2f97Ab5471F4d621ba93B919f487F8E81E2F14A1,
    0xea5d380A6Ec5C42fdE8969A0eb64BF2f90aFadAA,
    0xBbF308c4b21D808dDa7DaaD698aff46156C6f814,
    0x7d7921e2804fEfaE14B32849bB0bc679966Bc5C7,
    0xC4caf4D21556958cff2c51D62c31FE00c58ff8dD
  ];

  address public repayer = address(0x100);

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21621207); // https://etherscan.io/block/21621207

    steward = new BatchRepayBadDebtSteward(address(AaveV3Ethereum.POOL));

    vm.label(address(AaveV3Ethereum.POOL), "Pool");
    vm.label(address(steward), "BatchRepayBadDebtSteward");
    vm.label(repayer, "Repayer");
    vm.label(assetUnderlying, "AssetUnderlying");
    vm.label(assetDebtToken, "AssetDebtToken");

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]);

      totalBadDebt += currentDebtAmount;
      usersBadDebtAmounts.push(currentDebtAmount);
    }

    deal(assetUnderlying, repayer, totalBadDebt);
    vm.prank(repayer);
    IERC20(assetUnderlying).approve(address(steward), totalBadDebt);
  }

  function test_getBadDebtAmount() public view {
    (uint256 receivedTotalBadDebt, uint256[] memory receivedUsersBadDebtAmounts) =
      steward.getBadDebtAmount(assetUnderlying, usersWithBadDebt);

    assertEq(receivedTotalBadDebt, totalBadDebt);
    assertEq(receivedUsersBadDebtAmounts.length, usersBadDebtAmounts.length);

    for (uint256 i = 0; i < usersBadDebtAmounts.length; i++) {
      assertEq(receivedUsersBadDebtAmounts[i], usersBadDebtAmounts[i]);
    }
  }

  function test_batchRepayBadDebt() public {
    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      vm.expectEmit(address(steward));
      emit IBatchRepayBadDebtSteward.UserBadDebtRepaid({
        user: usersWithBadDebt[i],
        asset: assetUnderlying,
        amount: usersBadDebtAmounts[i]
      });
    }

    vm.prank(repayer);
    steward.batchRepayBadDebt(assetUnderlying, usersWithBadDebt);

    assertEq(IERC20(assetUnderlying).balanceOf(repayer), 0);

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      assertEq(IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]), 0);
    }
  }

  function test_reverts_getBadDebtAmount_duplicatedUsers() public {
    address[] memory passedArray = new address[](2);
    passedArray[0] = usersWithBadDebt[0];
    passedArray[1] = usersWithBadDebt[0];

    vm.expectRevert(
      abi.encodePacked(IBatchRepayBadDebtSteward.UsersShouldBeDifferent.selector, uint256(uint160(passedArray[0])))
    );

    steward.getBadDebtAmount(assetUnderlying, passedArray);
  }

  function test_reverts_getBadDebtAmount_userHasSomeCollateral() public {
    vm.expectRevert(
      abi.encodePacked(IBatchRepayBadDebtSteward.UserHasSomeCollateral.selector, uint256(uint160(usersWithGoodDebt[0])))
    );

    steward.getBadDebtAmount(assetUnderlying, usersWithGoodDebt);
  }

  function test_reverts_getBadDebtAmount_userHasNoDebt() public {
    address[] memory passedArray = new address[](1);
    passedArray[0] = repayer;

    vm.expectRevert(
      abi.encodePacked(IBatchRepayBadDebtSteward.UserHasNoDebt.selector, uint256(uint160(passedArray[0])))
    );

    steward.getBadDebtAmount(assetUnderlying, passedArray);
  }
}
