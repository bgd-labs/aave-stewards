// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {Ownable} from "solidity-utils/contracts/oz-common/Ownable.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3EthereumEtherFi, AaveV3EthereumEtherFiAssets} from "aave-address-book/AaveV3EthereumEtherFi.sol";
import {AaveV2Ethereum, AaveV2EthereumAssets} from "aave-address-book/AaveV2Ethereum.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {CollectorUtils} from "aave-helpers/src/CollectorUtils.sol";
import {ProxyAdmin} from "solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {ICollector} from "aave-address-book/common/ICollector.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

import {PoolSteward, IPoolSteward} from "src/finance/PoolSteward.sol";

/**
 * @dev Tests for PoolSteward contract
 * command: forge test -vvv --match-path tests/finance/PoolSteward.t.sol
 */
contract PoolStewardTest is Test {
    event MinimumTokenBalanceUpdated(address indexed token, uint newAmount);
    event Upgraded(address indexed impl);
    event ApprovedPool(address indexed pool, bytes version);
    event RevokedPool(address indexed pool);

    address public constant USDC_PRICE_FEED =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant AAVE_PRICE_FEED =
        0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
    address public constant EXECUTOR =
        0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;
    address public constant guardian = address(82);
    address public alice = address(43);
    PoolSteward public steward;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21580838); // https://etherscan.io/block/21580838

        address[] memory v2Pools = new address[](1);
        v2Pools[0] = address(AaveV2Ethereum.POOL);

        address[] memory v3Pools = new address[](3);
        v3Pools[0] = address(AaveV3Ethereum.POOL);
        v3Pools[1] = address(AaveV3EthereumEtherFi.POOL);
        v3Pools[2] = 0x4e033931ad43597d96D6bcc25c280717730B58B1;
        steward = new PoolSteward(
            GovernanceV3Ethereum.EXECUTOR_LVL_1,
            guardian,
            address(AaveV3Ethereum.COLLECTOR),
            v2Pools,
            v3Pools
        );

        vm.label(0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c, "Collector");
        vm.label(alice, "Alice");
        vm.label(guardian, "Guardian");
        vm.label(EXECUTOR, "Executor");
        vm.label(address(steward), "PoolSteward");

        vm.startPrank(EXECUTOR);
        AaveV3Ethereum.COLLECTOR.setFundsAdmin(address(steward));
        Ownable(MiscEthereum.AAVE_SWAPPER).transferOwnership(address(steward));

        vm.stopPrank();

        deal(
            AaveV3EthereumAssets.USDC_UNDERLYING,
            address(AaveV3Ethereum.COLLECTOR),
            1_000_000e6
        );
    }
}

contract Function_depositV3 is PoolStewardTest {
    function test_revertsIf_notOwnerOrQuardian() public {
        vm.startPrank(alice);

        vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
        steward.depositV3(
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );
        vm.stopPrank();
    }

    function test_resvertsIf_zeroAmount() public {
        vm.startPrank(guardian);

        vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
        steward.depositV3(
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            0
        );
        vm.stopPrank();
    }

    function test_success() public {
        uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN)
            .balanceOf(address(AaveV3Ethereum.COLLECTOR));
        vm.startPrank(guardian);

        steward.depositV3(
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );

        assertGt(
            IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(
                address(AaveV3Ethereum.COLLECTOR)
            ),
            balanceBefore
        );
        vm.stopPrank();
    }
}

contract Function_migrateV2toV3 is PoolStewardTest {
    function test_revertsIf_notOwnerOrQuardian() public {
        vm.startPrank(alice);

        vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
        steward.migrateV2toV3(
            address(AaveV2Ethereum.POOL),
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );
        vm.stopPrank();
    }

    function test_resvertsIf_zeroAmount() public {
        vm.startPrank(guardian);

        vm.expectRevert(IPoolSteward.InvalidZeroAmount.selector);
        steward.migrateV2toV3(
            address(AaveV2Ethereum.POOL),
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            0
        );
        vm.stopPrank();
    }

    function test_revertsIf_invalidV2Pool() public {
        vm.startPrank(guardian);

        vm.expectRevert(IPoolSteward.UnrecognizedPool.selector);
        steward.migrateV2toV3(
            makeAddr("fake-pool"),
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );
    }

    function test_revertsIf_invalidV3Pool() public {
        vm.startPrank(guardian);

        vm.expectRevert(IPoolSteward.UnrecognizedPool.selector);
        steward.migrateV2toV3(
            address(AaveV2Ethereum.POOL),
            makeAddr("fake-pool"),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );
    }

    function test_success() public {
        uint256 balanceV2Before = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN)
            .balanceOf(address(AaveV3Ethereum.COLLECTOR));
        uint256 balanceV3Before = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN)
            .balanceOf(address(AaveV3Ethereum.COLLECTOR));

        vm.startPrank(guardian);

        steward.migrateV2toV3(
            address(AaveV2Ethereum.POOL),
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );

        assertLt(
            IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(
                address(AaveV3Ethereum.COLLECTOR)
            ),
            balanceV2Before
        );
        assertGt(
            IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(
                address(AaveV3Ethereum.COLLECTOR)
            ),
            balanceV3Before
        );
        vm.stopPrank();
    }
}

