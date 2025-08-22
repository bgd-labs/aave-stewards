// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {GovV3Helpers} from "aave-helpers/src/GovV3Helpers.sol";

import {ILendingPool, DataTypes} from "aave-address-book/AaveV2.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV2Ethereum, AaveV2EthereumAssets, IAaveOracle} from "aave-address-book/AaveV2Ethereum.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

import {IClinicSteward} from "../../src/maintenance/interfaces/IClinicSteward.sol";
import {ClinicStewardV2} from "../../src/maintenance/ClinicStewardV2.sol";

contract ClinicStewardV2BaseTest is Test {
  ClinicStewardV2 public steward;

  address public assetUnderlying = AaveV2EthereumAssets.WETH_UNDERLYING;
  address public assetAToken = AaveV2EthereumAssets.WETH_A_TOKEN;
  address public assetDebtToken = AaveV2EthereumAssets.WETH_V_TOKEN;

  address[] public usersWithBadDebt = [
    0xFa4FC4ec2F81A4897743C5b4f45907c02ce06199,
    0xb5fb748EC3e019A7Ed4F6F701158bc23FA3a2626,
    0x6Aa63cb1657A2d9Dd8D0F54232ffda85267Af210,
    0xE801740F53040CF26E2F35811FB0c73D2B866902,
    0xD98014Be6E16eCDCd52a5fd8D6AC0c2f4CC8B95D
  ];
  uint256 totalBadDebt;
  uint256[] public usersBadDebtAmounts;

  address[] public usersEligibleForLiquidations = [
    0x20043D364e650318c129108B3dB625A1069778d5,
    0x52DE8B421f596edAF028b1FfCB92EC61CB9622A4,
    0x8F6D072cA42432692de973b788e89794D7db1037,
    0xd962D5147f628f3f902cB06696D2aa6E72411262,
    0xa6bF7fCebc4B4148c0c54324b190AaA7A779362e
  ];
  address collateralEligibleForLiquidations = AaveV2EthereumAssets.USDC_UNDERLYING;
  uint256[] public usersEligibleForLiquidationsDebtAmounts;
  uint256 public totalDebtToLiquidate;

  address[] public usersWithGoodDebt = [
    0xc70f915258483D65C3C562483653397D6B371858,
    0x5Ea145d91058F8B9fD6B02d30DB9959EB4C0af2C,
    0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84,
    0xf48Fe3471334E87D9B93a1559A049d1D1994B3a1,
    0x52ee6E1Af57889a513bf65AD7010ED36DA7FAAE3
  ];

  address public guardian = address(0x101);

  address public admin = address(0x102);

  address public collector = address(AaveV2Ethereum.COLLECTOR);

  uint256 public availableBudget = 1_000_000e8;

  ILendingPool public pool = AaveV2Ethereum.POOL;
  IAaveOracle public oracle = AaveV2Ethereum.ORACLE;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 23138376);

    steward = new ClinicStewardV2(address(AaveV2Ethereum.POOL), collector, admin, guardian, availableBudget);

    vm.prank(AaveV2Ethereum.POOL_ADMIN);
    IAccessControl(address(collector)).grantRole("FUNDS_ADMIN", address(steward));

    vm.prank(collector);
    IERC20(assetUnderlying).approve(address(steward), 100_000_000e18);

    vm.label(address(pool), "Pool");
    vm.label(address(steward), "ClinicStewardV2");
    vm.label(guardian, "Guardian");
    vm.label(admin, "Admin");
    vm.label(collector, "Collector");
    vm.label(assetUnderlying, "AssetUnderlying");
    vm.label(assetDebtToken, "AssetDebtToken");

    // make all possible liquidations for users from `usersWithBadDebt` list
    address[] memory reserves = pool.getReservesList();
    for (uint256 i = 0; i < usersWithBadDebt.length; ++i) {
      for (uint256 j = 0; j < reserves.length; ++j) {
        address vToken = _getReserveVariableDebtToken(reserves[j]);

        uint256 debtAmount = IERC20(vToken).balanceOf(usersWithBadDebt[i]);
        if (debtAmount > 0) {
          for (uint256 k = 0; k < reserves.length; ++k) {
            address aToken = _getReserveAToken(reserves[k]);

            uint256 supplyAmount = IERC20(aToken).balanceOf(usersWithBadDebt[i]);
            if (supplyAmount > 0) {
              deal(reserves[j], address(this), debtAmount * 2);

              IERC20(reserves[j]).approve(address(pool), debtAmount * 2);

              pool.liquidationCall({
                collateralAsset: reserves[k],
                debtAsset: reserves[j],
                user: usersWithBadDebt[i],
                debtToCover: type(uint256).max,
                receiveAToken: false
              });
            }

            debtAmount = IERC20(vToken).balanceOf(usersWithBadDebt[i]);
            if (debtAmount == 0) {
              break;
            }
          }
        }
      }
    }

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]);

      assertNotEq(currentDebtAmount, 0);

      totalBadDebt += currentDebtAmount;
      usersBadDebtAmounts.push(currentDebtAmount);
    }

    address collateralEligibleForLiquidationsAToken = _getReserveAToken(collateralEligibleForLiquidations);
    for (uint256 i = 0; i < usersEligibleForLiquidations.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersEligibleForLiquidations[i]);

      assertNotEq(currentDebtAmount, 0);

      totalDebtToLiquidate += currentDebtAmount;
      usersEligibleForLiquidationsDebtAmounts.push(currentDebtAmount);

      uint256 collateralBalance =
        IERC20(collateralEligibleForLiquidationsAToken).balanceOf(usersEligibleForLiquidations[i]);

      assertNotEq(collateralBalance, 0);
    }
  }

  function _getReserveAToken(address asset) internal view returns (address) {
    DataTypes.ReserveData memory reserveData = pool.getReserveData(asset);

    return reserveData.aTokenAddress;
  }

  function _getReserveVariableDebtToken(address asset) internal view returns (address) {
    DataTypes.ReserveData memory reserveData = pool.getReserveData(asset);

    return reserveData.variableDebtTokenAddress;
  }
}

