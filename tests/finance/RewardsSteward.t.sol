// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IRescuable} from "solidity-utils/contracts/utils/Rescuable.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {IRewardsController} from "aave-v3-origin/contracts/rewards/interfaces/IRewardsController.sol";

import {RewardsSteward, IRewardsSteward} from "src/finance/RewardsSteward.sol";

/**
 * @dev Tests for RewardsSteward contract
 * command: forge test --match-path tests/finance/RewardsStewardTest.t.sol -vvv
 */
contract RewardsStewardTest is Test {
  event ClaimedReward(address reward, uint256 amount);
  event ClaimedRewards(address[] rewards, uint256[] amounts);

  address public constant EXECUTOR = AaveV3Ethereum.ACL_ADMIN;
  address public constant guardian = address(82);
  address public alice = address(43);

  RewardsSteward public steward;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 23017400); // https://etherscan.io/block/23017400

    steward = new RewardsSteward(
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      guardian,
      address(AaveV3Ethereum.COLLECTOR),
      AaveV3Ethereum.DEFAULT_INCENTIVES_CONTROLLER
    );

    vm.prank(AaveV3Ethereum.EMISSION_MANAGER);
    IRewardsController(AaveV3Ethereum.DEFAULT_INCENTIVES_CONTROLLER).setClaimer(
      address(AaveV3Ethereum.COLLECTOR), address(steward)
    );
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
