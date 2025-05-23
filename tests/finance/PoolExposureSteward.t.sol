// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IRescuable} from "solidity-utils/contracts/utils/Rescuable.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3EthereumLido} from "aave-address-book/AaveV3EthereumLido.sol";
import {AaveV3EthereumEtherFi, AaveV3EthereumEtherFiAssets} from "aave-address-book/AaveV3EthereumEtherFi.sol";
import {AaveV2Ethereum, AaveV2EthereumAssets} from "aave-address-book/AaveV2Ethereum.sol";
import {CollectorUtils} from "aave-helpers/src/CollectorUtils.sol";
import {PoolExposureSteward, IPoolExposureSteward} from "src/finance/PoolExposureSteward.sol";

/**
 * @dev Tests for PoolSteward contract
 * command: forge test --match-path tests/finance/PoolExposureSteward.t.sol -vvv
 */
contract PoolExposureStewardTest is Test {
  event ApprovedV2Pool(address indexed pool);
  event ApprovedV3Pool(address indexed pool);
  event RevokedV2Pool(address indexed pool);
  event RevokedV3Pool(address indexed pool);

  address public constant EXECUTOR = AaveV3Ethereum.ACL_ADMIN;
  address public constant guardian = address(82);
  address public alice = address(43);
  PoolExposureSteward public steward;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21918940); // https://etherscan.io/block/21819625

    address[] memory v2Pools = new address[](1);
    v2Pools[0] = address(AaveV2Ethereum.POOL);

    address[] memory v3Pools = new address[](3);
    v3Pools[0] = address(AaveV3Ethereum.POOL);
    v3Pools[1] = address(AaveV3EthereumEtherFi.POOL);
    v3Pools[2] = address(AaveV3EthereumLido.POOL);
    steward = new PoolExposureSteward(
      GovernanceV3Ethereum.EXECUTOR_LVL_1, guardian, address(AaveV3Ethereum.COLLECTOR), v2Pools, v3Pools
    );

    vm.label(address(AaveV3Ethereum.COLLECTOR), "Collector");
    vm.label(alice, "Alice");
    vm.label(guardian, "Guardian");
    vm.label(EXECUTOR, "Executor");
    vm.label(address(steward), "PoolSteward");

    vm.prank(EXECUTOR);
    IAccessControl(address(AaveV3Ethereum.COLLECTOR)).grantRole("FUNDS_ADMIN", address(steward));

    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(AaveV3Ethereum.COLLECTOR), 1_000_000e6);
  }
}

contract Function_depositV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.depositV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.depositV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    vm.startPrank(guardian);

    steward.depositV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertGt(IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceBefore);
    vm.stopPrank();
  }
}

