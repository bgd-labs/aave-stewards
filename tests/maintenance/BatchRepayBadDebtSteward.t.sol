// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {IPool, IAToken, DataTypes} from "aave-address-book/AaveV3.sol";
import {AaveV3Avalanche, AaveV3AvalancheAssets} from "aave-address-book/AaveV3Avalanche.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";

import {IBatchRepayBadDebtSteward} from "../../src/maintenance/interfaces/IBatchRepayBadDebtSteward.sol";
import {BatchRepayBadDebtSteward} from "../../src/maintenance/BatchRepayBadDebtSteward.sol";

contract BatchRepayBadDebtStewardBaseTest is Test {
  BatchRepayBadDebtSteward public steward;

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
    0xb5FDf295d6C7a4E7f466EDb4B4d9aEAaeF37A9Dd,
    0x07d89372dAa468575b7fbd814E4A9D59e38d414b,
    0x741BeB5C2D744f8aCc8f54fbACa1880911D2cB32,
    0x6821Aceb02Bd2a64d0900cBf193A543aB41d397e,
    0x04249B0B26eA4a91F4F36d95c6CD11a207e22768,
    0x35cBb2525e442488Ed51cE524b4000D4d0d01acC
  ];
  address[] public collateralsEligibleForLiquidations = [
    AaveV3AvalancheAssets.USDt_UNDERLYING,
    AaveV3AvalancheAssets.DAIe_UNDERLYING,
    AaveV3AvalancheAssets.WAVAX_UNDERLYING,
    AaveV3AvalancheAssets.USDC_UNDERLYING,
    AaveV3AvalancheAssets.USDC_UNDERLYING,
    AaveV3AvalancheAssets.USDC_UNDERLYING
  ];
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

  address public repayer = address(0x100);

  address public guardian = address(0x101);

  address public owner = address(0x102);

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("avalanche"), 55793443); // https://snowscan.xyz/block/55793443

    steward = new BatchRepayBadDebtSteward(address(AaveV3Avalanche.POOL), guardian, owner);

    assertEq(steward.guardian(), guardian);
    assertEq(steward.owner(), owner);

    vm.label(address(AaveV3Avalanche.POOL), "Pool");
    vm.label(address(steward), "BatchRepayBadDebtSteward");
    vm.label(repayer, "Repayer");
    vm.label(assetUnderlying, "AssetUnderlying");
    vm.label(assetDebtToken, "AssetDebtToken");

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]);

      assertNotEq(currentDebtAmount, 0);

      totalBadDebt += currentDebtAmount;
      usersBadDebtAmounts.push(currentDebtAmount);
    }

    for (uint256 i = 0; i < usersEligibleForLiquidations.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersEligibleForLiquidations[i]);

      assertNotEq(currentDebtAmount, 0);

      totalDebtToLiquidate += currentDebtAmount;
      usersEligibleForLiquidationsDebtAmounts.push(currentDebtAmount);

      DataTypes.ReserveDataLegacy memory collateralReserveData =
        AaveV3Avalanche.POOL.getReserveData(collateralsEligibleForLiquidations[i]);
      uint256 collateralBalance = IERC20(collateralReserveData.aTokenAddress).balanceOf(usersEligibleForLiquidations[i]);

      assertNotEq(collateralBalance, 0);
    }
  }
}

