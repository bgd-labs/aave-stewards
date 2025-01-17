// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {Ownable} from "solidity-utils/contracts/oz-common/Ownable.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3EthereumLido} from "aave-address-book/AaveV3EthereumLido.sol";
import {AaveV3EthereumEtherFi, AaveV3EthereumEtherFiAssets} from "aave-address-book/AaveV3EthereumEtherFi.sol";
import {AaveV2Ethereum, AaveV2EthereumAssets} from "aave-address-book/AaveV2Ethereum.sol";
import {CollectorUtils} from "aave-helpers/src/CollectorUtils.sol";

import {PoolExposureSteward, IPoolExposureSteward} from "src/finance/PoolExposureSteward.sol";

/**
 * @dev Tests for PoolSteward contract
 * command: forge test -vvv --match-path tests/finance/PoolSteward.t.sol
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
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21580838); // https://etherscan.io/block/21580838

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
    AaveV3Ethereum.COLLECTOR.setFundsAdmin(address(steward));

    vm.stopPrank();

    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(AaveV3Ethereum.COLLECTOR), 1_000_000e6);
  }
}

contract Function_depositV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
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

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
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

  function test_revertsIf_arrayLengthMismatch() public {
    uint256[] memory amounts = new uint256[](1);
    address[] memory underlyings = new address[](2);

    vm.startPrank(guardian);
    vm.expectRevert(IPoolExposureSteward.MismatchingArrayLength.selector);
    steward.migrateV2toV3(address(AaveV2Ethereum.POOL), address(AaveV3Ethereum.POOL), underlyings, amounts);
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

  function test_success_arrays() public {
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1_000e6;
    address[] memory underlyings = new address[](1);
    underlyings[0] = AaveV3EthereumAssets.USDC_UNDERLYING;

    uint256 balanceV2Before = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 balanceV3Before = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);

    steward.migrateV2toV3(address(AaveV2Ethereum.POOL), address(AaveV3Ethereum.POOL), underlyings, amounts);

    assertLt(IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV2Before);
    assertGt(IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV3Before);
    vm.stopPrank();
  }
}

contract Function_migrateBetweenV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
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

  function test_revertsIf_arrayLengthMismatch() public {
    uint256[] memory amounts = new uint256[](1);
    address[] memory underlyings = new address[](2);

    vm.startPrank(guardian);
    vm.expectRevert(IPoolExposureSteward.MismatchingArrayLength.selector);
    steward.migrateBetweenV3(address(AaveV3Ethereum.POOL), address(AaveV3EthereumEtherFi.POOL), underlyings, amounts);
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

  function test_success_arrays() public {
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1_000e6;
    address[] memory underlyings = new address[](1);
    underlyings[0] = AaveV3EthereumAssets.USDC_UNDERLYING;

    uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 balanceBeforeEtherFi =
      IERC20(AaveV3EthereumEtherFiAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);

    steward.migrateBetweenV3(address(AaveV3Ethereum.POOL), address(AaveV3EthereumEtherFi.POOL), underlyings, amounts);

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

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
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

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
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

    vm.expectRevert("Ownable: caller is not the owner");
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

    vm.expectRevert("Ownable: caller is not the owner");
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
