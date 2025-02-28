// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {AaveSwapper} from "aave-helpers/src/swaps/AaveSwapper.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {CollectorUtils as CU} from "aave-helpers/src/CollectorUtils.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {IAggregatorInterface} from "src/finance/interfaces/IAggregatorInterface.sol";

import {IMainnetSwapSteward} from "src/finance/interfaces/IMainnetSwapSteward.sol";

/**
 * @title MainnetSwapSteward
 * @author luigy-lemon  (Karpatkey)
 * @author efecarranza  (Tokenlogic)
 * @notice Facilitates token swaps on behalf of the DAO Treasury using the AaveSwapper.
 * Funds must be present in the AaveSwapper in order for them to be executed.
 * The tokens that are to be swapped from/to are to be pre-approved via governance.
 *
 * The contract inherits from `Multicall`. Using the `multicall` function from this contract
 * multiple operations can be bundled into a single transaction.
 *
 * -- Security Considerations
 * Having previously set and validated oracles avoids mistakes that are easy to make when passing the necessary parameters to swap.
 * The contract has a budget on the token that is being swapped from in order to avoid scenarios where a looping strategy can drain
 * the Collector of funds by doing multiple swaps from A -> B -> A with slippage, where the slippage ends up draining the Collector.
 * The budget can only be updated by the DAO via a Governance vote.
 *
 * -- Permissions
 * The contract implements OwnableWithGuardian.
 * The owner will always be the respective network Short Executor (governance).
 * The guardian role will be given to a Financial Service provider of the DAO.
 *
 * -- Swap Pairs Information
 *
 * The swaps executed by this contract will be performed at the discretion of the finance stewards in order to
 * achieve different matters on behalf of the DAO.
 *
 * GHO Price Stability: Swap stables for GHO in order to regain the price objective
 * Merit, Streams and similar: Swap stables for GHO in order to have funding for these activities
 * Long-tail asset exposure reduction: Swap long-tail assets to stablecoins or WETH in order to reduce exposure and
 * or to consolidate the DAO's holdings
 * LSTs: Swap underlying tokens into LSTs in order to generate yield for the DAO
 * Majors: Swap wBTC to wETH as part of the treasury strategy
 *
 */
contract MainnetSwapSteward is IMainnetSwapSteward, OwnableWithGuardian, Multicall {
  using CU for ICollector;
  using CU for CU.SwapInput;

  /// @inheritdoc IMainnetSwapSteward
  uint256 public constant MAX_SLIPPAGE = 1000; // 10%

  /// @inheritdoc IMainnetSwapSteward
  AaveSwapper public immutable SWAPPER;

  /// @inheritdoc IMainnetSwapSteward
  ICollector public immutable COLLECTOR;

  /// @inheritdoc IMainnetSwapSteward
  address public milkman;

  /// @inheritdoc IMainnetSwapSteward
  address public priceChecker;

  /// @inheritdoc IMainnetSwapSteward
  mapping(address fromToken => mapping(address toToken => bool isApproved)) public swapApprovedToken;

  /// @inheritdoc IMainnetSwapSteward
  mapping(address token => address oracle) public priceOracle;

  /// @inheritdoc IMainnetSwapSteward
  mapping(address token => uint256 budget) public tokenBudget;

  constructor(
    address initialOwner,
    address initialGuardian,
    address collector,
    address swapper,
    address initialMilkman,
    address initialPriceChecker
  ) OwnableWithGuardian(initialOwner, initialGuardian) {
    _setMilkman(initialMilkman);
    _setPriceChecker(initialPriceChecker);

    COLLECTOR = ICollector(collector);
    SWAPPER = AaveSwapper(swapper);
  }

  /// @inheritdoc IMainnetSwapSteward
  function tokenSwap(address fromToken, address toToken, uint256 amount, uint256 slippage) external onlyOwnerOrGuardian {
    address fromOracle = priceOracle[fromToken];
    address toOracle = priceOracle[toToken];

    _validateSwap(fromToken, toToken, fromOracle, toOracle, amount, slippage);

    tokenBudget[fromToken] -= amount;

    COLLECTOR.swap(
      address(SWAPPER), CU.SwapInput(milkman, priceChecker, fromToken, toToken, fromOracle, toOracle, amount, slippage)
    );
  }

  /// @inheritdoc IMainnetSwapSteward
  function setTokenBudget(address token, uint256 budget) external onlyOwner {
    tokenBudget[token] = budget;

    emit UpdatedTokenBudget(token, budget);
  }

  /// @inheritdoc IMainnetSwapSteward
  function setSwappablePair(address fromToken, address toToken) external onlyOwner {
    if (fromToken == toToken) revert UnrecognizedTokenSwap();

    swapApprovedToken[fromToken][toToken] = true;

    emit ApprovedToken(fromToken, toToken);
  }

  /// @inheritdoc IMainnetSwapSteward
  function setTokenOracle(address token, address oracle) external onlyOwner {
    if (oracle == address(0)) revert InvalidZeroAddress();

    // Validate oracle has necessary functions
    if (IAggregatorInterface(oracle).decimals() != 8) {
      revert PriceFeedIncompatibleDecimals();
    }
    if (IAggregatorInterface(oracle).latestAnswer() == 0) {
      revert PriceFeedInvalidAnswer();
    }

    priceOracle[token] = oracle;

    emit SetTokenOracle(token, oracle);
  }

  /// @inheritdoc IMainnetSwapSteward
  function setPriceChecker(address newPriceChecker) external onlyOwner {
    _setPriceChecker(newPriceChecker);
  }

  /// @inheritdoc IMainnetSwapSteward
  function setMilkman(address newMilkman) external onlyOwner {
    _setMilkman(newMilkman);
  }

  /// @dev Internal function to set the price checker
  function _setPriceChecker(address newPriceChecker) internal {
    if (newPriceChecker == address(0)) revert InvalidZeroAddress();
    address old = priceChecker;
    priceChecker = newPriceChecker;

    emit PriceCheckerUpdated(old, newPriceChecker);
  }

  /// @dev Internal function to set the Milkman instance address
  function _setMilkman(address newMilkman) internal {
    if (newMilkman == address(0)) revert InvalidZeroAddress();
    address old = milkman;
    milkman = newMilkman;

    emit MilkmanAddressUpdated(old, newMilkman);
  }

  /// @dev Internal function to validate a swap's parameters
  function _validateSwap(
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    uint256 amountIn,
    uint256 slippage
  ) internal view {
    if (amountIn == 0) revert InvalidZeroAmount();
    if (amountIn > tokenBudget[fromToken]) revert InsufficientBudget();
    if (slippage > MAX_SLIPPAGE) revert InvalidSlippage();

    if (!swapApprovedToken[fromToken][toToken]) {
      revert UnrecognizedTokenSwap();
    }

    if (IAggregatorInterface(fromOracle).latestAnswer() == 0 || IAggregatorInterface(toOracle).latestAnswer() == 0) {
      revert PriceFeedInvalidAnswer();
    }
  }
}
