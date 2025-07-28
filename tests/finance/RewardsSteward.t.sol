// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IRescuable} from "solidity-utils/contracts/utils/Rescuable.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV2Ethereum} from "aave-address-book/AaveV2Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3EthereumLidoAssets} from "aave-address-book/AaveV3EthereumLido.sol";
import {IRewardsController} from "aave-v3-origin/contracts/rewards/interfaces/IRewardsController.sol";

import {IAaveIncentivesController} from "src/finance/interfaces/IAaveIncentivesController.sol";
import {RewardsSteward, IRewardsSteward} from "src/finance/RewardsSteward.sol";

/**
 * @dev Tests for RewardsSteward contract
 * command: forge test --match-path tests/finance/RewardsStewardTest.t.sol -vvv
 */
contract RewardsStewardTest is Test {
  event ClaimedReward(address reward, uint256 amount);
  event ClaimedRewards(address[] rewards, uint256[] amounts);
  event ClaimedStkTokenRewards(address[] rewards, uint256 amount);

  address public constant STK_AAVE = 0x4da27a545c0c5B758a6BA100e3a049001de870f5;
  address public constant AAVE_INCENTIVES_CONTROLLER = 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5;
  address public guardian = makeAddr("guardian");
  address public alice = makeAddr("alice");

  RewardsSteward public steward;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 23017400); // https://etherscan.io/block/23017400

    steward = new RewardsSteward(
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      guardian,
      address(AaveV3Ethereum.COLLECTOR),
      AAVE_INCENTIVES_CONTROLLER,
      AaveV3Ethereum.DEFAULT_INCENTIVES_CONTROLLER
    );

    vm.prank(AaveV2Ethereum.EMISSION_MANAGER);
    IAaveIncentivesController(AAVE_INCENTIVES_CONTROLLER).setClaimer(
      address(AaveV3Ethereum.COLLECTOR), address(steward)
    );
    vm.prank(AaveV3Ethereum.EMISSION_MANAGER);

    IRewardsController(AaveV3Ethereum.DEFAULT_INCENTIVES_CONTROLLER).setClaimer(
      address(AaveV3Ethereum.COLLECTOR), address(steward)
    );
  }
}

contract ConstructorTest is RewardsStewardTest {
  function test_revertsIf_invalidCollector() public {
    vm.expectRevert(IRewardsSteward.InvalidZeroAddress.selector);
    new RewardsSteward(
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      guardian,
      address(0),
      AAVE_INCENTIVES_CONTROLLER,
      AaveV3Ethereum.DEFAULT_INCENTIVES_CONTROLLER
    );
  }

  function test_revertsIf_invalidAaveIncentivesController() public {
    vm.expectRevert(IRewardsSteward.InvalidZeroAddress.selector);
    new RewardsSteward(
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      guardian,
      address(AaveV3Ethereum.COLLECTOR),
      address(0),
      AaveV3Ethereum.DEFAULT_INCENTIVES_CONTROLLER
    );
  }

  function test_revertsIf_invalidRewardsController() public {
    vm.expectRevert(IRewardsSteward.InvalidZeroAddress.selector);
    new RewardsSteward(
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      guardian,
      address(AaveV3Ethereum.COLLECTOR),
      AAVE_INCENTIVES_CONTROLLER,
      address(0)
    );
  }

  function test_successful() public {
    RewardsSteward newSteward = new RewardsSteward(
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      guardian,
      address(AaveV3Ethereum.COLLECTOR),
      AAVE_INCENTIVES_CONTROLLER,
      AaveV3Ethereum.DEFAULT_INCENTIVES_CONTROLLER
    );

    assertEq(newSteward.COLLECTOR(), address(AaveV3Ethereum.COLLECTOR));
    assertEq(address(newSteward.INCENTIVES_CONTROLLER()), AAVE_INCENTIVES_CONTROLLER);
    assertEq(address(newSteward.REWARDS_CONTROLLER()), AaveV3Ethereum.DEFAULT_INCENTIVES_CONTROLLER);
  }
}

