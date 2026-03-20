// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";

import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Arbitrum, AaveV3ArbitrumAssets} from "aave-address-book/AaveV3Arbitrum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";

import {ArbEthERC20BridgeSteward, IArbEthERC20BridgeSteward} from "src/bridge/arbitrum/ArbEthERC20BridgeSteward.sol";
import {ArbSysMock} from "./ArbSysMock.sol";

/**
 * @dev Test for ArbEthERC20BridgeSteward contract
 * command: forge test -vvv --match-path tests/bridge/arbitrum/ArbEthERC20BridgeSteward.t.sol
 */
contract ArbEthERC20BridgeStewardTest is Test {
    event Bridge(
        address indexed token,
        address indexed l1token,
        uint256 amount,
        address indexed to,
        uint256 nonce
    );
    event BridgeNative(uint256 amount, address indexed to, uint256 nonce);
    event TokenMappingUpdated(
        address indexed l2Token,
        address l1Token,
        address gateway
    );

    ArbEthERC20BridgeSteward steward;

    address OWNER = makeAddr("owner");
    address GUARDIAN = makeAddr("guardian");

    address constant USDC_E_GATEWAY =
        0x096760F208390250649E3e8763348E783AEF5562;
    address constant WETH_GATEWAY =
        0x6c411aD3E74De3E7Bd422b94A27770f5B86C623B;
    address constant STANDARD_GATEWAY =
        0x09e9222E96E7B4AE2a407B98d48e330053351EEe;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"), 320_000_000);

        steward = new ArbEthERC20BridgeSteward(OWNER, GUARDIAN, address(AaveV3Arbitrum.COLLECTOR));

        _etchArbSysMock();

        vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
        IAccessControl(address(AaveV3Arbitrum.COLLECTOR)).grantRole(
            bytes32("FUNDS_ADMIN"),
            address(steward)
        );
        vm.stopPrank();
    }

    function _etchArbSysMock() internal {
        ArbSysMock arbsys = new ArbSysMock();
        vm.etch(
            0x0000000000000000000000000000000000000064,
            address(arbsys).code
        );
    }

    function _fundCollectorUSDCe(uint256 amount) internal {
        deal(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            address(AaveV3Arbitrum.COLLECTOR),
            amount
        );
    }
}

contract ConstructorTest is Test {
    function test_revertsIf_ownerIsZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableInvalidOwner.selector,
                address(0)
            )
        );
        new ArbEthERC20BridgeSteward(address(0), makeAddr("guardian"), makeAddr("collector"));
    }

    function test_revertsIf_guardianIsZeroAddress() public {
        vm.expectRevert(
            IArbEthERC20BridgeSteward.InvalidZeroAddress.selector
        );
        new ArbEthERC20BridgeSteward(makeAddr("owner"), address(0), makeAddr("collector"));
    }

    function test_revertsIf_collectorIsZeroAddress() public {
        vm.expectRevert(
            IArbEthERC20BridgeSteward.InvalidZeroAddress.selector
        );
        new ArbEthERC20BridgeSteward(makeAddr("owner"), makeAddr("guardian"), address(0));
    }

    function test_successful() public {
        address owner = makeAddr("owner");
        address guardian = makeAddr("guardian");
        address collector = address(AaveV3Arbitrum.COLLECTOR);

        ArbEthERC20BridgeSteward _steward = new ArbEthERC20BridgeSteward(
            owner,
            guardian,
            collector
        );

        assertEq(_steward.owner(), owner);
        assertEq(_steward.guardian(), guardian);
        assertEq(_steward.nonce(), 0);
        assertEq(
            _steward.ARB_SYS(),
            0x0000000000000000000000000000000000000064
        );
        assertEq(_steward.COLLECTOR(), collector);
        assertEq(
            _steward.MAINNET_COLLECTOR(),
            address(AaveV3Ethereum.COLLECTOR)
        );
    }
}

