// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {GovV3Helpers} from "aave-helpers/src/GovV3Helpers.sol";

import {IPool, IAToken, DataTypes} from "aave-address-book/AaveV3.sol";
import {AaveV3Avalanche, AaveV3AvalancheAssets} from "aave-address-book/AaveV3Avalanche.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

import {IClinicSteward} from "../../src/maintenance/interfaces/IClinicSteward.sol";
import {ClinicSteward} from "../../src/maintenance/ClinicSteward.sol";

contract ClinicStewardBaseTest is Test {
  ClinicSteward public steward;

  address public assetUnderlying = AaveV3AvalancheAssets.BTCb_UNDERLYING;
  address public assetAToken = AaveV3AvalancheAssets.BTCb_A_TOKEN;
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

  address[] public usersEligibleForLiquidations = [
    0x6821Aceb02Bd2a64d0900cBf193A543aB41d397e,
    0x5822fb7f7eC70258abe638a6E8637FEd206311F7,
    0x35cBb2525e442488Ed51cE524b4000D4d0d01acC,
    0xE32655B320e77a7103e0837282106677F2C28dCb,
    0x042F53D7250c49f9DCCc54b1A1CFafB16d8A0633,
    0x4dAad5b1B9A4c60F1Bd18A0890AF6794A2242a7E
  ];
  address collateralEligibleForLiquidations = AaveV3AvalancheAssets.USDC_UNDERLYING;
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

  address public collector = address(AaveV3Avalanche.COLLECTOR);

  uint256 public availableBudget = 1_000_000e8;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("avalanche"), 57114758); // https://snowscan.xyz/block/56768474
    steward = new ClinicSteward(address(AaveV3Avalanche.POOL), collector, admin, guardian, availableBudget);

    // v3.3 pool upgrade
    GovV3Helpers.executePayload(vm, 67);
    vm.prank(AaveV3Avalanche.ACL_ADMIN);
    IAccessControl(address(collector)).grantRole("FUNDS_ADMIN", address(steward));

    vm.prank(collector);
    IERC20(assetUnderlying).approve(address(steward), 100_000_000e18);

    vm.label(address(AaveV3Avalanche.POOL), "Pool");
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

    DataTypes.ReserveDataLegacy memory collateralReserveData =
      AaveV3Avalanche.POOL.getReserveData(collateralEligibleForLiquidations);
    for (uint256 i = 0; i < usersEligibleForLiquidations.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersEligibleForLiquidations[i]);

      assertNotEq(currentDebtAmount, 0);

      totalDebtToLiquidate += currentDebtAmount;
      usersEligibleForLiquidationsDebtAmounts.push(currentDebtAmount);

      uint256 collateralBalance = IERC20(collateralReserveData.aTokenAddress).balanceOf(usersEligibleForLiquidations[i]);

      assertNotEq(collateralBalance, 0);
    }
  }
}

