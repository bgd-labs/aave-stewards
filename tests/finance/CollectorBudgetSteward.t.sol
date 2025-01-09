// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {Ownable} from "solidity-utils/contracts/oz-common/Ownable.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {CollectorUtils} from "aave-helpers/src/CollectorUtils.sol";
import {ICollector} from "aave-address-book/common/ICollector.sol";

import {CollectorBudgetSteward, ICollectorBudgetSteward} from "src/finance/CollectorBudgetSteward.sol";

/**
 * Helper contract to mock price feed calls
 */
contract MockOracle {
  function decimals() external pure returns (uint8) {
    return 8;
  }

  function latestAnswer() external pure returns (int256) {
    return 0;
  }
}

/*
 * Oracle missing `decimals` implementation thus invalid.
 */
contract InvalidMockOracle {
  function latestAnswer() external pure returns (int256) {
    return 0;
  }
}

/**
 * @dev Test for Finance Steward contract
 * command: forge test -vvv --match-path tests/finance/CollectorBudgetSteward.t.sol
 */
contract CollectorBudgetStewardTest is Test {
  event SwapRequested(
    address milkman,
    address indexed fromToken,
    address indexed toToken,
    address fromOracle,
    address toOracle,
    uint256 amount,
    address indexed recipient,
    uint256 slippage
  );
  event BudgetUpdate(address indexed token, uint256 newAmount);
  event SwapApprovedToken(address indexed token, address indexed oracleUSD);
  event ReceiverWhitelisted(address indexed receiver);
  event Upgraded(address indexed impl);

  address public constant USDC_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  address public constant AAVE_PRICE_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
  address public constant EXECUTOR = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;
  address public constant guardian = address(82);
  address public constant alice = address(43);
  CollectorBudgetSteward public steward;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21580838); // https://etherscan.io/block/21580838
    steward =
      new CollectorBudgetSteward(GovernanceV3Ethereum.EXECUTOR_LVL_1, guardian, address(AaveV3Ethereum.COLLECTOR));

    vm.label(0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c, "Collector");
    vm.label(alice, "Alice");
    vm.label(guardian, "Guardian");
    vm.label(EXECUTOR, "Executor");
    vm.label(address(steward), "CollectorBudgetSteward");

    vm.startPrank(EXECUTOR);
    AaveV3Ethereum.COLLECTOR.setFundsAdmin(address(steward));
    Ownable(MiscEthereum.AAVE_SWAPPER).transferOwnership(address(steward));

    vm.stopPrank();

    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(AaveV3Ethereum.COLLECTOR), 1_000_000e6);
  }
}

contract Function_approve is CollectorBudgetStewardTest {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedReceiver() public {
    vm.startPrank(guardian);

    vm.expectRevert(ICollectorBudgetSteward.UnrecognizedReceiver.selector);
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBalance() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.startPrank(guardian);

    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.expectRevert(ICollectorBudgetSteward.ExceedsBalance.selector);
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, currentBalance + 1_000e6);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBudget() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    vm.expectRevert(abi.encodeWithSelector(ICollectorBudgetSteward.ExceedsBudget.selector, 1_000e6));
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_001e6);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.expectEmit(true, true, true, true, address(steward));
    emit BudgetUpdate(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertEq(IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).allowance(address(AaveV3Ethereum.COLLECTOR), alice), 0);

    vm.startPrank(guardian);
    steward.approve(AaveV3EthereumAssets.USDC_UNDERLYING, alice, 1_000e6);
    vm.stopPrank();

    assertEq(IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).allowance(address(AaveV3Ethereum.COLLECTOR), alice), 1_000e6);
  }
}

contract Function_transfer is CollectorBudgetStewardTest {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
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

contract Function_createStream is CollectorBudgetStewardTest {
  uint256 public constant DURATION = 1 days;

  function test_revertsIf_notOwnerOrQuardian() public {
    ICollectorBudgetSteward.StreamData memory data = ICollectorBudgetSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6, block.timestamp, block.timestamp + DURATION
    );

    vm.startPrank(alice);

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
    steward.createStream(alice, data);
    vm.stopPrank();
  }

  function test_resvertsIf_invalidDate() public {
    ICollectorBudgetSteward.StreamData memory data = ICollectorBudgetSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6, block.timestamp - 1, block.timestamp + DURATION
    );

    vm.startPrank(guardian);

    vm.expectRevert(ICollectorBudgetSteward.InvalidDate.selector);
    steward.createStream(alice, data);

    data = ICollectorBudgetSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6, block.timestamp, block.timestamp - 1
    );

    vm.expectRevert(ICollectorBudgetSteward.InvalidDate.selector);
    steward.createStream(alice, data);

    vm.stopPrank();
  }

  function test_resvertsIf_unrecognizedReceiver() public {
    ICollectorBudgetSteward.StreamData memory data = ICollectorBudgetSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6, block.timestamp, block.timestamp + DURATION
    );

    vm.startPrank(guardian);

    vm.expectRevert(ICollectorBudgetSteward.UnrecognizedReceiver.selector);
    steward.createStream(alice, data);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBalance() public {
    uint256 currentBalance = IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    ICollectorBudgetSteward.StreamData memory data = ICollectorBudgetSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING, currentBalance + 1_000e6, block.timestamp, block.timestamp + DURATION
    );

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);

    vm.startPrank(guardian);

    vm.expectRevert(ICollectorBudgetSteward.ExceedsBalance.selector);
    steward.createStream(alice, data);
    vm.stopPrank();
  }

  function test_resvertsIf_exceedsBudget() public {
    ICollectorBudgetSteward.StreamData memory data = ICollectorBudgetSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING, 1_001e6, block.timestamp, block.timestamp + DURATION
    );

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);

    vm.expectRevert(abi.encodeWithSelector(ICollectorBudgetSteward.ExceedsBudget.selector, 1_000e6));
    steward.createStream(alice, data);
    vm.stopPrank();
  }

  function test_success() public {
    ICollectorBudgetSteward.StreamData memory data = ICollectorBudgetSteward.StreamData(
      AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6, block.timestamp, block.timestamp + DURATION
    );

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setWhitelistedReceiver(alice);
    steward.increaseBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    uint256 streamId = AaveV3Ethereum.COLLECTOR.getNextStreamId();

    vm.startPrank(guardian);
    steward.createStream(alice, data);
    vm.stopPrank();

    vm.warp(block.timestamp + 5 days);

    vm.startPrank(alice);
    AaveV3Ethereum.COLLECTOR.withdrawFromStream(streamId, 1);
    vm.stopPrank();
  }
}

contract Function_cancelStream is CollectorBudgetStewardTest {
  uint256 constant STREAM_ID = uint256(100050);

  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
    steward.cancelStream(STREAM_ID);
    vm.stopPrank();
  }

  function test_success() public {
    (address sender,,,,,,,) = AaveV3Ethereum.COLLECTOR.getStream(STREAM_ID);
    assertNotEq(sender, address(0));
    vm.startPrank(guardian);
    steward.cancelStream(STREAM_ID);
    vm.stopPrank();
  }
}

contract Function_increaseBudget is CollectorBudgetStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert("Ownable: caller is not the owner");
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

    vm.expectRevert("Ownable: caller is not the owner");
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

    vm.expectRevert("Ownable: caller is not the owner");
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