contract Function_migrateV2toV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.migrateV2toV3(
      address(AaveV2Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.migrateV2toV3(
      address(AaveV2Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0
    );
    vm.stopPrank();
  }

  function test_revertsIf_invalidV2Pool() public {
    vm.startPrank(guardian);

    vm.expectRevert(IPoolExposureSteward.UnrecognizedPool.selector);
    steward.migrateV2toV3(
      makeAddr("fake-pool"), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );
  }

  function test_revertsIf_invalidV3Pool() public {
    vm.startPrank(guardian);

    vm.expectRevert(IPoolExposureSteward.UnrecognizedPool.selector);
    steward.migrateV2toV3(
      address(AaveV2Ethereum.POOL), makeAddr("fake-pool"), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );
  }

  function test_success() public {
    uint256 balanceV2Before = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 balanceV3Before = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);

    steward.migrateV2toV3(
      address(AaveV2Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );

    assertLt(IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV2Before);
    assertGt(IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV3Before);
    vm.stopPrank();
  }
}

contract Function_migrateBetweenV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.migrateBetweenV3(
      address(AaveV3Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.migrateBetweenV3(
      address(AaveV3Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0
    );
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 balanceBeforeEtherFi =
      IERC20(AaveV3EthereumEtherFiAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.prank(guardian);
    steward.migrateBetweenV3(
      address(AaveV3Ethereum.POOL), address(AaveV3EthereumEtherFi.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );

    assertApproxEqAbs(
      IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceBefore - 1_000e6, 1
    );
    assertApproxEqAbs(
      IERC20(AaveV3EthereumEtherFiAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      balanceBeforeEtherFi + 1_000e6,
      1
    );
  }
}

contract Function_withdrawV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.withdrawV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.withdrawV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceV3Before = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);
    steward.withdrawV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertLt(IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV3Before);
    vm.stopPrank();
  }
}

contract Function_withdrawV2 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.withdrawV2(address(AaveV2Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.withdrawV2(address(AaveV2Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(guardian);

    uint256 balanceV2Before = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);
    steward.withdrawV2(address(AaveV2Ethereum.POOL), AaveV2EthereumAssets.USDC_UNDERLYING, 1_0_000e6);

    assertLt(IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV2Before);
    vm.stopPrank();
  }
}

contract Function_approvePool is PoolExposureStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.approvePool(address(AaveV3Ethereum.POOL), true);
    vm.stopPrank();
  }

  function test_revertsIf_invalidZeroAddress() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectRevert(IPoolExposureSteward.InvalidZeroAddress.selector);
    steward.approvePool(address(0), true);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ApprovedV3Pool(address(50));
    steward.approvePool(address(50), true);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ApprovedV2Pool(address(51));
    steward.approvePool(address(51), false);
    vm.stopPrank();
  }
}

contract Function_revokePool is PoolExposureStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.revokePool(address(AaveV3Ethereum.POOL), true);
    vm.stopPrank();
  }

  function test_revertsIf_invalidZeroAddress() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectRevert(IPoolExposureSteward.UnrecognizedPool.selector);
    steward.revokePool(address(0), true);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit RevokedV3Pool(address(AaveV3Ethereum.POOL));
    steward.revokePool(address(AaveV3Ethereum.POOL), true);

    vm.expectEmit(true, true, true, true, address(steward));
    emit RevokedV2Pool(address(AaveV2Ethereum.POOL));
    steward.revokePool(address(AaveV2Ethereum.POOL), false);
    vm.stopPrank();
  }
}

contract Function_emergencyTokenTransfer is PoolExposureStewardTest {
  function test_successful_permissionless() public {
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);

    uint256 aaveAmount = 1_000e18;

    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(steward), aaveAmount);

    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), aaveAmount);

    uint256 initialCollectorAaveBalance =
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR));

    steward.rescueToken(AaveV2EthereumAssets.AAVE_UNDERLYING);

    assertEq(
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorAaveBalance + aaveAmount
    );
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);
  }

  function test_successful_governanceCaller() public {
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);

    uint256 aaveAmount = 1_000e18;

    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(steward), aaveAmount);

    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), aaveAmount);

    uint256 initialCollectorAaveBalance =
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR));

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.rescueToken(AaveV2EthereumAssets.AAVE_UNDERLYING);
    vm.stopPrank();

    assertEq(
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorAaveBalance + aaveAmount
    );
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);
  }

  function test_rescueEth() public {
    uint256 mintAmount = 1_000_000e18;
    deal(address(steward), mintAmount);

    uint256 collectorBalanceBefore = address(AaveV2Ethereum.COLLECTOR).balance;

    steward.rescueEth();

    uint256 collectorBalanceAfter = address(AaveV2Ethereum.COLLECTOR).balance;

    assertEq(collectorBalanceAfter - collectorBalanceBefore, mintAmount);
    assertEq(address(steward).balance, 0);
  }
}

contract Function_maxRescue is PoolExposureStewardTest {
  function test_maxRescue() public {
    assertEq(steward.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), 0);

    uint256 mintAmount = 1_000_000e18;
    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(steward), mintAmount);

    assertEq(steward.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), mintAmount);
  }
}
