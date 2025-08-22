// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {RescuableBase, IRescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";
import {IRewardsController} from "aave-v3-origin/contracts/rewards/interfaces/IRewardsController.sol";

import {IRewardsSteward} from "./interfaces/IRewardsSteward.sol";

/**
 * @title RewardsSteward
 * @author efecarranza  (Tokenlogic)
 * @notice Claims rewards on behalf of the Collector.
 *
 * -- Security Considerations
 * Anyone can claim rewards at any time permissionlessly even if the DAO did not want to claim rewards at that time.
 *
 * -- Permissions
 * The contract is fully permissionless.
 * All token interactions start and end on the Collector, so no funds ever leave the DAO's possession at any point in time.
 */
contract RewardsSteward is IRewardsSteward, RescuableBase {
  /// @inheritdoc IRewardsSteward
  address public immutable COLLECTOR;

  /// @inheritdoc IRewardsSteward
  IRewardsController public immutable REWARDS_CONTROLLER;

  constructor(address collector, address rewardsController) {
    if (collector == address(0)) revert InvalidZeroAddress();
    if (rewardsController == address(0)) revert InvalidZeroAddress();

    COLLECTOR = collector;
    REWARDS_CONTROLLER = IRewardsController(rewardsController);
  }

  /// @inheritdoc IRewardsSteward
  function claimAllRewards(address[] calldata assets) external {
    (address[] memory rewardsList, uint256[] memory claimedAmounts) =
      REWARDS_CONTROLLER.claimAllRewardsOnBehalf(assets, COLLECTOR, COLLECTOR);

    emit ClaimedRewards(rewardsList, claimedAmounts);
  }

  /// @inheritdoc IRewardsSteward
  function claimRewards(address[] calldata assets, uint256 amount, address reward) external {
    uint256 claimed = REWARDS_CONTROLLER.claimRewardsOnBehalf(assets, amount, COLLECTOR, COLLECTOR, reward);

    emit ClaimedReward(reward, claimed);
  }

  /// @inheritdoc IRewardsSteward
  function rescueToken(address token) external {
    _emergencyTokenTransfer(token, COLLECTOR, type(uint256).max);
  }

  /// @inheritdoc IRewardsSteward
  function rescueEth() external {
    _emergencyEtherTransfer(COLLECTOR, address(this).balance);
  }

  /// @inheritdoc IRescuableBase
  function maxRescue(address token) public view override(RescuableBase) returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }
}
