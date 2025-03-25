// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {CollectorUtils} from "aave-helpers/src/CollectorUtils.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";

import {MainnetSwapSteward, IMainnetSwapSteward} from "src/finance/MainnetSwapSteward.sol";

/**
 * @dev Test for SwapSteward contract
 * command: forge test -vvv --match-path tests/finance/MainnetSwapSteward.t.sol
 */
contract MainnetSwapStewardTest is Test {
    event MilkmanAddressUpdated(address oldAddress, address newAddress);
    event PriceCheckerUpdated(address oldAddress, address newAddress);
    event SwapRequested(
        address indexed fromToken,
        address indexed toToken,
        address fromOracle,
        address toOracle,
        uint256 amount,
        uint256 slippage
    );
    event ApprovedToken(address indexed fromToken, address indexed toToken);
    event SetTokenOracle(address indexed token, address indexed oracle);
    event UpdatedTokenBudget(address indexed token, uint256 budget);

    address public constant USDC_PRICE_FEED =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant AAVE_PRICE_FEED =
        0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
    address public constant EXECUTOR =
        0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;

    // https://etherscan.io/address/0x060373D064d0168931dE2AB8DDA7410923d06E88
    address public constant MILKMAN =
        0x060373D064d0168931dE2AB8DDA7410923d06E88;

    // https://etherscan.io/address/0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c
    address public constant PRICE_CHECKER =
        0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c;
    // https://etherscan.io/address/0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802
    address public constant LIMIT_ORDER_PRICE_CHECKER =
        0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802;
    address public constant alice = address(43);
    address public constant guardian = address(82);

    MainnetSwapSteward public steward;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 22125630); // https://etherscan.io/block/22125630

        steward = new MainnetSwapSteward(
            GovernanceV3Ethereum.EXECUTOR_LVL_1,
            guardian,
            address(AaveV3Ethereum.COLLECTOR),
            MILKMAN,
            PRICE_CHECKER,
            LIMIT_ORDER_PRICE_CHECKER
        );

        vm.label(0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c, "Collector");
        vm.label(alice, "Alice");
        vm.label(guardian, "Guardian");
        vm.label(EXECUTOR, "Executor");
        vm.label(address(steward), "MainnetSwapSteward");

        vm.startPrank(EXECUTOR);
        IAccessControl(address(AaveV3Ethereum.COLLECTOR)).grantRole(
            bytes32("FUNDS_ADMIN"),
            address(steward)
        );
        vm.stopPrank();

        deal(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            address(AaveV3Ethereum.COLLECTOR),
            1_000_000e6
        );
    }
}

contract SwapTest is MainnetSwapStewardTest {
    function test_revertsIf_notOwnerOrQuardian() public {
        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                alice
            )
        );
        steward.swap(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING,
            1_000e6,
            100
        );
        vm.stopPrank();
    }

    function test_resvertsIf_zeroAmount() public {
        vm.startPrank(guardian);

        vm.expectRevert(IMainnetSwapSteward.InvalidZeroAmount.selector);
        steward.swap(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING,
            0,
            100
        );
        vm.stopPrank();
    }

    function test_resvertsIf_unrecognizedToken() public {
        vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        steward.setTokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

        vm.startPrank(guardian);
        vm.expectRevert(IMainnetSwapSteward.UnrecognizedTokenSwap.selector);
        steward.swap(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING,
            1_000e6,
            100
        );
        vm.stopPrank();
    }

    function test_resvertsIf_invalidPriceFeedAnswer() public {
        address mockOracle = address(new MockOracle());

        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        vm.expectRevert(IMainnetSwapSteward.PriceFeedInvalidAnswer.selector);
        steward.setTokenOracle(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            mockOracle
        );
        vm.stopPrank();
    }

    function test_revertsIf_pairSetNoOracle() public {
        uint256 slippage = 100;

        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        steward.setSwappablePair(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING
        );
        steward.setTokenOracle(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_PRICE_FEED
        );

        vm.startPrank(guardian);
        vm.expectRevert();
        steward.swap(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING,
            1_000e6,
            slippage
        );
    }

    function test_revertsIf_tokenBudgetExceeded() public {
        vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        vm.expectRevert(IMainnetSwapSteward.InsufficientBudget.selector);
        steward.swap(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING,
            1_000e6,
            100
        );
    }

    function test_success() public {
        deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(steward), 1_000e6);
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        steward.setTokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
        vm.stopPrank();
        uint256 slippage = 100;

        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        steward.setSwappablePair(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING
        );
        steward.setTokenOracle(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_PRICE_FEED
        );
        steward.setTokenOracle(
            AaveV3EthereumAssets.AAVE_UNDERLYING,
            AAVE_PRICE_FEED
        );

        vm.startPrank(guardian);
        vm.expectEmit(true, true, true, true, address(steward));
        emit SwapRequested(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING,
            USDC_PRICE_FEED,
            AAVE_PRICE_FEED,
            1_000e6,
            slippage
        );

        steward.swap(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING,
            1_000e6,
            slippage
        );
        vm.stopPrank();
    }
}