contract ClinicStewardTest is ClinicStewardBaseTest {
  function test_batchRepayBadDebt() public {
    deal(assetUnderlying, collector, totalBadDebt);

    uint256 collectorBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);

    vm.prank(guardian);
    steward.batchRepayBadDebt(assetUnderlying, usersWithBadDebt, false);

    uint256 collectorBalanceAfter = IERC20(assetUnderlying).balanceOf(collector);

    assertEq(collectorBalanceBefore - collectorBalanceAfter, totalBadDebt);

    uint256 debtDollarAmount = (AaveV3Avalanche.ORACLE.getAssetPrice(assetUnderlying) * totalBadDebt)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();
    assertEq(steward.availableBudget(), availableBudget - debtDollarAmount);

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      assertEq(IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]), 0);
    }
  }

  function test_batchRepayBadDebtUseAToken() public {
    address aToken = AaveV3Avalanche.POOL.getReserveAToken(assetUnderlying);
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

    uint256 debtDollarAmount = (AaveV3Avalanche.ORACLE.getAssetPrice(assetUnderlying) * totalBadDebt)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();
    assertEq(steward.availableBudget(), availableBudget - debtDollarAmount);

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

  function test_reverts_batchRepayBadDebt_exceeded_pull_limit() public {
    uint256 debtDollarAmount = (AaveV3Avalanche.ORACLE.getAssetPrice(assetUnderlying) * totalBadDebt)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();

    uint256 newAvailableBudget = debtDollarAmount / 2;

    steward = new ClinicSteward(address(AaveV3Avalanche.POOL), collector, admin, guardian, newAvailableBudget);

    vm.expectRevert(
      abi.encodePacked(
        IClinicSteward.AvailableBudgetExceeded.selector,
        uint256(uint160(assetUnderlying)),
        totalBadDebt,
        debtDollarAmount,
        newAvailableBudget
      )
    );

    vm.prank(guardian);
    steward.batchRepayBadDebt(assetUnderlying, usersWithBadDebt, false);
  }

  function test_batchLiquidate() public {
    uint256 collectorBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);
    uint256 stewardBalanceBefore = IERC20(assetUnderlying).balanceOf(address(steward));

    DataTypes.ReserveDataLegacy memory collateralReserveData =
      AaveV3Avalanche.POOL.getReserveData(collateralEligibleForLiquidations);
    uint256 collectorCollateralBalanceBefore = IERC20(collateralReserveData.aTokenAddress).balanceOf(collector);
    uint256 stewardCollateralBalanceBefore = IERC20(collateralReserveData.aTokenAddress).balanceOf(address(steward));

    vm.prank(guardian);
    steward.batchLiquidate(assetUnderlying, collateralEligibleForLiquidations, usersEligibleForLiquidations, false);

    uint256 collectorBalanceAfter = IERC20(assetUnderlying).balanceOf(collector);
    uint256 stewardBalanceAfter = IERC20(assetUnderlying).balanceOf(address(steward));

    uint256 collectorCollateralBalanceAfter = IERC20(collateralReserveData.aTokenAddress).balanceOf(collector);
    uint256 stewardCollateralBalanceAfter = IERC20(collateralReserveData.aTokenAddress).balanceOf(address(steward));

    assertTrue(collectorBalanceBefore >= collectorBalanceAfter);
    assertTrue(collectorBalanceBefore - collectorBalanceAfter <= totalDebtToLiquidate);

    uint256 debtDollarAmount = (AaveV3Avalanche.ORACLE.getAssetPrice(assetUnderlying) * totalDebtToLiquidate)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();
    assertEq(steward.availableBudget(), availableBudget - debtDollarAmount);

    assertTrue(collectorCollateralBalanceAfter >= collectorCollateralBalanceBefore);

    assertEq(stewardBalanceBefore, stewardBalanceAfter);
    assertEq(stewardCollateralBalanceBefore, stewardCollateralBalanceAfter);

    for (uint256 i = 0; i < usersEligibleForLiquidations.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersEligibleForLiquidations[i]);

      uint256 collateralBalance = IERC20(collateralReserveData.aTokenAddress).balanceOf(usersEligibleForLiquidations[i]);

      assertTrue(currentDebtAmount == 0 || collateralBalance == 0);
    }
  }

  function test_batchLiquidateUseAToken() public {
    address debtAToken = AaveV3Avalanche.POOL.getReserveAToken(assetUnderlying);
    uint256 collectorBalanceBefore = IERC20(debtAToken).balanceOf(collector);
    uint256 collectorDebtUnderlyingBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);
    uint256 stewardBalanceBefore = IERC20(assetUnderlying).balanceOf(address(steward));

    address collateralAToken = AaveV3Avalanche.POOL.getReserveAToken(collateralEligibleForLiquidations);
    uint256 collectorCollateralBalanceBefore = IERC20(collateralAToken).balanceOf(collector);
    uint256 stewardCollateralBalanceBefore = IERC20(collateralAToken).balanceOf(address(steward));

    vm.prank(guardian);
    steward.batchLiquidate(assetUnderlying, collateralEligibleForLiquidations, usersEligibleForLiquidations, true);

    uint256 collectorBalanceAfter = IERC20(debtAToken).balanceOf(collector);
    uint256 collectorDebtUnderlyingBalanceAfter = IERC20(assetUnderlying).balanceOf(collector);
    uint256 stewardBalanceAfter = IERC20(assetUnderlying).balanceOf(address(steward));

    uint256 collectorCollateralBalanceAfter = IERC20(collateralAToken).balanceOf(collector);
    uint256 stewardCollateralBalanceAfter = IERC20(collateralAToken).balanceOf(address(steward));

    assertGe(collectorBalanceBefore, collectorBalanceAfter);
    assertGe(collectorDebtUnderlyingBalanceAfter, collectorDebtUnderlyingBalanceBefore);
    assertLe(collectorBalanceBefore - collectorBalanceAfter, totalDebtToLiquidate + 1); // account for 1 wei rounding surplus

    uint256 debtDollarAmount = (AaveV3Avalanche.ORACLE.getAssetPrice(assetUnderlying) * (totalDebtToLiquidate + 1))
      / 10 ** IERC20Metadata(assetUnderlying).decimals();
    assertApproxEqAbs(steward.availableBudget(), availableBudget - debtDollarAmount, 1);

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

  function test_reverts_batchLiquidate_exceeded_pull_limit() public {
    uint256 debtDollarAmount = (AaveV3Avalanche.ORACLE.getAssetPrice(assetUnderlying) * totalDebtToLiquidate)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();

    uint256 newAvailableBudget = debtDollarAmount / 2;

    steward = new ClinicSteward(address(AaveV3Avalanche.POOL), collector, admin, guardian, newAvailableBudget);

    vm.expectRevert(
      abi.encodePacked(
        IClinicSteward.AvailableBudgetExceeded.selector,
        uint256(uint160(assetUnderlying)),
        totalDebtToLiquidate,
        debtDollarAmount,
        newAvailableBudget
      )
    );

    vm.prank(guardian);
    steward.batchLiquidate(assetUnderlying, collateralEligibleForLiquidations, usersEligibleForLiquidations, false);
  }

  function test_setAvailableBudget() public {
    uint256 newAvailableBudget = availableBudget / 2;

    vm.expectEmit(address(steward));
    emit IClinicSteward.AvailableBudgetChanged({oldValue: availableBudget, newValue: newAvailableBudget});

    vm.prank(admin);
    steward.setAvailableBudget(newAvailableBudget);

    assertEq(steward.availableBudget(), newAvailableBudget);
  }

  function test_reverts_setAvailableBudget_caller_not_admin(address caller) public {
    vm.assume(caller != admin);

    vm.expectRevert(
      abi.encodePacked(
        IAccessControl.AccessControlUnauthorizedAccount.selector, uint256(uint160(caller)), steward.DEFAULT_ADMIN_ROLE()
      )
    );

    vm.prank(caller);
    steward.setAvailableBudget(0);
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

  function test_userHasSomeCollateral_returns_zero() public view {
    (uint256 totalAmount, uint256[] memory amounts) = steward.getBadDebtAmount(assetUnderlying, usersWithGoodDebt);
    assertEq(totalAmount, 0);
    for (uint256 i = 0; i < amounts.length; i++) {
      assertEq(amounts[i], 0);
    }
  }

  function test_maxRescue() public {
    assertEq(steward.maxRescue(assetUnderlying), 0);

    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, address(steward), mintAmount);

    assertEq(steward.maxRescue(assetUnderlying), mintAmount);
  }
}
