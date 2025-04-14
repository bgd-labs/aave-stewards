// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV2Ethereum, AaveV2EthereumAssets} from "aave-address-book/AaveV2Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {CollectorUtils} from "aave-helpers/src/CollectorUtils.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";

import {MainnetSwapSteward, IMainnetSwapSteward} from "src/finance/MainnetSwapSteward.sol";

/**
 * @dev Test for SwapSteward contract
 * command: forge test -vvv --match-path tests/finance/MainnetSwapSteward.t.sol
 */
contract MainnetSwapStewardTest is Test {
  event ApprovedToken(address indexed fromToken, address indexed toToken);
  event MilkmanAddressUpdated(address oldAddress, address newAddress);
  event HandlerAddressUpdated(address oldAddress, address newAddress);
  event RelayerAddressUpdated(address oldAddress, address newAddress);
  event PriceCheckerUpdated(address oldAddress, address newAddress);
  event LimitOrderPriceCheckerUpdated(address oldAddress, address newAddress);
  event LimitSwapRequested(address indexed fromToken, address indexed toToken, uint256 amount, uint256 minAmountOut);
  event SwapCanceled(address indexed fromToken, address indexed toToken, uint256 amount);
  event SwapRequested(
    address indexed fromToken,
    address indexed toToken,
    address fromOracle,
    address toOracle,
    uint256 amount,
    uint256 slippage
  );
  event SetTokenOracle(address indexed token, address indexed oracle);
  event TWAPSwapCanceled(address indexed fromToken, address indexed toToken, uint256 totalAmount);
  event TWAPSwapRequested(address indexed fromToken, address indexed toToken, uint256 totalAmount);
  event UpdatedTokenBudget(address indexed token, uint256 budget);

  address public constant USDC_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  address public constant AAVE_PRICE_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
  address public constant EXECUTOR = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;

  // https://etherscan.io/address/0x060373D064d0168931dE2AB8DDA7410923d06E88
  address public constant MILKMAN = 0x060373D064d0168931dE2AB8DDA7410923d06E88;

  // https://etherscan.io/address/0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c
  address public constant PRICE_CHECKER = 0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c;

  // https://etherscan.io/address/0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802
  address public constant LIMIT_ORDER_PRICE_CHECKER = 0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802;

  // https://etherscan.io/address/0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74
  address public constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;

  // https://etherscan.io/address/0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5
  address public constant TWAP_HANDLER = 0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5;

  // https://etherscan.io/address/0xC92E8bdf79f0507f65a392b0ab4667716BFE0110
  address public constant COW_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

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
      LIMIT_ORDER_PRICE_CHECKER,
      COMPOSABLE_COW,
      TWAP_HANDLER,
      COW_RELAYER
    );

    vm.label(0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c, "Collector");
    vm.label(alice, "Alice");
    vm.label(guardian, "Guardian");
    vm.label(EXECUTOR, "Executor");
    vm.label(address(steward), "MainnetSwapSteward");

    vm.startPrank(EXECUTOR);
    IAccessControl(address(AaveV3Ethereum.COLLECTOR)).grantRole(bytes32("FUNDS_ADMIN"), address(steward));
    vm.stopPrank();

    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(AaveV3Ethereum.COLLECTOR), 1_000_000e6);
  }

  function _setBudgetAndPath() internal {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setTokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    steward.setSwappablePair(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING);
    steward.setTokenOracle(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    steward.setTokenOracle(AaveV3EthereumAssets.AAVE_UNDERLYING, AAVE_PRICE_FEED);
    vm.stopPrank();
  }
}

contract ConstructorTest is Test {}

