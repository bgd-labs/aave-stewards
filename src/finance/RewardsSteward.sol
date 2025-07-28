// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ICollector, CollectorUtils as CU} from "aave-helpers/src/CollectorUtils.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {RescuableBase, IRescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {IRewardsController} from "aave-v3-origin/contracts/rewards/interfaces/IRewardsController.sol";

import {IAaveIncentivesController} from "./interfaces/IAaveIncentivesController.sol";
import {IRewardsSteward} from "./interfaces/IRewardsSteward.sol";

/**
 * @title RewardsSteward
 * @author efecarranza  (Tokenlogic)
 * @notice Claims rewards on behalf of the Collector.
 *
 * The contract inherits from `Multicall`. Using the `multicall` function from this contract
 * multiple operations can be bundled into a single transaction.
 *
 * -- Security Considerations
 *
 * -- Permissions
 * The contract implements OwnableWithGuardian.
 * The owner will always be the respective network Level 1 Executor (governance).
 * The guardian role will be given to a Financial Service provider of the DAO.
 *
 * While the permitted Service Provider will have full control over the claiming of funds, the allowed actions are limited by the contract itself.
 * All token interactions start and end on the Collector, so no funds ever leave the DAO's possession at any point in time.
 */
contract RewardsSteward is IRewardsSteward, OwnableWithGuardian, RescuableBase, Multicall {
  /// @inheritdoc IRewardsSteward
  address public immutable COLLECTOR;

  /// @inheritdoc IRewardsSteward
  IAaveIncentivesController public immutable INCENTIVES_CONTROLLER;

  /// @inheritdoc IRewardsSteward
  IRewardsController public immutable REWARDS_CONTROLLER;

  constructor(
    address initialOwner,
    address initialGuardian,
    address collector,
    address incentivesController,
    address rewardsController
  ) OwnableWithGuardian(initialOwner, initialGuardian) {
    if (collector == address(0)) revert InvalidZeroAddress();
    if (incentivesController == address(0)) revert InvalidZeroAddress();
    if (rewardsController == address(0)) revert InvalidZeroAddress();

    COLLECTOR = collector;
    INCENTIVES_CONTROLLER = IAaveIncentivesController(incentivesController);
    REWARDS_CONTROLLER = IRewardsController(rewardsController);
  }

  /// @inheritdoc IRewardsSteward
  function claimAllRewards(address[] calldata assets) external onlyOwnerOrGuardian {
    (address[] memory rewardsList, uint256[] memory claimedAmounts) =
      REWARDS_CONTROLLER.claimAllRewardsOnBehalf(assets, COLLECTOR, COLLECTOR);

    emit ClaimedRewards(rewardsList, claimedAmounts);
  }

  /// @inheritdoc IRewardsSteward
  function claimRewards(address[] calldata assets, uint256 amount, address reward) external onlyOwnerOrGuardian {
    uint256 claimed = REWARDS_CONTROLLER.claimRewardsOnBehalf(assets, amount, COLLECTOR, COLLECTOR, reward);

    emit ClaimedReward(reward, claimed);
  }

  /// @inheritdoc IRewardsSteward
  function claimStkTokenRewards(address[] calldata assets, uint256 amount) external onlyOwnerOrGuardian {
    uint256 claimed = INCENTIVES_CONTROLLER.claimRewardsOnBehalf(assets, amount, COLLECTOR, COLLECTOR);

    emit ClaimedStkTokenRewards(assets, claimed);
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