contract Function_migrateBetweenV3 is PoolStewardTest {
    function test_revertsIf_notOwnerOrQuardian() public {
        vm.startPrank(alice);

        vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
        steward.migrateBetweenV3(
            address(AaveV3Ethereum.POOL),
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );
        vm.stopPrank();
    }

    function test_resvertsIf_zeroAmount() public {
        vm.startPrank(guardian);

        vm.expectRevert(IPoolSteward.InvalidZeroAmount.selector);
        steward.migrateBetweenV3(
            address(AaveV3Ethereum.POOL),
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            0
        );
        vm.stopPrank();
    }

    function test_success() public {
        uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN)
            .balanceOf(address(AaveV3Ethereum.COLLECTOR));
        uint256 balanceBeforeEtherFi = IERC20(
            AaveV3EthereumEtherFiAssets.USDC_A_TOKEN
        ).balanceOf(address(AaveV3Ethereum.COLLECTOR));

        vm.startPrank(guardian);

        steward.migrateBetweenV3(
            address(AaveV3Ethereum.POOL),
            address(AaveV3EthereumEtherFi.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );

        assertEq(
            IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(
                address(AaveV3Ethereum.COLLECTOR)
            ),
            balanceBefore - 1_000e6
        );
        assertEq(
            IERC20(AaveV3EthereumEtherFiAssets.USDC_A_TOKEN).balanceOf(
                address(AaveV3Ethereum.COLLECTOR)
            ),
            balanceBeforeEtherFi + 1_000e6
        );
        vm.stopPrank();
    }
}

contract Function_withdrawV3 is PoolStewardTest {
    function test_revertsIf_notOwnerOrQuardian() public {
        vm.startPrank(alice);

        vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
        steward.withdrawV3(
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );
        vm.stopPrank();
    }

    function test_resvertsIf_zeroAmount() public {
        vm.startPrank(guardian);

        vm.expectRevert(IPoolSteward.InvalidZeroAmount.selector);
        steward.withdrawV3(
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            0
        );
        vm.stopPrank();
    }

    function test_success() public {
        uint256 balanceV3Before = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN)
            .balanceOf(address(AaveV3Ethereum.COLLECTOR));

        vm.startPrank(guardian);
        steward.withdrawV3(
            address(AaveV3Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );

        assertLt(
            IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(
                address(AaveV3Ethereum.COLLECTOR)
            ),
            balanceV3Before
        );
        vm.stopPrank();
    }
}

contract Function_withdrawV2 is PoolStewardTest {
    function test_revertsIf_notOwnerOrQuardian() public {
        vm.startPrank(alice);

        vm.expectRevert("ONLY_BY_OWNER_OR_GUARDIAN");
        steward.withdrawV2(
            address(AaveV2Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            1_000e6
        );
        vm.stopPrank();
    }

    function test_resvertsIf_zeroAmount() public {
        vm.startPrank(guardian);

        vm.expectRevert(IPoolSteward.InvalidZeroAmount.selector);
        steward.withdrawV2(
            address(AaveV2Ethereum.POOL),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            0
        );
        vm.stopPrank();
    }

    function test_success() public {
        vm.startPrank(guardian);

        uint256 balanceV2Before = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN)
            .balanceOf(address(AaveV3Ethereum.COLLECTOR));

        vm.startPrank(guardian);
        steward.withdrawV2(
            address(AaveV2Ethereum.POOL),
            AaveV2EthereumAssets.USDC_UNDERLYING,
            1_0_000e6
        );

        assertLt(
            IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(
                address(AaveV3Ethereum.COLLECTOR)
            ),
            balanceV2Before
        );
        vm.stopPrank();
    }
}

contract Function_approvePool is PoolStewardTest {
    function test_revertsIf_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert("Ownable: caller is not the owner");
        steward.approvePool(address(AaveV3Ethereum.POOL), true);
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress() public {
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

        vm.expectRevert(IPoolSteward.InvalidZeroAddress.selector);
        steward.approvePool(address(0), true);
        vm.stopPrank();
    }

    function test_success() public {
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

        vm.expectEmit(true, true, true, true, address(steward));
        emit ApprovedPool(address(50), "v3");
        steward.approvePool(address(50), true);

        vm.expectEmit(true, true, true, true, address(steward));
        emit ApprovedPool(address(51), "v2");
        steward.approvePool(address(51), false);
        vm.stopPrank();
    }
}

contract Function_revokePool is PoolStewardTest {
    function test_revertsIf_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert("Ownable: caller is not the owner");
        steward.revokePool(address(AaveV3Ethereum.POOL), true);
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress() public {
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

        vm.expectRevert(IPoolSteward.UnrecognizedPool.selector);
        steward.revokePool(address(0), true);
        vm.stopPrank();
    }

    function test_success() public {
        vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

        vm.expectEmit(true, true, true, true, address(steward));
        emit RevokedPool(address(AaveV3Ethereum.POOL));
        steward.revokePool(address(AaveV3Ethereum.POOL), true);
        vm.stopPrank();
    }
}