contract ClinicStewardV2Test is ClinicStewardV2BaseTest {
  function test_batchRepayBadDebt() public {
    deal(assetUnderlying, collector, totalBadDebt);

    uint256 collectorBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);

    vm.prank(guardian);
    steward.batchRepayBadDebt(assetUnderlying, usersWithBadDebt, false);

    uint256 collectorBalanceAfter = IERC20(assetUnderlying).balanceOf(collector);

    assertEq(collectorBalanceBefore - collectorBalanceAfter, totalBadDebt);

    uint256 debtDollarAmount = (AaveV3Ethereum.ORACLE.getAssetPrice(assetUnderlying) * totalBadDebt)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();
    assertApproxEqRel(steward.availableBudget(), availableBudget - debtDollarAmount, 0.0001e18);

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      assertEq(IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]), 0);
    }
  }

  function test_batchRepayBadDebtUseAToken() public {
    address aToken = _getReserveAToken(assetUnderlying);
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

    uint256 debtDollarAmount = (AaveV3Ethereum.ORACLE.getAssetPrice(assetUnderlying) * totalBadDebt)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();
    assertApproxEqRel(steward.availableBudget(), availableBudget - debtDollarAmount, 0.0001e18);

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
    uint256 debtDollarAmount = (AaveV3Ethereum.ORACLE.getAssetPrice(assetUnderlying) * totalBadDebt)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();

    uint256 newAvailableBudget = debtDollarAmount / 2;

    steward = new ClinicStewardV2(address(pool), collector, admin, guardian, newAvailableBudget);

    vm.prank(AaveV2Ethereum.POOL_ADMIN);
    IAccessControl(address(collector)).grantRole("FUNDS_ADMIN", address(steward));

    vm.prank(collector);
    IERC20(assetUnderlying).approve(address(steward), 100_000_000e18);

    vm.expectPartialRevert(IClinicSteward.AvailableBudgetExceeded.selector, address(steward));

    vm.prank(guardian);
    steward.batchRepayBadDebt(assetUnderlying, usersWithBadDebt, false);
  }

  function test_batchLiquidate() public {
    uint256 collectorBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);
    uint256 stewardBalanceBefore = IERC20(assetUnderlying).balanceOf(address(steward));

    address collateralReserveDataAToken = _getReserveAToken(collateralEligibleForLiquidations);
    uint256 collectorCollateralBalanceBefore = IERC20(collateralReserveDataAToken).balanceOf(collector);
    uint256 stewardCollateralBalanceBefore = IERC20(collateralReserveDataAToken).balanceOf(address(steward));

    vm.prank(guardian);
    steward.batchLiquidate(assetUnderlying, collateralEligibleForLiquidations, usersEligibleForLiquidations, false);

    uint256 collectorBalanceAfter = IERC20(assetUnderlying).balanceOf(collector);
    uint256 stewardBalanceAfter = IERC20(assetUnderlying).balanceOf(address(steward));

    uint256 collectorCollateralBalanceAfter = IERC20(collateralReserveDataAToken).balanceOf(collector);
    uint256 stewardCollateralBalanceAfter = IERC20(collateralReserveDataAToken).balanceOf(address(steward));

    assertTrue(collectorBalanceBefore >= collectorBalanceAfter);
    assertTrue(collectorBalanceBefore - collectorBalanceAfter <= totalDebtToLiquidate);

    uint256 debtDollarAmount = (AaveV3Ethereum.ORACLE.getAssetPrice(assetUnderlying) * totalDebtToLiquidate)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();
    assertApproxEqRel(steward.availableBudget(), availableBudget - debtDollarAmount, 0.0001e18);

    assertTrue(collectorCollateralBalanceAfter >= collectorCollateralBalanceBefore);

    assertEq(stewardBalanceBefore, stewardBalanceAfter);
    assertEq(stewardCollateralBalanceBefore, stewardCollateralBalanceAfter);
  }

  function test_batchLiquidateUseAToken() public {
    address debtAToken = _getReserveAToken(assetUnderlying);
    uint256 collectorBalanceBefore = IERC20(debtAToken).balanceOf(collector);
    uint256 collectorDebtUnderlyingBalanceBefore = IERC20(assetUnderlying).balanceOf(collector);
    uint256 stewardBalanceBefore = IERC20(assetUnderlying).balanceOf(address(steward));

    address collateralAToken = _getReserveAToken(collateralEligibleForLiquidations);
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

    uint256 debtDollarAmount = (AaveV3Ethereum.ORACLE.getAssetPrice(assetUnderlying) * (totalDebtToLiquidate))
      / 10 ** IERC20Metadata(assetUnderlying).decimals();
    assertApproxEqAbs(steward.availableBudget(), availableBudget - debtDollarAmount, 0.0001e18);

    assertTrue(collectorCollateralBalanceAfter >= collectorCollateralBalanceBefore);

    assertEq(stewardBalanceBefore, stewardBalanceAfter);
    assertEq(stewardCollateralBalanceBefore, stewardCollateralBalanceAfter);
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
    uint256 debtDollarAmount = (AaveV3Ethereum.ORACLE.getAssetPrice(assetUnderlying) * totalDebtToLiquidate)
      / 10 ** IERC20Metadata(assetUnderlying).decimals();

    uint256 newAvailableBudget = debtDollarAmount / 2;

    steward = new ClinicStewardV2(address(pool), collector, admin, guardian, newAvailableBudget);

    vm.prank(AaveV2Ethereum.POOL_ADMIN);
    IAccessControl(address(collector)).grantRole("FUNDS_ADMIN", address(steward));

    vm.prank(collector);
    IERC20(assetUnderlying).approve(address(steward), 100_000_000e18);

    vm.expectPartialRevert(IClinicSteward.AvailableBudgetExceeded.selector, address(steward));

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
