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
  address public MILKMAN;

  /// @inheritdoc IMainnetSwapSteward
  address public PRICE_CHECKER;

  /// @inheritdoc IMainnetSwapSteward
  mapping(address token => bool isApproved) public swapApprovedToken;

  /// @inheritdoc IMainnetSwapSteward
  mapping(address token => address oracle) public priceOracle;

  constructor(address _owner, address _guardian, address collector) {
    _transferOwnership(_owner);
    _updateGuardian(_guardian);

    COLLECTOR = ICollector(collector);
    SWAPPER = AaveSwapper(MiscEthereum.AAVE_SWAPPER);

    // https://etherscan.io/address/0x060373D064d0168931dE2AB8DDA7410923d06E88
    _setMilkman(0x060373D064d0168931dE2AB8DDA7410923d06E88);

    // https://etherscan.io/address/0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c
    _setPriceChecker(0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c);
  }

  /// @inheritdoc IMainnetSwapSteward
  function tokenSwap(address sellToken, uint256 amount, address buyToken, uint256 slippage)
    external
    onlyOwnerOrGuardian
  {
    _validateSwap(sellToken, amount, buyToken, slippage);

    CU.SwapInput memory swapData = CU.SwapInput(
      MILKMAN, PRICE_CHECKER, sellToken, buyToken, priceOracle[sellToken], priceOracle[buyToken], amount, slippage
    );

    CU.swap(COLLECTOR, address(SWAPPER), swapData);
  }

  /// @inheritdoc IMainnetSwapSteward
  function setSwappableToken(address token, address priceFeedUSD) external onlyOwner {
    if (priceFeedUSD == address(0)) revert MissingPriceFeed();

    swapApprovedToken[token] = true;
    priceOracle[token] = priceFeedUSD;

    // Validate oracle has necessary functions
    if (IAggregatorInterface(priceFeedUSD).decimals() != 8) {
      revert PriceFeedIncompatibility();
    }
    if (IAggregatorInterface(priceFeedUSD).latestAnswer() == 0) {
      revert PriceFeedIncompatibility();
    }

    emit SwapApprovedToken(token, priceFeedUSD);
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
    address old = PRICE_CHECKER;
    PRICE_CHECKER = newPriceChecker;

    emit PriceCheckerUpdated(old, newPriceChecker);
  }

  /// @dev Internal function to set the Milkman instance address
  function _setMilkman(address newMilkman) internal {
    if (newMilkman == address(0)) revert InvalidZeroAddress();
    address old = MILKMAN;
    MILKMAN = newMilkman;

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
      revert PriceFeedFailure();
    }
  }
}
