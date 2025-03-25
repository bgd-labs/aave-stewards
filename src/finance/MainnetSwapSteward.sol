// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {RescuableBase, IRescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {IAggregatorInterface} from "src/finance/interfaces/IAggregatorInterface.sol";
import {IMilkman} from "src/finance/interfaces/IMilkman.sol";
import {IPriceChecker} from "./interfaces/IPriceChecker.sol";

import {IMainnetSwapSteward} from "src/finance/interfaces/IMainnetSwapSteward.sol";

/**
 * @title MainnetSwapSteward
 * @author luigy-lemon  (Karpatkey)
 * @author efecarranza  (Tokenlogic)
 * @notice Facilitates token swaps on behalf of the DAO Treasury by having functions for different types of swaps.
 * Funds must be present in this contract in order for them to be executed.
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
contract MainnetSwapSteward is
    IMainnetSwapSteward,
    OwnableWithGuardian,
    Multicall,
    RescuableBase
{
    using SafeERC20 for IERC20;

    /// @inheritdoc IMainnetSwapSteward
    uint256 public constant MAX_SLIPPAGE = 1000; // 10%

    /// @inheritdoc IMainnetSwapSteward
    ICollector public immutable COLLECTOR;

    /// @inheritdoc IMainnetSwapSteward
    address public milkman;

    /// @inheritdoc IMainnetSwapSteward
    address public priceChecker;

    /// @inheritdoc IMainnetSwapSteward
    address public limitOrderPriceChecker;

    /// @inheritdoc IMainnetSwapSteward
    mapping(address fromToken => mapping(address toToken => bool isApproved))
        public swapApprovedToken;

    /// @inheritdoc IMainnetSwapSteward
    mapping(address token => address oracle) public priceOracle;

    /// @inheritdoc IMainnetSwapSteward
    mapping(address token => uint256 budget) public tokenBudget;

    constructor(
        address initialOwner,
        address initialGuardian,
        address collector,
        address initialMilkman,
        address initialPriceChecker,
        address initialLimitOrderPriceChecker
    ) OwnableWithGuardian(initialOwner, initialGuardian) {
        if (collector == address(0)) revert InvalidZeroAddress();

        _setMilkman(initialMilkman);
        _setPriceChecker(initialPriceChecker);
        _setLimitOrderPriceChecker(initialLimitOrderPriceChecker);

        COLLECTOR = ICollector(collector);
    }

    /// @inheritdoc IMainnetSwapSteward
    function swap(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 slippage
    ) external onlyOwnerOrGuardian {
        address fromOracle = priceOracle[fromToken];
        address toOracle = priceOracle[toToken];
        amount = _checkAmount(fromToken, amount);

        _validateSwap(
            fromToken,
            toToken,
            fromOracle,
            toOracle,
            amount,
            slippage
        );

        amount = _transferTokensIn(fromToken, amount);

        _swap(
            priceChecker,
            fromToken,
            toToken,
            address(COLLECTOR),
            amount,
            _getPriceCheckerAndData(fromOracle, toOracle, slippage)
        );

        emit SwapRequested(
            fromToken,
            toToken,
            fromOracle,
            toOracle,
            amount,
            slippage
        );
    }

    /// @inheritdoc IMainnetSwapSteward
    function limitSwap(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 amountOut
    ) external onlyOwnerOrGuardian {
        amount = _checkAmount(fromToken, amount);

        _validateLimitSwap(fromToken, toToken, amount);

        amount = _transferTokensIn(fromToken, amount);

        _swap(
            limitOrderPriceChecker,
            fromToken,
            toToken,
            address(COLLECTOR),
            amount,
            abi.encode(amountOut)
        );

        emit LimitSwapRequested(fromToken, toToken, amount, amountOut);
    }

    /// @inheritdoc IMainnetSwapSteward
    function cancelSwap(
        address tradeMilkman,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 slippage
    ) external onlyOwnerOrGuardian {
        bytes memory data = _getPriceCheckerAndData(
            priceOracle[fromToken],
            priceOracle[toToken],
            slippage
        );

        _cancelSwap(
            tradeMilkman,
            priceChecker,
            fromToken,
            toToken,
            amount,
            data
        );
    }

    /// @inheritdoc IMainnetSwapSteward
    function cancelLimitSwap(
        address tradeMilkman,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 amountOut
    ) external onlyOwnerOrGuardian {
        _cancelSwap(
            tradeMilkman,
            limitOrderPriceChecker,
            fromToken,
            toToken,
            amount,
            abi.encode(amountOut)
        );
    }

    /// @inheritdoc IMainnetSwapSteward
    function setTokenBudget(address token, uint256 budget) external onlyOwner {
        tokenBudget[token] = budget;

        emit UpdatedTokenBudget(token, budget);
    }

    /// @inheritdoc IMainnetSwapSteward
    function rescueToken(address token) external {
        _emergencyTokenTransfer(token, address(COLLECTOR), type(uint256).max);
    }

    /// @inheritdoc IRescuableBase
    function maxRescue(
        address token
    ) public view override(RescuableBase) returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc IMainnetSwapSteward
    function setSwappablePair(
        address fromToken,
        address toToken
    ) external onlyOwner {
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

    /// @inheritdoc IMainnetSwapSteward
    function getExpectedOut(
        uint256 amount,
        address fromToken,
        address toToken
    ) public view returns (uint256) {
        bytes memory data = _getPriceCheckerAndData(
            priceOracle[fromToken],
            priceOracle[toToken],
            0
        );

        (, bytes memory _data) = abi.decode(data, (uint256, bytes));

        return
            IPriceChecker(priceChecker)
                .EXPECTED_OUT_CALCULATOR()
                .getExpectedOut(amount, fromToken, toToken, _data);
    }

    /// @notice Internal function that handles swaps
    /// @param _priceChecker Address of the price checker to validate order
    /// @param fromToken Address of the token to swap from
    /// @param toToken Address of the token to swap to
    /// @param recipient Address of the account receiving the swapped funds
    /// @param amount The amount of fromToken to swap
    /// @param priceCheckerData abi-encoded data for price checker
    function _swap(
        address _priceChecker,
        address fromToken,
        address toToken,
        address recipient,
        uint256 amount,
        bytes memory priceCheckerData
    ) internal {
        IERC20(fromToken).forceApprove(milkman, amount);

        IMilkman(milkman).requestSwapExactTokensForTokens(
            amount,
            IERC20(fromToken),
            IERC20(toToken),
            recipient,
            bytes32(0),
            _priceChecker,
            priceCheckerData
        );
    }

    /// @notice Internal function that handles swap cancellations
    /// @param tradeMilkman Address of the Milkman contract to submit the order
    /// @param _priceChecker Address of the price checker to validate order
    /// @param fromToken Address of the token to swap from
    /// @param toToken Address of the token to swap to
    /// @param amount The amount of fromToken to swap
    /// @param priceCheckerData abi-encoded data for price checker
    function _cancelSwap(
        address tradeMilkman,
        address _priceChecker,
        address fromToken,
        address toToken,
        uint256 amount,
        bytes memory priceCheckerData
    ) internal {
        IMilkman(tradeMilkman).cancelSwap(
            amount,
            IERC20(fromToken),
            IERC20(toToken),
            address(COLLECTOR),
            bytes32(0),
            _priceChecker,
            priceCheckerData
        );

        IERC20(fromToken).safeTransfer(
            address(COLLECTOR),
            IERC20(fromToken).balanceOf(address(this))
        );

        emit SwapCanceled(fromToken, toToken, amount);
    }

    /// @notice Helper function to abi-encode data for price checker
    /// @param fromOracle Address of the oracle to check fromToken price
    /// @param toOracle Address of the oracle to check toToken price
    /// @param slippage The allowed slippage compared to the oracle price (in BPS)
    function _getPriceCheckerAndData(
        address fromOracle,
        address toOracle,
        uint256 slippage
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                slippage,
                _getChainlinkCheckerData(fromOracle, toOracle)
            );
    }

    /// @notice Helper function to abi-encode Chainlink oracle data
    /// @param fromOracle Address of the oracle to check fromToken price
    /// @param toOracle Address of the oracle to check toToken price
    function _getChainlinkCheckerData(
        address fromOracle,
        address toOracle
    ) internal pure returns (bytes memory) {
        address[] memory paths = new address[](2);
        paths[0] = fromOracle;
        paths[1] = toOracle;

        bool[] memory reverses = new bool[](2);
        reverses[1] = true;

        return abi.encode(paths, reverses);
    }

    /// @dev Internal function to set the price checker
    function _setPriceChecker(address newPriceChecker) internal {
        if (newPriceChecker == address(0)) revert InvalidZeroAddress();
        address old = priceChecker;
        priceChecker = newPriceChecker;

        emit PriceCheckerUpdated(old, newPriceChecker);
    }

    /// @dev Internal function to set the price checker
    function _setLimitOrderPriceChecker(address newPriceChecker) internal {
        if (newPriceChecker == address(0)) revert InvalidZeroAddress();
        address old = priceChecker;
        limitOrderPriceChecker = newPriceChecker;

        emit LimitOrderPriceCheckerUpdated(old, newPriceChecker);
    }

    /// @dev Internal function to set the Milkman instance address
    function _setMilkman(address newMilkman) internal {
        if (newMilkman == address(0)) revert InvalidZeroAddress();
        address old = milkman;
        milkman = newMilkman;

        emit MilkmanAddressUpdated(old, newMilkman);
    }

    /// @dev Internal function to check maximum amount
    function _checkAmount(
        address fromToken,
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == type(uint256).max) {
            amount = msg.sender == owner()
                ? IERC20(fromToken).balanceOf(address(COLLECTOR))
                : tokenBudget[fromToken];
        }

        return amount;
    }

    function _transferTokensIn(
        address fromToken,
        uint256 amount
    ) internal returns (uint256) {
        COLLECTOR.transfer(IERC20(fromToken), address(this), amount);
        uint256 swapperBalance = IERC20(fromToken).balanceOf(address(this));

        // some tokens, like stETH, can lose 1-2wei on transfer
        if (swapperBalance < amount) {
            amount = swapperBalance;
        }

        return amount;
    }

    /// @dev Internal function to validate a swap's parameters
    function _validateSwap(
        address fromToken,
        address toToken,
        address fromOracle,
        address toOracle,
        uint256 amount,
        uint256 slippage
    ) internal {
        if (amount == 0) revert InvalidZeroAmount();
        if (slippage > MAX_SLIPPAGE) revert InvalidSlippage();
        if (!swapApprovedToken[fromToken][toToken]) {
            revert UnrecognizedTokenSwap();
        }

        if (msg.sender != owner()) {
            if (amount > tokenBudget[fromToken]) revert InsufficientBudget();
            tokenBudget[fromToken] -= amount;
        }

        if (
            IAggregatorInterface(fromOracle).latestAnswer() == 0 ||
            IAggregatorInterface(toOracle).latestAnswer() == 0
        ) {
            revert PriceFeedInvalidAnswer();
        }
    }

    /// @dev Internal function to validate a limit swap's parameters
    function _validateLimitSwap(
        address fromToken,
        address toToken,
        uint256 amount
    ) internal {
        if (amount == 0) revert InvalidZeroAmount();
        if (!swapApprovedToken[fromToken][toToken]) {
            revert UnrecognizedTokenSwap();
        }

        if (msg.sender != owner()) {
            if (amount > tokenBudget[fromToken]) revert InsufficientBudget();
            tokenBudget[fromToken] -= amount;
        }
    }
}
