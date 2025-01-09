// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICollector} from "aave-helpers/src/CollectorUtils.sol";
import {AaveSwapper} from "aave-helpers/src/swaps/AaveSwapper.sol";

interface IMainnetSwapSteward {
  /// @dev Slippage is too high
  error InvalidSlippage();

  /// @dev Provided address cannot be the zero-address
  error InvalidZeroAddress();

  /// @dev Amount cannot be zero
  error InvalidZeroAmount();

  /// @dev Oracle cannot be the zero-address
  error MissingPriceFeed();

  /// @dev Oracle did not return a valid value
  error PriceFeedFailure();

  /// @dev Oracle is returning unexpected values
  error PriceFeedIncompatibility();

  /// @dev Token has not been previously approved for swapping
  error UnrecognizedToken();

  /// @notice Emitted when the Milkman contract address is updated
  /// @param oldAddress The old Milkman instance address
  /// @param newAddress The new Milkman instance address
  event MilkmanAddressUpdated(address oldAddress, address newAddress);

  /// @notice Emitted when the Chainlink Price Checker contract address is updated
  /// @param oldAddress The old Price Checker instance address
  /// @param newAddress The new Price Checker instance address
  event PriceCheckerUpdated(address oldAddress, address newAddress);

  /// @notice Emitted when a token is approved for swapping with its corresponding USD oracle
  /// @param token The address of the token approved for swapping
  /// @param oracleUSD The address of the oracle providing the USD price feed for the token
  event SwapApprovedToken(address indexed token, address indexed oracleUSD);

  /// @notice Returns instance of Aave V3 Collector
  function COLLECTOR() external view returns (ICollector);

  /// @notice Returns the maximum allowed slippage for swaps (in BPS)
  function MAX_SLIPPAGE() external view returns (uint256);

  /// @notice Returns instance of the AaveSwapper contract
  function SWAPPER() external view returns (AaveSwapper);

  /// @notice Returns the address of the Milkman contract
  function MILKMAN() external view returns (address);

  /// @notice Returns address of the price checker used for swaps
  function PRICE_CHECKER() external view returns (address);

  /// @notice Returns whether token is approved to be swapped from/to
  /// @param token Address of the token to swap from/to
  function swapApprovedToken(address token) external view returns (bool);

  /// @notice Returns address of the Oracle to use for token swaps
  /// @param token Address of the token to swap
  function priceOracle(address token) external view returns (address);

  /// @notice Swaps a specified amount of a sell token for a buy token
  /// @param sellToken The address of the token to sell
  /// @param amount The amount of the sell token to swap
  /// @param buyToken The address of the token to buy
  /// @param slippage The slippage allowed in the swap
  function tokenSwap(address sellToken, uint256 amount, address buyToken, uint256 slippage) external;

  /// @notice Sets the address for the MILKMAN used in swaps
  /// @param to The address of MILKMAN
  function setMilkman(address to) external;

  /// @notice Sets the address for the Price checker used in swaps
  /// @param to The address of PRICE_CHECKER
  function setPriceChecker(address to) external;

  /// @notice Sets a token as swappable and provides its price feed address
  /// @param token The address of the token to set as swappable
  /// @param priceFeedUSD The address of the price feed for the token
  function setSwappableToken(address token, address priceFeedUSD) external;
}
