// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IMainnetSwapSteward {
    /// @dev Struct representing a TWAP Swap order on COW Swap
    struct TWAPData {
        IERC20 sellToken;
        IERC20 buyToken;
        address receiver;
        uint256 partSellAmount; // amount of sellToken to sell in each part
        uint256 minPartLimit; // minimum amount of tokens to receive per part
        uint256 t0;
        uint256 n;
        uint256 t;
        uint256 span;
        bytes32 appData;
    }

    /// @dev Slippage is too high
    error InvalidSlippage();

    /// @dev Provided address cannot be the zero-address
    error InvalidZeroAddress();

    /// @dev Amount cannot be zero
    error InvalidZeroAmount();

    /// @dev Amount requested is greater than token budget
    error InsufficientBudget();

    /// @dev An order with the specified params does not exist
    error OrderDoesNotExist();

    /// @dev An order with the exact same params exists already
    error OrderExists();

    /// @dev Oracle does not have correct number of decimals
    error PriceFeedIncompatibleDecimals();

    /// @dev Oracle is returning unexpected value
    error PriceFeedInvalidAnswer();

    /// @dev Token pair has not been set for swapping
    error UnrecognizedTokenSwap();

    /// @notice Emitted when a token is approved for swapping with its corresponding USD oracle
    /// @param fromToken The address of the token approved for swapping from
    /// @param toToken The address of the token approved to swap to
    /// @param allowed Whether token pair is allowed or disallowed
    event SetSwappablePair(
        address indexed fromToken,
        address indexed toToken,
        bool allowed
    );

    /// @notice Emitted when the Milkman contract address is updated
    /// @param oldAddress The old Milkman instance address
    /// @param newAddress The new Milkman instance address
    event MilkmanAddressUpdated(address oldAddress, address newAddress);

    /// @notice Emitted when the Relayer contract address is updated
    /// @param oldAddress The old Relayer instance address
    /// @param newAddress The new Relayer instance address
    event RelayerAddressUpdated(address oldAddress, address newAddress);

    /// @notice Emitted when the Chainlink Price Checker contract address is updated
    /// @param oldAddress The old Price Checker instance address
    /// @param newAddress The new Price Checker instance address
    event PriceCheckerUpdated(address oldAddress, address newAddress);

    /// @notice Emitted when the Chainlink Limit Order Price Checker contract address is updated
    /// @param oldAddress The old Price Checker instance address
    /// @param newAddress The new Price Checker instance address
    event LimitOrderPriceCheckerUpdated(address oldAddress, address newAddress);

    /// @notice Emitted when an oracle address is set for a given token
    /// @param token The address of the token
    /// @param oracle The address of the token oracle
    event SetTokenOracle(address indexed token, address indexed oracle);

    /// @notice Emitted when a limit swap is requested
    /// @param fromToken The token that was swapped from
    /// @param toToken The token that was swapped for
    /// @param amount The amount of fromToken that was swapped
    /// @param minAmountOut The minimum amount expected to receive in the swap
    event LimitSwapRequested(
        address indexed fromToken,
        address indexed toToken,
        uint256 amount,
        uint256 minAmountOut
    );

    /// @notice Emitted when a swap is cancelled
    /// @param fromToken The token that was swapped from
    /// @param toToken The token that was swapped for
    /// @param amount The amount of fromToken that was swapped
    event SwapCanceled(
        address indexed fromToken,
        address indexed toToken,
        uint256 amount
    );

    /// @notice Emitted when a swap is requested
    /// @param fromToken The token that was swapped from
    /// @param toToken The token that was swapped for
    /// @param fromOracle The token oracle that was used to check fromToken price
    /// @param toOracle The token that wa  that was used to check toToken price
    /// @param amount The amount of fromToken that was swapped
    /// @param slippage The maximum allowed slippage for the swap
    event SwapRequested(
        address indexed fromToken,
        address indexed toToken,
        address fromOracle,
        address toOracle,
        uint256 amount,
        uint256 slippage
    );

    /// @notice Emitted when a TWAP Swap order is cancelled
    /// @param fromToken The token that was being swapped from
    /// @param toToken The token that was being swapped for
    /// @param totalAmount The total amount of fromToken that was going to be swapped
    event TWAPSwapCanceled(
        address indexed fromToken,
        address indexed toToken,
        uint256 totalAmount
    );

    /// @notice Emitted when a TWAP Swap order is created
    /// @param fromToken The token that is being swapped from
    /// @param toToken The token that is being swapped for
    /// @param totalAmount The total amount of fromToken that is going to be swapped
    event TWAPSwapRequested(
        address indexed fromToken,
        address indexed toToken,
        uint256 totalAmount
    );

    /// @notice Emitted when a token's budget is updated
    /// @param token The address of the token
    /// @param budget The budget set for the token
    event UpdatedTokenBudget(address indexed token, uint256 budget);

    /// @notice Returns address of Aave V3 Collector
    function COLLECTOR() external view returns (address);

    /// @notice Returns the maximum allowed slippage for swaps (in BPS)
    function MAX_SLIPPAGE() external view returns (uint256);

    /// @notice Returns address of handler of conditional orders
    function HANDLER() external view returns (address);

    /// @notice Returns the address of the Milkman contract
    function milkman() external view returns (address);

    /// @notice Returns address of the relayer to relay conditional orders
    function relayer() external view returns (address);

    /// @notice Returns address of the price checker used for swaps
    function priceChecker() external view returns (address);

    /// @notice Returns address of the limit order price checker used for limit swaps
    function limitOrderPriceChecker() external view returns (address);

    /// @notice Returns whether token is approved to be swapped from/to
    /// @param fromToken Address of the token to swap from
    /// @param toToken Address of the token to swap to
    function swapApprovedToken(
        address fromToken,
        address toToken
    ) external view returns (bool);

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
    function swap(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 slippage
    ) external;

    /// @notice Function to swap one token for another with a limit price
    /// @param fromToken Address of the token to swap from
    /// @param toToken Address of the token to swap to
    /// @param amount The amount of fromToken to swap
    /// @param amountOut The limit price of the toToken (minimium amount to receive)
    /// @dev For amountOut, use the token's atoms for decimals (ie: 6 for USDC, 18 for DAI)
    function limitSwap(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 amountOut
    ) external;

    /// @notice Function to swap one token for another at a time-weighted-average-price
    /// @param fromToken Address of the token to swap
    /// @param toToken Address of the token to receive
    /// @param partSellAmount The amount of tokens to sell per TWAP swap part
    /// @param minPartLimit Minimum amount of toToken to receive per TWAP swap part
    /// @param startTime Timestamp of when TWAP orders start
    /// @param numParts Number of TWAP swap parts to take place (each for partSellAmount)
    /// @param partDuration How long each TWAP takes (ie: hourly, weekly, etc)
    /// @param span The timeframe the orders can take place in
    function twapSwap(
        address fromToken,
        address toToken,
        uint256 partSellAmount,
        uint256 minPartLimit,
        uint256 startTime,
        uint256 numParts,
        uint256 partDuration,
        uint256 span
    ) external;

    /// @notice Function to cancel an existing swap
    /// @param tradeMilkman Address of the Milkman contract created upon order submission
    /// @param fromToken Address of the token to swap from
    /// @param toToken Address of the token to swap to
    /// @param amount The amount of fromToken to swap
    /// @param slippage The allowed slippage compared to the oracle price (in BPS)
    function cancelSwap(
        address tradeMilkman,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 slippage
    ) external;

    /// @notice Function to cancel an existing limit swap
    /// @param tradeMilkman Address of the Milkman contract created upon order submission
    /// @param fromToken Address of the token to swap from
    /// @param toToken Address of the token to swap to
    /// @param amount The amount of fromToken to swap
    /// @param amountOut The limit price of the toToken (minimium amount to receive)
    function cancelLimitSwap(
        address tradeMilkman,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 amountOut
    ) external;

    /// @notice Function to cancel a pending time-weighted-average-price swap
    /// @param fromToken Address of the token to swap
    /// @param toToken Address of the token to receive
    /// @param partSellAmount The amount of tokens to sell per TWAP swap part
    /// @param minPartLimit Minimum amount of toToken to receive per TWAP swap
    /// @param startTime Timestamp of when TWAP orders start
    /// @param numParts Number of TWAP swaps to take place (each for partSellAmount)
    /// @param partDuration How long each TWAP part takes (ie: hourly, weekly, etc)
    /// @param span The timeframe the orders can take place in
    /// @param executedParts The number of parts that have already been executed
    function cancelTwapSwap(
        address fromToken,
        address toToken,
        uint256 partSellAmount,
        uint256 minPartLimit,
        uint256 startTime,
        uint256 numParts,
        uint256 partDuration,
        uint256 span,
        uint256 executedParts
    ) external;

    /// @notice Rescues the specified token back to the Collector
    /// @param token The address of the ERC20 token to rescue
    function rescueToken(address token) external;

    /// @notice Rescues the specified token back to the Collector
    /// @param token The address of the ERC20 token to rescue
    /// @param amount The amount of the ERC20 token to rescue
    function rescueToken(address token, uint256 amount) external;

    /// @notice Sets the address for the MILKMAN used in swaps
    /// @param newMilkman The address of MILKMAN
    function setMilkman(address newMilkman) external;

    /// @notice Sets the address for the RELAYER used in swaps
    /// @param newRelayer The address of RELAYER
    function setRelayer(address newRelayer) external;

    /// @notice Sets the address for the RELAYER used in swaps
    /// @param newRelayer The address of RELAYER
    /// @param tokens Array of token addresses to set allowance to zero of current RELAYER
    function setRelayer(address newRelayer, address[] calldata tokens) external;

    /// @notice Sets the address for the Price checker used in swaps
    /// @param to The address of PRICE_CHECKER
    function setPriceChecker(address to) external;

    /// @notice Sets the address for the Limit Order Price checker used in swaps
    /// @param to The address of LIMIT_ORDER_PRICE_CHECKER
    function setLimitOrderPriceChecker(address to) external;

    /// @notice Sets a token pair as allowed for swapping in from -> to direction only
    /// @param fromToken The address of the token to swap from
    /// @param toToken The address of the token to swap to
    /// @param allowed Sets swappable pair to allowed/disallowed
    function setSwappablePair(
        address fromToken,
        address toToken,
        bool allowed
    ) external;

    /// @notice Increases a token's budget (the maximum that can be swapped from)
    /// @param token The address of the token to increase the budget for
    /// @param budget The extra amount of token that can be swapped from
    function increaseTokenBudget(address token, uint256 budget) external;

    /// @notice Sets a token's budget (the maximum that can be swapped from)
    /// @param token The address of the token to decrease the budget for
    /// @param budget The extra amount of token that can no longer be swapped from
    function decreaseTokenBudget(address token, uint256 budget) external;

    /// @notice Sets a token's Chainlink Oracle (in USD)
    /// @param token The address of the token
    /// @param oracle The address of the token oracle
    function setTokenOracle(address token, address oracle) external;

    /// @notice Helper function to see how much one could expect return in a swap
    /// @param amount The amount of fromToken to swap
    /// @param fromToken Address of the token to swap from
    /// @param toToken Address of the token to swap to
    function getExpectedOut(
        uint256 amount,
        address fromToken,
        address toToken
    ) external view returns (uint256);
}
