// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {ICollector, CollectorUtils as CU} from "aave-helpers/src/CollectorUtils.sol";

import {ICollectorBudgetSteward} from "./interfaces/ICollectorBudgetSteward.sol";

/**
 * @title CollectorBudgetSteward
 * @author luigy-lemon  (Karpatkey)
 * @author efecarranza  (Tokenlogic)
 * @notice Enables the Guardian to execute approved financial operations using funds from the AaveCollector.
 * The CollectorBudgetSteward is granted a certain budget via a governance vote and is limited in its operations to the remaining budget.
 * The budget is provided per token.
 * The budgets must be reset via governance once expired (or as needed for sizeable transactions).
 *
 * The funds can only be received by governance approved addresses. An example scenario is as follows: the DAO approved 1M GHO, and 5 addresses.
 * The stewards then create a stream to a service provider for 500k GHO, transfer 10k GHO for incentives, and 2k GHO for gas-refunds to providers.
 * The stewards then have 488k GHO at their disposal. A DAO controller multi-sig can also be a beneficiary to handle smaller payments such as
 * bounty payouts to bug platforms and other ad hoc expenses.
 *
 * -- Permissions
 * The contract implements OwnableWithGuardian.
 * The owner will always be the respective network Short Executor (governance).
 * The guardian role will be given to a Financial Service provider of the DAO.
 */
contract CollectorBudgetSteward is OwnableWithGuardian, ICollectorBudgetSteward {
  using CU for ICollector;
  using CU for CU.IOInput;
  using CU for CU.CreateStreamInput;

  /// @inheritdoc ICollectorBudgetSteward
  ICollector public immutable COLLECTOR;

  /// @inheritdoc ICollectorBudgetSteward
  mapping(address receiver => bool isApproved) public transferApprovedReceiver;

  /// @inheritdoc ICollectorBudgetSteward
  mapping(address token => uint256 budget) public tokenBudget;

  constructor(address _owner, address _guardian, address collector) {
    _transferOwnership(_owner);
    _updateGuardian(_guardian);
    COLLECTOR = ICollector(collector);
  }

  /// Controlled Actions

  /// @inheritdoc ICollectorBudgetSteward
  function approve(address token, address to, uint256 amount) external onlyOwnerOrGuardian {
    _validateTransfer(token, to, amount);
    COLLECTOR.approve(token, to, amount);
  }

  /// @inheritdoc ICollectorBudgetSteward
  function transfer(address token, address to, uint256 amount) external onlyOwnerOrGuardian {
    _validateTransfer(token, to, amount);
    COLLECTOR.transfer(token, to, amount);
  }

  /// @inheritdoc ICollectorBudgetSteward
  function createStream(address to, StreamData memory stream) external onlyOwnerOrGuardian {
    if (stream.start < block.timestamp || stream.end <= stream.start) {
      revert InvalidDate();
    }

    _validateTransfer(stream.token, to, stream.amount);

    uint256 duration = stream.end - stream.start;

    CU.CreateStreamInput memory utilsData =
      CU.CreateStreamInput(stream.token, to, stream.amount, stream.start, duration);

    CU.stream(COLLECTOR, utilsData);
  }

  /// @inheritdoc ICollectorBudgetSteward
  function cancelStream(uint256 streamId) external onlyOwnerOrGuardian {
    COLLECTOR.cancelStream(streamId);
  }

  /// DAO Actions

  /// @inheritdoc ICollectorBudgetSteward
  function increaseBudget(address token, uint256 amount) external onlyOwner {
    uint256 currentBudget = tokenBudget[token];
    _updateBudget(token, currentBudget + amount);
  }

  /// @inheritdoc ICollectorBudgetSteward
  function decreaseBudget(address token, uint256 amount) external onlyOwner {
    uint256 currentBudget = tokenBudget[token];
    if (amount > currentBudget) {
      _updateBudget(token, 0);
    } else {
      _updateBudget(token, currentBudget - amount);
    }
  }

  /// @inheritdoc ICollectorBudgetSteward
  function setWhitelistedReceiver(address to) external onlyOwner {
    transferApprovedReceiver[to] = true;
    emit ReceiverWhitelisted(to);
  }

  /// Logic

  /// @dev Internal function to validate a transfer's parameters
  function _validateTransfer(address token, address to, uint256 amount) internal {
    if (transferApprovedReceiver[to] == false) {
      revert UnrecognizedReceiver();
    }

    uint256 currentBalance = IERC20(token).balanceOf(address(COLLECTOR));
    if (currentBalance < amount) {
      revert ExceedsBalance();
    }

    uint256 currentBudget = tokenBudget[token];
    if (currentBudget < amount) {
      revert ExceedsBudget(currentBudget);
    }
    _updateBudget(token, currentBudget - amount);
  }

  function _updateBudget(address token, uint256 newAmount) internal {
    tokenBudget[token] = newAmount;
    emit BudgetUpdate(token, newAmount);
  }
}