contract SetSwappablePairTest is MainnetSwapStewardTest {
    function test_revertsIf_notOwner() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        steward.setSwappablePair(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING
        );
        vm.stopPrank();
    }

    function test_resvertsIf_sameToken() public {
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        vm.expectRevert(IMainnetSwapSteward.UnrecognizedTokenSwap.selector);
        steward.setSwappablePair(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING
        );
        vm.stopPrank();
    }

    function test_success() public {
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

        vm.expectEmit(true, true, true, true, address(steward));
        emit ApprovedToken(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING
        );
        steward.setSwappablePair(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.AAVE_UNDERLYING
        );
        vm.stopPrank();
    }
}

contract SetTokenOracleTest is MainnetSwapStewardTest {
    function test_revertsIf_notOwner() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        steward.setTokenOracle(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_PRICE_FEED
        );
        vm.stopPrank();
    }

    function test_resvertsIf_incompatibleOracleMissingImplementations() public {
        address mockOracle = address(new InvalidMockOracle());

        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        vm.expectRevert();
        steward.setTokenOracle(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            mockOracle
        );

        vm.stopPrank();
    }

    function test_success() public {
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

        vm.expectEmit(true, true, true, true, address(steward));
        emit SetTokenOracle(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_PRICE_FEED
        );

        steward.setTokenOracle(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_PRICE_FEED
        );
    }
}

contract SetPriceChecker is MainnetSwapStewardTest {
    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(this)
            )
        );
        steward.setPriceChecker(makeAddr("price-checker"));
    }

    function test_revertsIf_invalidZeroAddress() public {
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        vm.expectRevert(IMainnetSwapSteward.InvalidZeroAddress.selector);
        steward.setPriceChecker(address(0));
    }

    function test_successful() public {
        address newChecker = makeAddr("new-checker");
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        vm.expectEmit(true, true, true, true, address(steward));
        emit PriceCheckerUpdated(steward.priceChecker(), newChecker);
        steward.setPriceChecker(newChecker);

        assertEq(steward.priceChecker(), newChecker);
    }
}

contract SetMilkman is MainnetSwapStewardTest {
    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(this)
            )
        );
        steward.setMilkman(makeAddr("new-milkman"));
    }

    function test_revertsIf_invalidZeroAddress() public {
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        vm.expectRevert(IMainnetSwapSteward.InvalidZeroAddress.selector);
        steward.setMilkman(address(0));
    }

    function test_successful() public {
        address newMilkman = makeAddr("new-milkman");
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        vm.expectEmit(true, true, true, true, address(steward));
        emit MilkmanAddressUpdated(steward.milkman(), newMilkman);
        steward.setMilkman(newMilkman);

        assertEq(steward.milkman(), newMilkman);
    }
}

contract SetTokenBudget is MainnetSwapStewardTest {
    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(this)
            )
        );
        steward.setTokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    }

    function test_successful() public {
        vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
        vm.expectEmit(true, true, true, true, address(steward));
        emit UpdatedTokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
        steward.setTokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    }
}

/**
 * Helper contract to mock price feed calls
 */
contract MockOracle {
    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestAnswer() external pure returns (int256) {
        return 0;
    }
}

/*
 * Oracle missing `decimals` implementation thus invalid.
 */
contract InvalidMockOracle {
    function latestAnswer() external pure returns (int256) {
        return 0;
    }
}
