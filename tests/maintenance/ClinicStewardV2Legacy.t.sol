// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {GovV3Helpers} from "aave-helpers/src/GovV3Helpers.sol";

import {IPool, IAToken, DataTypes} from "aave-address-book/AaveV3.sol";
import {AaveV2Ethereum, AaveV2EthereumAssets} from "aave-address-book/AaveV2Ethereum.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

import {IClinicSteward} from "../../src/maintenance/interfaces/IClinicSteward.sol";
import {ClinicStewardV2Legacy} from "../../src/maintenance/ClinicStewardV2Legacy.sol";

contract ClinicStewardV2LegacyBaseTest is Test {
  ClinicStewardV2Legacy public steward;

  address public assetUnderlying = AaveV2EthereumAssets.WBTC_UNDERLYING;
  address public assetAToken = AaveV2EthereumAssets.WBTC_A_TOKEN;
  address public assetDebtToken = AaveV2EthereumAssets.WBTC_V_TOKEN;

  // this rarely exists on v2 due to 50% liquidations
  address[] public usersWithBadDebt;
  uint256 totalBadDebt;
  uint256[] public usersBadDebtAmounts;

  address[] public usersEligibleForLiquidations = [
    0xd51BA56E5966d363F55203d7f8CbB7Eb4Bf5296f,
    0x9919ec3ef3782382FE1487c4a36b72f02E03189B,
    0x56bABdb63d71879f8D77e2c9515060d3Ae29Cd9e,
    0x76E7A5bb155Ab6838caAdCf4AeC0a2620d7A97a3,
    0x79908ff01947B3d5056AA33c5E1B4b6BfD5aA3D8
  ];
  address collateralEligibleForLiquidations = AaveV2EthereumAssets.USDC_UNDERLYING;
  uint256[] public usersEligibleForLiquidationsDebtAmounts;
  uint256 public totalDebtToLiquidate;

  address[] public usersWithGoodDebt = [
    0x37592B2927c40C4B0054614D7FF6065D6B752a8C,
    0x5fb6Fd8125023c7c4f8FFC8b636a658ad8C1b4eF,
    0x20ed4EF75cE723A580D250005a00DfC86F03112a,
    0x1C943ffC835bFcCd2a435e7bE3507eF821aC06e2,
    0x87F8A29eB20D5DB98dE07301345b48E1e9DDa569,
    0x97F0d7f9d9e7Fe4BFBAbc04BE336dc058873A0E8
  ];

  address public guardian = address(0x101);

  address public admin = address(0x102);

  address public collector = address(AaveV2Ethereum.COLLECTOR);

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21825518);
    steward = new ClinicStewardV2Legacy(address(AaveV2Ethereum.POOL), collector, admin, guardian);

    // v3.3 pool upgrade
    GovV3Helpers.executePayload(vm, 67);
    vm.prank(AaveV2Ethereum.POOL_ADMIN);
    IAccessControl(address(collector)).grantRole("FUNDS_ADMIN", address(steward));

    vm.prank(collector);
    IERC20(assetUnderlying).approve(address(steward), 100_000_000e18);

    vm.label(address(AaveV2Ethereum.POOL), "Pool");
    vm.label(address(steward), "ClinicSteward");
    vm.label(guardian, "Guardian");
    vm.label(admin, "Admin");
    vm.label(collector, "Collector");
    vm.label(assetUnderlying, "AssetUnderlying");
    vm.label(assetDebtToken, "AssetDebtToken");

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]);

      assertNotEq(currentDebtAmount, 0);

      totalBadDebt += currentDebtAmount;
      usersBadDebtAmounts.push(currentDebtAmount);
    }

    address aTokenAddress = AaveV2Ethereum.POOL.getReserveData(collateralEligibleForLiquidations).aTokenAddress;
    for (uint256 i = 0; i < usersEligibleForLiquidations.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersEligibleForLiquidations[i]);

      assertNotEq(currentDebtAmount, 0);

      totalDebtToLiquidate += currentDebtAmount;
      usersEligibleForLiquidationsDebtAmounts.push(currentDebtAmount);

      uint256 collateralBalance = IERC20(aTokenAddress).balanceOf(usersEligibleForLiquidations[i]);

      assertNotEq(collateralBalance, 0);
    }
  }
}