contract SwapTest is MainnetSwapStewardTest {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.swap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 100);
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(IMainnetSwapSteward.InvalidZeroAmount.selector);
    steward.swap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 0, 100);
    vm.stopPrank();
  }

  function test_revertsIf_unrecognizedToken() public {
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setTokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);
    vm.expectRevert(IMainnetSwapSteward.UnrecognizedTokenSwap.selector);
    steward.swap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 100);
    vm.stopPrank();
  }

  function test_revertsIf_invalidPriceFeedAnswer() public {
    address mockOracle = address(new MockOracle());

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert(IMainnetSwapSteward.PriceFeedInvalidAnswer.selector);
    steward.setTokenOracle(AaveV3EthereumAssets.USDC_UNDERLYING, mockOracle);
    vm.stopPrank();
  }

  function test_revertsIf_pairSetNoOracle() public {
    uint256 slippage = 100;

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappablePair(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING);
    steward.setTokenOracle(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);

    vm.startPrank(guardian);
    vm.expectRevert();
    steward.swap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, slippage);
  }

  function test_revertsIf_tokenBudgetExceeded() public {
    _setBudgetAndPath();
    vm.prank(guardian);
    vm.expectRevert(IMainnetSwapSteward.InsufficientBudget.selector);
    steward.swap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 2_000e6, 100);
  }

  function test_success_governanceCallerBudgetExceeded() public {
    _setBudgetAndPath();
    uint256 slippage = 100;

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit SwapRequested(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      USDC_PRICE_FEED,
      AAVE_PRICE_FEED,
      2_000e6,
      slippage
    );

    steward.swap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 2_000e6, slippage);
    vm.stopPrank();
  }

  function test_success() public {
    _setBudgetAndPath();
    uint256 slippage = 100;

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

    steward.swap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, slippage);
    vm.stopPrank();
  }
}

contract LimitSwapTest is MainnetSwapStewardTest {
  function test_revertsIf_notOwnerOrQuardian() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.limitSwap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 900e6);
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(IMainnetSwapSteward.InvalidZeroAmount.selector);
    steward.limitSwap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 0, 100);
    vm.stopPrank();
  }

  function test_revertsIf_unrecognizedToken() public {
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setTokenBudget(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    vm.startPrank(guardian);
    vm.expectRevert(IMainnetSwapSteward.UnrecognizedTokenSwap.selector);
    steward.limitSwap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 100);
    vm.stopPrank();
  }

  function test_revertsIf_pairSetNoOracle() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setSwappablePair(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING);
    steward.setTokenOracle(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);

    vm.startPrank(guardian);
    vm.expectRevert();
    steward.limitSwap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 900e6);
  }

  function test_revertsIf_tokenBudgetExceeded() public {
    _setBudgetAndPath();
    vm.prank(guardian);
    vm.expectRevert(IMainnetSwapSteward.InsufficientBudget.selector);
    steward.limitSwap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 2_000e6, 100);
  }

  function test_success_governanceCallerBudgetExceeded() public {
    _setBudgetAndPath();

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit LimitSwapRequested(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 2_000e6, 1900e6);

    steward.limitSwap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 2_000e6, 1900e6);
    vm.stopPrank();
  }

  function test_success() public {
    _setBudgetAndPath();

    vm.startPrank(guardian);
    vm.expectEmit(true, true, true, true, address(steward));
    emit LimitSwapRequested(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 900e6);

    steward.limitSwap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 900e6);
    vm.stopPrank();
  }
}

contract CancelSwapTest is MainnetSwapStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.cancelSwap(
      makeAddr("milkman-instance"),
      AaveV2EthereumAssets.WETH_UNDERLYING,
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      1_000 ether,
      200
    );
  }

  function test_revertsIf_noMatchingTrade() public {
    _setBudgetAndPath();

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.swap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 200);

    vm.expectRevert();
    steward.cancelSwap(
      makeAddr("not-milkman-instance"),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      1_000e6,
      200
    );
    vm.stopPrank();
  }

  function test_successful() public {
    _setBudgetAndPath();

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit SwapRequested(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      USDC_PRICE_FEED,
      AAVE_PRICE_FEED,
      1_000e6,
      200
    );
    steward.swap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 200);

    vm.expectEmit(true, true, true, true, address(steward));
    emit SwapCanceled(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6);
    steward.cancelSwap(
      0x1aEE9BE6489A40366350Dd623c54e488DCb839c3, // Address generated by tests
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      1_000e6,
      200
    );
    vm.stopPrank();
  }
}