contract SetTokenMappingTest is ArbEthERC20BridgeStewardTest {
    function test_revertsIf_notOwner() public {
        vm.startPrank(GUARDIAN);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                GUARDIAN
            )
        );
        steward.setTokenMapping(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_E_GATEWAY
        );
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress_l2Token() public {
        vm.startPrank(OWNER);
        vm.expectRevert(
            IArbEthERC20BridgeSteward.InvalidZeroAddress.selector
        );
        steward.setTokenMapping(
            address(0),
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_E_GATEWAY
        );
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress_l1Token() public {
        vm.startPrank(OWNER);
        vm.expectRevert(
            IArbEthERC20BridgeSteward.InvalidZeroAddress.selector
        );
        steward.setTokenMapping(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            address(0),
            USDC_E_GATEWAY
        );
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress_gateway() public {
        vm.startPrank(OWNER);
        vm.expectRevert(
            IArbEthERC20BridgeSteward.InvalidZeroAddress.selector
        );
        steward.setTokenMapping(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING,
            address(0)
        );
        vm.stopPrank();
    }

    function test_revertsIf_invalidChain() public {
        vm.chainId(1);

        vm.startPrank(OWNER);
        vm.expectRevert(IArbEthERC20BridgeSteward.InvalidChain.selector);
        steward.setTokenMapping(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_E_GATEWAY
        );
        vm.stopPrank();
    }

    function test_successful() public {
        vm.startPrank(OWNER);

        vm.expectEmit(true, true, true, true, address(steward));
        emit TokenMappingUpdated(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_E_GATEWAY
        );

        steward.setTokenMapping(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_E_GATEWAY
        );
        vm.stopPrank();

        (address l1Token, address gateway) = steward.tokenConfigs(
            AaveV3ArbitrumAssets.USDC_UNDERLYING
        );
        assertEq(l1Token, AaveV3EthereumAssets.USDC_UNDERLYING);
        assertEq(gateway, USDC_E_GATEWAY);
    }
}

contract RemoveTokenMappingTest is ArbEthERC20BridgeStewardTest {
    function test_revertsIf_notOwner() public {
        vm.startPrank(GUARDIAN);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                GUARDIAN
            )
        );
        steward.removeTokenMapping(AaveV3ArbitrumAssets.USDC_UNDERLYING);
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(
            IArbEthERC20BridgeSteward.InvalidZeroAddress.selector
        );
        steward.removeTokenMapping(address(0));
        vm.stopPrank();
    }

    function test_revertsIf_invalidChain() public {
        vm.chainId(1);

        vm.startPrank(OWNER);
        vm.expectRevert(IArbEthERC20BridgeSteward.InvalidChain.selector);
        steward.removeTokenMapping(AaveV3ArbitrumAssets.USDC_UNDERLYING);
        vm.stopPrank();
    }

    function test_successful() public {
        vm.startPrank(OWNER);
        steward.setTokenMapping(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_E_GATEWAY
        );

        (address l1Token, address gateway) = steward.tokenConfigs(
            AaveV3ArbitrumAssets.USDC_UNDERLYING
        );
        assertEq(l1Token, AaveV3EthereumAssets.USDC_UNDERLYING);
        assertEq(gateway, USDC_E_GATEWAY);

        vm.expectEmit(true, true, true, true, address(steward));
        emit TokenMappingUpdated(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            address(0),
            address(0)
        );

        steward.removeTokenMapping(AaveV3ArbitrumAssets.USDC_UNDERLYING);
        vm.stopPrank();

        (l1Token, gateway) = steward.tokenConfigs(
            AaveV3ArbitrumAssets.USDC_UNDERLYING
        );
        assertEq(l1Token, address(0));
        assertEq(gateway, address(0));
    }
}

contract BridgeTest is ArbEthERC20BridgeStewardTest {
    function test_revertsIf_invalidChain() public {
        vm.chainId(1);

        vm.expectRevert(IArbEthERC20BridgeSteward.InvalidChain.selector);
        vm.startPrank(OWNER);
        steward.bridge(AaveV3ArbitrumAssets.USDC_UNDERLYING, 1_000e6);
        vm.stopPrank();
    }

    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                address(this)
            )
        );
        steward.bridge(AaveV3ArbitrumAssets.USDC_UNDERLYING, 1_000e6);
    }

    function test_revertsIf_tokenNotAllowed() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IArbEthERC20BridgeSteward.TokenNotAllowed.selector);
        steward.bridge(AaveV3ArbitrumAssets.USDC_UNDERLYING, 1_000e6);
        vm.stopPrank();
    }

    function test_successful() public {
        uint256 amount = 1_000e6;
        _fundCollectorUSDCe(amount);

        assertEq(
            IERC20(AaveV3ArbitrumAssets.USDC_UNDERLYING).balanceOf(
                address(steward)
            ),
            0
        );

        vm.startPrank(OWNER);
        steward.setTokenMapping(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING,
            USDC_E_GATEWAY
        );

        vm.expectEmit(true, true, true, true, address(steward));
        emit Bridge(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING,
            amount,
            address(AaveV3Ethereum.COLLECTOR),
            0
        );
        steward.bridge(AaveV3ArbitrumAssets.USDC_UNDERLYING, amount);
        vm.stopPrank();

        assertEq(
            IERC20(AaveV3ArbitrumAssets.USDC_UNDERLYING).balanceOf(
                address(steward)
            ),
            0
        );
        assertEq(steward.nonce(), 1);
    }
}

