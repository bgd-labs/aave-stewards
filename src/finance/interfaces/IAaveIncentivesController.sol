// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAaveIncentivesController {
  /**
   * @dev Claims reward for an user on behalf, on all the assets of the lending pool, accumulating the pending rewards. The caller must
   * be whitelisted via "allowClaimOnBehalf" function by the RewardsAdmin role manager
   * @param assets The assets to claim rewards for
   * @param amount Amount of rewards to claim
   * @param user Address to check and claim rewards
   * @param to Address that will be receiving the rewards
   * @return Rewards claimed
   *
   */
  function claimRewardsOnBehalf(address[] calldata assets, uint256 amount, address user, address to)
    external
    returns (uint256);

  /**
   * @dev Checks rewards balance for a given user
   * @param assets The assets to claim rewards for
   * @param user Address to check and claim rewards
   */
  function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);

  /**
   * @dev Whitelists an address to claim the rewards on behalf of another address
   * @param user The address of the user
   * @param claimer The address of the claimer
   */
  function setClaimer(address user, address claimer) external;
}
