// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {CollectorUtils} from "aave-helpers/src/CollectorUtils.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";

import {CollectorBudgetSteward, ICollectorBudgetSteward} from "src/finance/CollectorBudgetSteward.sol";

/**
 * @dev Test for Finance Steward contract
 * command: forge test -vvv --match-path tests/finance/CollectorBudgetSteward.t.sol
 */
contract CollectorBudgetStewardTest is Test {
  event BudgetUpdate(address indexed token, uint256 newAmount);
  event ReceiverWhitelisted(address indexed receiver);

  address public constant EXECUTOR = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;
  address public constant guardian = address(82);
  address public constant alice = address(43);
  CollectorBudgetSteward public steward;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21945825); // https://etherscan.io/block/21945825
    steward =
      new CollectorBudgetSteward(GovernanceV3Ethereum.EXECUTOR_LVL_1, guardian, address(AaveV3Ethereum.COLLECTOR));

    vm.label(0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c, "Collector");
    vm.label(alice, "Alice");
    vm.label(guardian, "Guardian");
    vm.label(EXECUTOR, "Executor");
    vm.label(address(steward), "CollectorBudgetSteward");

    vm.startPrank(EXECUTOR);
    IAccessControl(address(AaveV3Ethereum.COLLECTOR)).grantRole(bytes32("FUNDS_ADMIN"), address(steward));
    vm.stopPrank();

    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(AaveV3Ethereum.COLLECTOR), 1_000_000e6);
  }
}

contract Function_transfer is CollectorBudgetStewardTest {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedReceiver() public {
    vm.startPrank(guardian);

    vm.expectRevert(ICollectorBudgetSteward.UnrecognizedReceiver.selector);
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBalance() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.expectRevert(ICollectorBudgetSteward.ExceedsBalance.selector);
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, currentBalance + 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBudget() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    vm.expectRevert(abi.encodeWithSelector(ICollectorBudgetSteward.ExceedsBudget.selector, 1_000e6));
    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_001e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    uint256 balance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);

    steward.transfer(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);

    assertEq(
      IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balance - 1_000e6
    );
    vm.stopPrank();
  }
}

contract Function_increaseBudget is CollectorBudgetStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_success() public {
    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 0);
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();

    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 1_000e6);
  }
}

contract Function_decreaseBudget is CollectorBudgetStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.decreaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_decreaseBudgetLessThanTotal() public {
    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 0);

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 1_000e6);

    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 750e6);
    steward.decreaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 250e6);

    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 750e6);
    vm.stopPrank();
  }

  function test_success() public {
    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 0);

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.decreaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    assertEq(steward.tokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING), 0);
    vm.stopPrank();
  }
}

contract Function_setWhitelistedReceiver is CollectorBudgetStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setWhitelistedReceiver(alice);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ReceiverWhitelisted(alice);
    steward.setWhitelistedReceiver(alice);
    vm.stopPrank();
  }
}
