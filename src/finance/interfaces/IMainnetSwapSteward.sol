// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {AaveSwapper} from "aave-helpers/src/swaps/AaveSwapper.sol";

interface IMainnetSwapSteward {
  /// @dev Slippage is too high
  error InvalidSlippage();

  /// @dev Provided address cannot be the zero-address
  error InvalidZeroAddress();

  /// @dev Amount cannot be zero
  error InvalidZeroAmount();

  /// @dev Amount requested is greater than token budget
  error InsufficientBudget();

  /// @dev Oracle does not have correct number of decimals
  error PriceFeedIncompatibleDecimals();

  /// @dev Oracle is returning unexpected value
  error PriceFeedInvalidAnswer();

  /// @dev Token pair has not been set for swapping
  error UnrecognizedTokenSwap();

  /// @notice Emitted when the Milkman contract address is updated
  /// @param oldAddress The old Milkman instance address
  /// @param newAddress The new Milkman instance address
  event MilkmanAddressUpdated(address oldAddress, address newAddress);

  /// @notice Emitted when the Chainlink Price Checker contract address is updated
  /// @param oldAddress The old Price Checker instance address
  /// @param newAddress The new Price Checker instance address
  event PriceCheckerUpdated(address oldAddress, address newAddress);

  /// @notice Emitted when a token is approved for swapping with its corresponding USD oracle
  /// @param fromToken The address of the token approved for swapping from
  /// @param toToken The address of the token approved to swap to
  event ApprovedToken(address indexed fromToken, address indexed toToken);

  /// @notice Emitted when an oracle address is set for a given token
  /// @param token The address of the token
  /// @param oracle The address of the token oracle
  event SetTokenOracle(address indexed token, address indexed oracle);

  /// @notice Emitted when a token's budget is updated
  /// @param token The address of the token
  /// @param budget The budget set for the token
  event UpdatedTokenBudget(address indexed token, uint256 budget);

  /// @notice Returns instance of Aave V3 Collector
  function COLLECTOR() external view returns (ICollector);

  /// @notice Returns the maximum allowed slippage for swaps (in BPS)
  function MAX_SLIPPAGE() external view returns (uint256);

  /// @notice Returns instance of the AaveSwapper contract
  function SWAPPER() external view returns (AaveSwapper);

  /// @notice Returns the address of the Milkman contract
  function milkman() external view returns (address);

  /// @notice Returns address of the price checker used for swaps
  function priceChecker() external view returns (address);

  /// @notice Returns whether token is approved to be swapped from/to
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  function swapApprovedToken(address fromToken, address toToken) external view returns (bool);

  /// @notice Returns address of the Oracle to use for token swaps
  /// @param token Address of the token to swap
  function priceOracle(address token) external view returns (address);

  /// @notice Returns the budget remaining for a given token
  /// @param token The address of the token to query the budget for
  function tokenBudget(address token) external view returns (uint256);

  /// @notice Swaps a specified amount of a sell token for a buy token
  /// @param fromToken The address of the token to sell
  /// @param toToken The address of the token to buy
  /// @param amount The amount of the sell token to swap
  /// @param slippage The slippage allowed in the swap
  function tokenSwap(address fromToken, address toToken, uint256 amount, uint256 slippage) external;

  /// @notice Sets the address for the MILKMAN used in swaps
  /// @param to The address of MILKMAN
  function setMilkman(address to) external;

  /// @notice Sets the address for the Price checker used in swaps
  /// @param to The address of PRICE_CHECKER
  function setPriceChecker(address to) external;

  /// @notice Sets a token pair as allowed for swapping in from -> to direction only
  /// @param fromToken The address of the token to swap from
  /// @param toToken The address of the token to swap to
  function setSwappablePair(address fromToken, address toToken) external;

  /// @notice Sets a token's budget (the maximum that can be swapped from)
  /// @param token The address of the token to set the budget for
  /// @param budget The amount of token that can be swapped from
  function setTokenBudget(address token, uint256 budget) external;

  /// @notice Sets a token's Chainlink Oracle (in USD)
  /// @param token The address of the token
  /// @param oracle The address of the token oracle
  function setTokenOracle(address token, address oracle) external;
}