contract BatchRepayBadDebtStewardTest is BatchRepayBadDebtStewardBaseTest {
  function test_batchRepayBadDebt() public {
    deal(assetUnderlying, repayer, totalBadDebt);
    vm.prank(repayer);
    IERC20(assetUnderlying).approve(address(steward), totalBadDebt);

    vm.prank(repayer);
    steward.batchRepayBadDebt(assetUnderlying, usersWithBadDebt);

    assertEq(IERC20(assetUnderlying).balanceOf(repayer), 0);

    for (uint256 i = 0; i < usersWithBadDebt.length; i++) {
      assertEq(IERC20(assetDebtToken).balanceOf(usersWithBadDebt[i]), 0);
    }
  }

  function test_batchLiquidate() public {
    deal(assetUnderlying, repayer, totalDebtToLiquidate);

    vm.prank(repayer);
    IERC20(assetUnderlying).approve(address(steward), totalDebtToLiquidate);

    vm.prank(repayer);
    steward.batchLiquidate(assetUnderlying, collateralsEligibleForLiquidations, usersEligibleForLiquidations);

    assertEq(IERC20(assetUnderlying).balanceOf(repayer), 0);

    for (uint256 i = 0; i < usersEligibleForLiquidations.length; i++) {
      uint256 currentDebtAmount = IERC20(assetDebtToken).balanceOf(usersEligibleForLiquidations[i]);

      DataTypes.ReserveDataLegacy memory collateralReserveData =
        AaveV3Avalanche.POOL.getReserveData(collateralsEligibleForLiquidations[i]);
      uint256 collateralBalance = IERC20(collateralReserveData.aTokenAddress).balanceOf(usersEligibleForLiquidations[i]);

      assertTrue(currentDebtAmount <= 1 || collateralBalance <= 1);
    }
  }

  function test_rescueToken_with_guardian() public {
    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, address(steward), mintAmount);

    vm.prank(guardian);
    steward.rescueToken(assetUnderlying, address(this));

    assertEq(IERC20(assetUnderlying).balanceOf(address(this)), mintAmount);
    assertEq(IERC20(assetUnderlying).balanceOf(address(steward)), 0);
  }

  function test_rescueToken_with_owner() public {
    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, address(steward), mintAmount);

    vm.prank(owner);
    steward.rescueToken(assetUnderlying, address(this));

    assertEq(IERC20(assetUnderlying).balanceOf(address(this)), mintAmount);
    assertEq(IERC20(assetUnderlying).balanceOf(address(steward)), 0);
  }

  function test_reverts_rescueToken_with_notGuardianOrOwner(address caller) public {
    vm.assume(caller != guardian && caller != owner);

    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, address(steward), mintAmount);

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");

    vm.prank(caller);
    steward.rescueToken(assetUnderlying, address(this));
  }

  receive() external payable {}

  function test_rescueEth_with_guardian() public {
    uint256 mintAmount = 1_000_000e18;
    deal(address(steward), mintAmount);

    uint256 addressThisBalanceBefore = address(this).balance;

    vm.prank(guardian);
    steward.rescueEth(address(this));

    uint256 addressThisBalanceAfter = address(this).balance;

    assertEq(addressThisBalanceAfter - addressThisBalanceBefore, mintAmount);
    assertEq(address(steward).balance, 0);
  }

  function test_rescueEth_with_owner() public {
    uint256 mintAmount = 1_000_000e18;
    deal(address(steward), mintAmount);

    uint256 addressThisBalanceBefore = address(this).balance;

    vm.prank(owner);
    steward.rescueEth(address(this));

    uint256 addressThisBalanceAfter = address(this).balance;

    assertEq(addressThisBalanceAfter - addressThisBalanceBefore, mintAmount);
    assertEq(address(steward).balance, 0);
  }

  function test_reverts_rescueEth_with_notGuardianOrOwner(address caller) public {
    vm.assume(caller != guardian && caller != owner);

    uint256 mintAmount = 1_000_000e18;
    deal(address(steward), mintAmount);

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");

    vm.prank(caller);
    steward.rescueEth(address(this));
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

  function test_reverts_getDebtAmount_duplicatedUsers() public {
    address[] memory passedArray = new address[](2);
    passedArray[0] = usersWithBadDebt[0];
    passedArray[1] = usersWithBadDebt[0];

    vm.expectRevert(
      abi.encodePacked(IBatchRepayBadDebtSteward.UsersShouldBeDifferent.selector, uint256(uint160(passedArray[0])))
    );

    steward.getDebtAmount(assetUnderlying, passedArray);
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

  function test_maxRescue() public {
    assertEq(steward.maxRescue(assetUnderlying), 0);

    uint256 mintAmount = 1_000_000e18;
    deal(assetUnderlying, address(steward), mintAmount);

    assertEq(steward.maxRescue(assetUnderlying), mintAmount);
  }
}