contract BridgeNativeTest is ArbEthERC20BridgeStewardTest {
    function test_revertsIf_invalidChain() public {
        vm.chainId(1);

        vm.expectRevert(IArbEthERC20BridgeSteward.InvalidChain.selector);
        vm.startPrank(OWNER);
        steward.bridgeNative(1 ether);
        vm.stopPrank();
    }

    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                address(this)
            )
        );
        steward.bridgeNative(1 ether);
    }

    function test_revertsIf_tokenNotAllowed() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IArbEthERC20BridgeSteward.TokenNotAllowed.selector);
        steward.bridgeNative(1 ether);
        vm.stopPrank();
    }

    function test_successful() public {
        address weth = AaveV3ArbitrumAssets.WETH_UNDERLYING;
        uint256 amount = 1 ether;

        deal(weth, address(AaveV3Arbitrum.COLLECTOR), amount);

        assertEq(IERC20(weth).balanceOf(address(steward)), 0);

        vm.startPrank(OWNER);
        steward.setTokenMapping(
            weth,
            AaveV3EthereumAssets.WETH_UNDERLYING,
            WETH_GATEWAY
        );

        vm.expectEmit(true, true, true, true, address(steward));
        emit BridgeNative(amount, address(AaveV3Ethereum.COLLECTOR), 0);
        steward.bridgeNative(amount);
        vm.stopPrank();

        assertEq(IERC20(weth).balanceOf(address(steward)), 0);
        assertEq(address(steward).balance, 0);
        assertEq(steward.nonce(), 1);
    }
}

contract RescueTokenTest is ArbEthERC20BridgeStewardTest {
    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                address(this)
            )
        );
        steward.rescueToken(AaveV3ArbitrumAssets.WETH_UNDERLYING);
    }

    function test_successful_ownerCaller() public {
        assertEq(
            IERC20(AaveV3ArbitrumAssets.WETH_UNDERLYING).balanceOf(
                address(steward)
            ),
            0
        );

        uint256 rescueAmount = 1_000e18;
        deal(
            AaveV3ArbitrumAssets.WETH_UNDERLYING,
            address(steward),
            rescueAmount
        );

        assertEq(
            IERC20(AaveV3ArbitrumAssets.WETH_UNDERLYING).balanceOf(
                address(steward)
            ),
            rescueAmount
        );

        uint256 initialCollectorBalance = IERC20(
            AaveV3ArbitrumAssets.WETH_UNDERLYING
        ).balanceOf(address(AaveV3Arbitrum.COLLECTOR));

        vm.startPrank(OWNER);
        steward.rescueToken(AaveV3ArbitrumAssets.WETH_UNDERLYING);
        vm.stopPrank();

        assertEq(
            IERC20(AaveV3ArbitrumAssets.WETH_UNDERLYING).balanceOf(
                address(AaveV3Arbitrum.COLLECTOR)
            ),
            initialCollectorBalance + rescueAmount
        );
        assertEq(
            IERC20(AaveV3ArbitrumAssets.WETH_UNDERLYING).balanceOf(
                address(steward)
            ),
            0
        );
    }
}

contract RescueEthTest is ArbEthERC20BridgeStewardTest {
    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                address(this)
            )
        );
        steward.rescueEth();
    }

    function test_successful_ownerCaller() public {
        assertEq(address(steward).balance, 0);

        uint256 amount = 10 ether;
        deal(address(steward), amount);

        assertEq(address(steward).balance, amount);

        uint256 initialCollectorBalance = address(AaveV3Arbitrum.COLLECTOR)
            .balance;

        vm.startPrank(OWNER);
        steward.rescueEth();
        vm.stopPrank();

        assertEq(
            address(AaveV3Arbitrum.COLLECTOR).balance,
            initialCollectorBalance + amount
        );
        assertEq(address(steward).balance, 0);
    }
}

contract ReceiveTest is ArbEthERC20BridgeStewardTest {
    function test_successful_receivesETH() public {
        uint256 balanceBefore = address(steward).balance;
        assertEq(balanceBefore, 0);

        (bool success, ) = address(steward).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(steward).balance, 1 ether);
    }
}

contract MaxRescueTest is ArbEthERC20BridgeStewardTest {
    function test_maxRescue() public {
        assertEq(
            steward.maxRescue(AaveV3ArbitrumAssets.USDC_UNDERLYING),
            0
        );

        uint256 mintAmount = 1_000_000e6;
        deal(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            address(steward),
            mintAmount
        );

        assertEq(
            steward.maxRescue(AaveV3ArbitrumAssets.USDC_UNDERLYING),
            mintAmount
        );
    }
}