contract CancelLimitSwapTest is MainnetSwapStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.cancelLimitSwap(
      makeAddr("milkman-instance"),
      AaveV2EthereumAssets.WETH_UNDERLYING,
      AaveV2EthereumAssets.AAVE_UNDERLYING,
      1_000 ether,
      900 ether
    );
  }

  function test_revertsIf_noMatchingTrade() public {
    _setBudgetAndPath();

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.limitSwap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 900e6);

    vm.expectRevert();
    steward.cancelLimitSwap(
      makeAddr("not-milkman-instance"),
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      1_000e6,
      900e6
    );
    vm.stopPrank();
  }

  function test_successful() public {
    _setBudgetAndPath();

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit LimitSwapRequested(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 900e6);
    steward.limitSwap(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6, 900e6);

    vm.expectEmit(true, true, true, true, address(steward));
    emit SwapCanceled(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, 1_000e6);
    steward.cancelLimitSwap(
      0x1aEE9BE6489A40366350Dd623c54e488DCb839c3, // Address generated by tests
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      1_000e6,
      900e6
    );
    vm.stopPrank();
  }
}

contract TWAPSwapTest is MainnetSwapStewardTest {
  function test_revertsIf_invalidCaller() public {
    uint256 amount = 1_000e18;
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.twapSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.WETH_UNDERLYING,
      amount,
      0.001 ether,
      block.timestamp,
      5,
      1 days,
      0
    );
  }

  function test_revertsIf_fromTokenAddressIsZeroAddress() public {
    vm.expectRevert(IMainnetSwapSteward.UnrecognizedTokenSwap.selector);
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.twapSwap(
      address(0), AaveV3EthereumAssets.WETH_UNDERLYING, 1_000e18, 0.001 ether, block.timestamp, 5, 1 days, 0
    );
  }

  function test_revertsIf_toTokenAddressIsZeroAddress() public {
    vm.expectRevert(IMainnetSwapSteward.UnrecognizedTokenSwap.selector);
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.twapSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING, address(0), 1_000e18, 0.001 ether, block.timestamp, 5, 1 days, 0
    );
  }

  function test_revertsIf_amountIsZero() public {
    vm.expectRevert(IMainnetSwapSteward.InvalidZeroAmount.selector);
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.twapSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.WETH_UNDERLYING,
      0,
      0.001 ether,
      block.timestamp,
      5,
      1 days,
      0
    );
  }

  function test_revertsIf_numberOfPartsIsZero() public {
    vm.expectRevert(IMainnetSwapSteward.InvalidZeroAmount.selector);
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.twapSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.WETH_UNDERLYING,
      1_000e18,
      0.001 ether,
      block.timestamp,
      0,
      1 days,
      0
    );
  }

  function test_successful() public {
    _setBudgetAndPath();

    uint256 amount = 1_000e6;
    uint256 numParts = 5;
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit TWAPSwapRequested(
      AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, amount * numParts
    );
    steward.twapSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      amount,
      0.001 ether,
      block.timestamp,
      numParts,
      1 days,
      0
    );
    vm.stopPrank();
  }
}

contract CancelTWAPSwapTest is MainnetSwapStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.cancelTwapSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      1_000e18,
      0.001 ether,
      block.timestamp,
      5,
      1 days,
      0
    );
  }

  function test_successful() public {
    _setBudgetAndPath();

    uint256 amount = 1_000e6;
    uint256 numParts = 5;

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.twapSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      amount,
      0.001 ether,
      block.timestamp,
      numParts,
      1 days,
      0
    );

    // Creating this order yields the following order hash:
    // 0xa1cd0126c63d96b3d82ba666eb592348a132bfa3dbf6028168fb72df14a3fe28
    bool orderExists = IComposableCow(COMPOSABLE_COW).singleOrders(
      address(steward), 0xa1cd0126c63d96b3d82ba666eb592348a132bfa3dbf6028168fb72df14a3fe28
    );

    assertTrue(orderExists, "Order does not exist");

    vm.expectEmit(true, true, true, true, address(steward));
    emit TWAPSwapCanceled(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING, amount * numParts);

    steward.cancelTwapSwap(
      AaveV3EthereumAssets.USDC_UNDERLYING,
      AaveV3EthereumAssets.AAVE_UNDERLYING,
      amount,
      0.001 ether,
      block.timestamp,
      numParts,
      1 days,
      0
    );

    orderExists = IComposableCow(COMPOSABLE_COW).singleOrders(
      address(steward), 0xa1cd0126c63d96b3d82ba666eb592348a132bfa3dbf6028168fb72df14a3fe28
    );
    assertFalse(orderExists, "Order exists after removing");
    vm.stopPrank();
  }
}

