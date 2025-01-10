// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {AaveSwapper} from "aave-helpers/src/swaps/AaveSwapper.sol";
import {ICollector, CollectorUtils as CU} from "aave-helpers/src/CollectorUtils.sol";
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
 * -- Security Considerations
 * Having previously set and validated oracles avoids mistakes that are easy to make when passing the necessary parameters to swap.
 *
 * -- Permissions
 * The contract implements OwnableWithGuardian.
 * The owner will always be the respective network Short Executor (governance).
 * The guardian role will be given to a Financial Service provider of the DAO.
 *
 */
contract MainnetSwapSteward is OwnableWithGuardian, IMainnetSwapSteward {
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
  mapping(address token => bool isApproved) public swapApprovedToken;

  /// @inheritdoc IMainnetSwapSteward
  mapping(address token => address oracle) public priceOracle;

  constructor(
    address _owner,
    address _guardian,
    address _collector,
    address _swapper,
    address _milkman,
    address _priceChecker
  ) {
    _transferOwnership(_owner);
    _updateGuardian(_guardian);
    _setMilkman(_milkman);
    _setPriceChecker(_priceChecker);

    COLLECTOR = ICollector(_collector);
    SWAPPER = AaveSwapper(_swapper);
  }

  /// @inheritdoc IMainnetSwapSteward
  function tokenSwap(address sellToken, uint256 amount, address buyToken, uint256 slippage)
    external
    onlyOwnerOrGuardian
  {
    _validateSwap(sellToken, amount, buyToken, slippage);

    CU.SwapInput memory swapData = CU.SwapInput(
      milkman, priceChecker, sellToken, buyToken, priceOracle[sellToken], priceOracle[buyToken], amount, slippage
    );

    CU.swap(COLLECTOR, address(SWAPPER), swapData);
  }

  /// @inheritdoc IMainnetSwapSteward
  function setSwappableToken(address token, address priceFeedUSD) external onlyOwner {
    if (priceFeedUSD == address(0)) revert InvalidZeroAddress();

    swapApprovedToken[token] = true;
    priceOracle[token] = priceFeedUSD;

    // Validate oracle has necessary functions
    if (IAggregatorInterface(priceFeedUSD).decimals() != 8) {
      revert PriceFeedIncompatibleDecimals();
    }
    if (IAggregatorInterface(priceFeedUSD).latestAnswer() == 0) {
      revert PriceFeedInvalidAnswer();
    }

    emit ApprovedToken(token, priceFeedUSD);
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
  function _validateSwap(address sellToken, uint256 amountIn, address buyToken, uint256 slippage) internal view {
    if (amountIn == 0) revert InvalidZeroAmount();

    if (!swapApprovedToken[sellToken] || !swapApprovedToken[buyToken]) {
      revert UnrecognizedToken();
    }

    if (slippage > MAX_SLIPPAGE) revert InvalidSlippage();

    if (
      IAggregatorInterface(priceOracle[buyToken]).latestAnswer() == 0
        || IAggregatorInterface(priceOracle[sellToken]).latestAnswer() == 0
    ) {
      revert PriceFeedInvalidAnswer();
    }
  }
}