contract ClinicStewardTest is ClinicStewardV2LegacyBaseTest {
  function test_batchRepayBadDebt() public {
    deal(assetUnderlying, collector, totalBadDebt);

    uint256 collectorBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);

    vm.prank(guardian);
    steward.batchRepayBadDebt(assetUnderlying, usersWithBadDebt, false);

    uint256 collectorBalanceAfter = IERC20(assetUnderlying).balanceOf(collector);

    assertEq(collectorBalanceBefore - collectorBalanceAfter, totalBadDebt);

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      assertEq(IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]), 0);
    }
  }

  function test_batchRepayBadDebtUseAToken() public {
    address aToken = AaveV2Ethereum.POOL.getReserveData(assetUnderlying).aTokenAddress;
    uint256 collectorUnderlyingBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);
    uint256 collectorBalanceBefore = IERC20(aToken).balanceOf(collector);

    vm.prank(guardian);
    steward.batchRepayBadDebt(assetUnderlying, usersWithBadDebt, false);

    uint256 collectorUnderlyingBalanceAfter = IERC20(assetUnderlying).balanceOf(collector);
    uint256 collectorBalanceAfter = IERC20(aToken).balanceOf(collector);

    assertApproxEqAbs(
      (collectorBalanceBefore + collectorUnderlyingBalanceBefore)
        - (collectorBalanceAfter + collectorUnderlyingBalanceAfter),
      totalBadDebt,
      100
    );

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      assertEq(IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]), 0);
    }
  }

  function test_reverts_batchRepayBadDebt_caller_not_cleaner(address caller) public {
    vm.assume(caller != guardian);

    vm.expectRevert(
      abi.encodePacked(
        IAccessControl.AccessControlUnauthorizedAccount.selector, uint256(uint160(caller)), steward.CLEANUP_ROLE()
      )
    );

    vm.prank(caller);
    steward.batchRepayBadDebt(assetUnderlying, usersWithBadDebt, false);
  }

  function test_batchLiquidate() public {
    uint256 collectorBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);
    uint256 stewardBalanceBefore = IERC20(assetUnderlying).balanceOf(address(steward));

    address aTokenAddress = AaveV2Ethereum.POOL.getReserveData(collateralEligibleForLiquidations).aTokenAddress;
    uint256 collectorCollateralBalanceBefore = IERC20(aTokenAddress).balanceOf(collector);
    uint256 stewardCollateralBalanceBefore = IERC20(aTokenAddress).balanceOf(address(steward));

    vm.prank(guardian);
    steward.batchLiquidate(assetUnderlying, collateralEligibleForLiquidations, usersEligibleForLiquidations, false);

    uint256 collectorBalanceAfter = IERC20(assetUnderlying).balanceOf(collector);
    uint256 stewardBalanceAfter = IERC20(assetUnderlying).balanceOf(address(steward));

    uint256 collectorCollateralBalanceAfter = IERC20(aTokenAddress).balanceOf(collector);
    uint256 stewardCollateralBalanceAfter = IERC20(aTokenAddress).balanceOf(address(steward));

    assertTrue(collectorBalanceBefore >= collectorBalanceAfter);
    assertTrue(collectorBalanceBefore - collectorBalanceAfter <= totalDebtToLiquidate);

    assertTrue(collectorCollateralBalanceAfter >= collectorCollateralBalanceBefore);

    assertEq(stewardBalanceBefore, stewardBalanceAfter);
    assertEq(stewardCollateralBalanceBefore, stewardCollateralBalanceAfter);

    for (uint256 i = 0; i < usersEligibleForLiquidations.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersEligibleForLiquidations[i]);

      uint256 collateralBalance = IERC20(aTokenAddress).balanceOf(usersEligibleForLiquidations[i]);

      assertTrue(currentDebtAmount == 0 || collateralBalance == 0);
    }
  }

  function test_batchLiquidateUseAToken() public {
    address debtAToken = AaveV2Ethereum.POOL.getReserveData(assetUnderlying).aTokenAddress;
    uint256 collectorBalanceBefore = IERC20(debtAToken).balanceOf(collector);
    uint256 stewardBalanceBefore = IERC20(assetUnderlying).balanceOf(address(steward));

    address collateralAToken = AaveV2Ethereum.POOL.getReserveData(collateralEligibleForLiquidations).aTokenAddress;
    uint256 collectorCollateralBalanceBefore = IERC20(collateralAToken).balanceOf(collector);
    uint256 stewardCollateralBalanceBefore = IERC20(collateralAToken).balanceOf(address(steward));

    vm.prank(guardian);
    steward.batchLiquidate(assetUnderlying, collateralEligibleForLiquidations, usersEligibleForLiquidations, true);

    uint256 collectorBalanceAfter = IERC20(debtAToken).balanceOf(collector);
    uint256 stewardBalanceAfter = IERC20(assetUnderlying).balanceOf(address(steward));

    uint256 collectorCollateralBalanceAfter = IERC20(collateralAToken).balanceOf(collector);
    uint256 stewardCollateralBalanceAfter = IERC20(collateralAToken).balanceOf(address(steward));

    assertGe(collectorBalanceBefore, collectorBalanceAfter);
    assertLe(collectorBalanceBefore - collectorBalanceAfter, totalDebtToLiquidate + 1); // account for 1 wei rounding surplus

    assertTrue(collectorCollateralBalanceAfter >= collectorCollateralBalanceBefore);

    assertEq(stewardBalanceBefore, stewardBalanceAfter);
    assertEq(stewardCollateralBalanceBefore, stewardCollateralBalanceAfter);

    for (uint256 i = 0; i < usersEligibleForLiquidations.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersEligibleForLiquidations[i]);

      uint256 collateralBalance = IERC20(collateralAToken).balanceOf(usersEligibleForLiquidations[i]);

      assertTrue(currentDebtAmount == 0 || collateralBalance == 0);
    }
  }

  function test_reverts_batchLiquidate_caller_not_cleaner(address caller) public {
    vm.assume(caller != guardian);

    vm.expectRevert(
      abi.encodePacked(
        IAccessControl.AccessControlUnauthorizedAccount.selector, uint256(uint160(caller)), steward.CLEANUP_ROLE()
      )
    );

    vm.prank(caller);
    steward.batchLiquidate(assetUnderlying, collateralEligibleForLiquidations, usersEligibleForLiquidations, false);
  }

  function test_rescueToken() public {
    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, address(steward), mintAmount);

    uint256 collectorBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);

    steward.rescueToken(assetUnderlying);

    uint256 collectorBalanceAfter = IERC20(assetUnderlying).balanceOf(collector);

    assertEq(collectorBalanceAfter - collectorBalanceBefore, mintAmount);
    assertEq(IERC20(assetUnderlying).balanceOf(address(steward)), 0);
  }

  receive() external payable {}

  function test_rescueEth() public {
    uint256 mintAmount = 1_000_000e18;
    deal(address(steward), mintAmount);

    uint256 collectorBalanceBefore = collector.balance;

    steward.rescueEth();

    uint256 collectorBalanceAfter = collector.balance;

    assertEq(collectorBalanceAfter - collectorBalanceBefore, mintAmount);
    assertEq(address(steward).balance, 0);
  }

  function test_getDebtAmount() public view {
    (uint256 receivedTotalDebt, uint256[] memory receivedUsersDebtAmounts) =
      steward.getDebtAmount(assetUnderlying, usersEligibleForLiquidations);

    assertEq(receivedTotalDebt, totalDebtToLiquidate);
    assertEq(receivedUsersDebtAmounts.length, usersEligibleForLiquidations.length);

    for (uint256 i = 0; i < usersEligibleForLiquidations.length; i++) {
      assertEq(receivedUsersDebtAmounts[i], usersEligibleForLiquidationsDebtAmounts[i]);
    }
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

  function test_reverts_getBadDebtAmount_userHasSomeCollateral() public {
    vm.expectRevert(
      abi.encodePacked(IClinicSteward.UserHasSomeCollateral.selector, uint256(uint160(usersWithGoodDebt[0])))
    );

    steward.getBadDebtAmount(assetUnderlying, usersWithGoodDebt);
  }

  function test_maxRescue() public {
    assertEq(steward.maxRescue(assetUnderlying), 0);

    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, address(steward), mintAmount);

    assertEq(steward.maxRescue(assetUnderlying), mintAmount);
  }
}