contract SetSwappablePairTest is MainnetSwapStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setSwappablePair(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING);
    vm.stopPrank();
  }

  function test_revertsIf_sameToken() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert(IMainnetSwapSteward.UnrecognizedTokenSwap.selector);
    steward.setSwappablePair(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.USDC_UNDERLYING);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ApprovedToken(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING);
    steward.setSwappablePair(AaveV3EthereumAssets.USDC_UNDERLYING, AaveV3EthereumAssets.AAVE_UNDERLYING);
    vm.stopPrank();
  }
}

contract SetTokenOracleTest is MainnetSwapStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setTokenOracle(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
    vm.stopPrank();
  }

  function test_revertsIf_incompatibleOracleMissingImplementations() public {
    address mockOracle = address(new InvalidMockOracle());

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert();
    steward.setTokenOracle(AaveV3EthereumAssets.USDC_UNDERLYING, mockOracle);

    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit SetTokenOracle(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);

    steward.setTokenOracle(AaveV3EthereumAssets.USDC_UNDERLYING, USDC_PRICE_FEED);
  }
}

contract SetPriceChecker is MainnetSwapStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
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

contract SetLimitOrderPriceChecker is MainnetSwapStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
    steward.setLimitOrderPriceChecker(makeAddr("price-checker"));
  }

  function test_revertsIf_invalidZeroAddress() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert(IMainnetSwapSteward.InvalidZeroAddress.selector);
    steward.setLimitOrderPriceChecker(address(0));
  }

  function test_successful() public {
    address newChecker = makeAddr("new-checker");
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit LimitOrderPriceCheckerUpdated(steward.limitOrderPriceChecker(), newChecker);
    steward.setLimitOrderPriceChecker(newChecker);

    assertEq(steward.limitOrderPriceChecker(), newChecker);
  }
}

contract SetMilkmanTest is MainnetSwapStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
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

contract SetRelayerTest is MainnetSwapStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
    steward.setRelayer(makeAddr("new-relayer"));
  }

  function test_revertsIf_invalidZeroAddress() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert(IMainnetSwapSteward.InvalidZeroAddress.selector);
    steward.setRelayer(address(0));
  }

  function test_successful() public {
    address newRelayer = makeAddr("new-relayer");
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit RelayerAddressUpdated(steward.relayer(), newRelayer);
    steward.setRelayer(newRelayer);

    assertEq(steward.relayer(), newRelayer);
  }
}

contract RescueTokenTest is MainnetSwapStewardTest {
  function test_successful_permissionless() public {
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);

    uint256 aaveAmount = 1_000e18;

    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(steward), aaveAmount);

    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), aaveAmount);

    uint256 initialCollectorAaveBalance =
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR));

    steward.rescueToken(AaveV2EthereumAssets.AAVE_UNDERLYING);

    assertEq(
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorAaveBalance + aaveAmount
    );
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);
  }

  function test_successful_governanceCaller() public {
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);

    uint256 aaveAmount = 1_000e18;

    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(steward), aaveAmount);

    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), aaveAmount);

    uint256 initialCollectorAaveBalance =
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR));

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.rescueToken(AaveV2EthereumAssets.AAVE_UNDERLYING);
    vm.stopPrank();

    assertEq(
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorAaveBalance + aaveAmount
    );
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);
  }
}

contract MaxRescueTest is MainnetSwapStewardTest {
  function test_maxRescue() public {
    assertEq(steward.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), 0);

    uint256 mintAmount = 1_000_000e18;
    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(steward), mintAmount);

    assertEq(steward.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), mintAmount);
  }
}

contract SetTokenBudget is MainnetSwapStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
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
