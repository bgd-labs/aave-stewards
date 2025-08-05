// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRewardsController} from "aave-v3-origin/contracts/rewards/interfaces/IRewardsController.sol";

/**
 * @title IRewardsSteward
 * @author Aave/TokenLogic
 * @notice Defines the behaviour of a IRewardsSteward
 */
interface IRewardsSteward {
  /// @dev Provided address cannot be the zero-address
  error InvalidZeroAddress();

  /// @dev Emitted when a token reward is claimed for a given list of assets
  /// @param reward The token awarded
  /// @param amount The amount of token awarded
  event ClaimedReward(address reward, uint256 amount);

  /// @dev Emitted when all rewards are claimed for a given list of assets
  /// @param rewards The list of tokens awarded
  /// @param amounts The amounts of tokens awarded
  event ClaimedRewards(address[] rewards, uint256[] amounts);

  /// @notice Claims all pending rewards on behalf of the Collector for a list of assets
  /// @param assets List of assets to claim rewards for
  function claimAllRewards(address[] calldata assets) external;

  /// @notice Claims an amount of pending rewards for a specific token on behalf of the Collector for a list of assets
  /// @param assets List of assets to claim rewards for
  /// @param amount The amount of rewards to claim
  /// @param reward The token awarded
  function claimRewards(address[] calldata assets, uint256 amount, address reward) external;

  /// @notice Rescues the specified token back to the Collector
  /// @param token The address of the ERC20 token to rescue
  function rescueToken(address token) external;

  /// @notice Rescues ETH from the contract back to the Collector
  function rescueEth() external;

  /// @notice Returns instance of Aave V3 Collector
  function COLLECTOR() external view returns (address);

  /// @notice Returns instance of RewardsController
  function REWARDS_CONTROLLER() external view returns (IRewardsController);
}