contract ClaimAllRewardsTest is RewardsStewardTest {
  address public constant STADER = 0x30D20208d987713f46DFD34EF128Bb16C404D10f;

  function test_revertsIf_invalidCaller() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));

    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.WETH_UNDERLYING;
    steward.claimAllRewards(assets);
  }

  function test_successful() public {
    uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDS_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    address[] memory rewards = new address[](5);
    rewards[0] = STADER;
    rewards[1] = AaveV3EthereumLidoAssets.WETH_A_TOKEN;
    rewards[2] = AaveV3EthereumAssets.wstETH_UNDERLYING;
    rewards[3] = AaveV3EthereumAssets.USDS_A_TOKEN;
    rewards[4] = AaveV3EthereumLidoAssets.wstETH_A_TOKEN;

    uint256[] memory amounts = new uint256[](5);
    amounts[0] = 0;
    amounts[1] = 0;
    amounts[2] = 0;
    amounts[3] = 67211841266988130642712;
    amounts[4] = 0;

    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.USDS_A_TOKEN;

    vm.expectEmit(true, true, true, true, address(steward));
    emit ClaimedRewards(rewards, amounts);
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.claimAllRewards(assets);

    assertEq(
      IERC20(AaveV3EthereumAssets.USDS_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceBefore + amounts[3]
    );
  }
}

contract ClaimRewardsTest is RewardsStewardTest {
  address public constant STADER = 0x30D20208d987713f46DFD34EF128Bb16C404D10f;

  function test_revertsIf_invalidCaller() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));

    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.USDS_A_TOKEN;
    steward.claimRewards(assets, 1 ether, AaveV3EthereumAssets.USDS_A_TOKEN);
  }

  function test_successful() public {
    uint256 amount = 1 ether;
    uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDS_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.USDS_A_TOKEN;

    vm.expectEmit(true, true, true, true, address(steward));
    emit ClaimedReward(AaveV3EthereumAssets.USDS_A_TOKEN, amount);
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.claimRewards(assets, amount, AaveV3EthereumAssets.USDS_A_TOKEN);

    assertEq(
      IERC20(AaveV3EthereumAssets.USDS_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceBefore + amount
    );
  }
}

contract ClaimStkTokenRewards is RewardsStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));

    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.USDS_A_TOKEN;
    steward.claimStkTokenRewards(assets, 1 ether);
  }

  function test_successful_noRewards() public {
    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.USDS_A_TOKEN;

    vm.expectEmit(true, true, true, true, address(steward));
    emit ClaimedStkTokenRewards(assets, 0);
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.claimStkTokenRewards(assets, 0);
  }

  function test_successful() public {
    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.USDS_A_TOKEN;

    vm.expectEmit(true, true, true, true, address(steward));
    emit ClaimedStkTokenRewards(assets, 1 ether);
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.claimStkTokenRewards(assets, 1 ether);
  }
}

contract RescueTokenTest is RewardsStewardTest {
  function test_successful_permissionless() public {
    assertEq(IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);

    uint256 aaveAmount = 1_000e18;

    deal(AaveV3EthereumAssets.AAVE_UNDERLYING, address(steward), aaveAmount);

    assertEq(IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), aaveAmount);

    uint256 initialCollectorAaveBalance =
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    steward.rescueToken(AaveV3EthereumAssets.AAVE_UNDERLYING);

    assertEq(
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      initialCollectorAaveBalance + aaveAmount
    );
    assertEq(IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);
  }

  function test_successful_governanceCaller() public {
    assertEq(IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);

    uint256 aaveAmount = 1_000e18;

    deal(AaveV3EthereumAssets.AAVE_UNDERLYING, address(steward), aaveAmount);

    assertEq(IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), aaveAmount);

    uint256 initialCollectorAaveBalance =
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.rescueToken(AaveV3EthereumAssets.AAVE_UNDERLYING);
    vm.stopPrank();

    assertEq(
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      initialCollectorAaveBalance + aaveAmount
    );
    assertEq(IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);
  }

  function test_rescueEth() public {
    uint256 mintAmount = 1_000_000e18;
    deal(address(steward), mintAmount);

    uint256 collectorBalanceBefore = address(AaveV3Ethereum.COLLECTOR).balance;

    steward.rescueEth();

    uint256 collectorBalanceAfter = address(AaveV3Ethereum.COLLECTOR).balance;

    assertEq(collectorBalanceAfter - collectorBalanceBefore, mintAmount);
    assertEq(address(steward).balance, 0);
  }
}

contract MaxRescueTest is RewardsStewardTest {
  function test_maxRescue() public {
    assertEq(steward.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), 0);

    uint256 mintAmount = 1_000_000e18;
    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(steward), mintAmount);

    assertEq(steward.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), mintAmount);
  }
}
