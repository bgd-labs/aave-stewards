// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
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

interface TempCollector {
  function grantRole(bytes32 role, address account) external;
}

/**
 * @dev Tests for PoolSteward contract
 * command: forge test --match-path tests/finance/PoolExposureSteward.t.sol -vvv
 */
contract PoolExposureStewardTest is Test {
  event ApprovedV2Pool(address indexed pool);
  event ApprovedV3Pool(address indexed pool);
  event RevokedV2Pool(address indexed pool);
  event RevokedV3Pool(address indexed pool);

  address public constant USDC_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  address public constant AAVE_PRICE_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
  address public constant EXECUTOR = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;
  address public constant guardian = address(82);
  address public alice = address(43);
  PoolExposureSteward public steward;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21819625); // https://etherscan.io/block/21819625

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

    vm.startPrank(EXECUTOR);
    TempCollector(address(AaveV3Ethereum.COLLECTOR)).grantRole(bytes32("FUNDS_ADMIN"), address(steward)); // TODO: Remove once aave-address-book is updated

    vm.stopPrank();

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

    vm.startPrank(guardian);

    steward.migrateBetweenV3(
      address(AaveV3Ethereum.POOL), address(AaveV3EthereumEtherFi.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );

    assertEq(
      IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceBefore - 1_000e6
    );
    assertEq(
      IERC20(AaveV3EthereumEtherFiAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      balanceBeforeEtherFi + 1_000e6
    );
    vm.stopPrank();
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
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert(IRescuable.OnlyRescueGuardian.selector);
    steward.emergencyTokenTransfer(AaveV2EthereumAssets.BAL_UNDERLYING, address(AaveV2Ethereum.COLLECTOR), 1_000e6);
  }

  function test_successful_governanceCaller() public {
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);

    uint256 aaveAmount = 1_000e18;

    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(steward), aaveAmount);

    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), aaveAmount);

    uint256 initialCollectorUsdcBalance =
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR));

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.emergencyTokenTransfer(AaveV2EthereumAssets.AAVE_UNDERLYING, address(AaveV2Ethereum.COLLECTOR), aaveAmount);
    vm.stopPrank();

    assertEq(
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorUsdcBalance + aaveAmount
    );
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);
  }
}
