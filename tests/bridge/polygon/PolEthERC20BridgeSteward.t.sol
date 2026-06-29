// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Errors} from "openzeppelin-contracts/contracts/utils/Errors.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {GovernanceV3Polygon} from "aave-address-book/GovernanceV3Polygon.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Polygon, AaveV3PolygonAssets} from "aave-address-book/AaveV3Polygon.sol";

import {PolEthERC20BridgeSteward, IPolEthERC20BridgeSteward} from "src/bridge/polygon/PolEthERC20BridgeSteward.sol";
import {IRootChainManager} from "src/bridge/polygon/interfaces/IRootChainManager.sol";
import {IWithdrawManager} from "src/bridge/polygon/interfaces/IWithdrawManager.sol";
import {IERC20PredicateBurnOnly} from "src/bridge/polygon/interfaces/IERC20PredicateBurnOnly.sol";

/**
 * @dev Test for PolEthERC20BridgeSteward contract
 * command: forge test -vvv --match-path tests/bridge/polygon/PolEthERC20BridgeSteward.t.sol
 */
contract PolEthERC20BridgeStewardTest is Test {
  PolEthERC20BridgeSteward bridgeMainnet;
  PolEthERC20BridgeSteward bridgePolygon;
  uint256 mainnetFork;
  uint256 polygonFork;

  address OWNER = makeAddr("owner");
  address GUARDIAN = makeAddr("guardian");

  function setUp() public {
    bytes32 salt = keccak256(abi.encode(tx.origin, uint256(0)));

    mainnetFork = vm.createSelectFork(vm.rpcUrl("mainnet"), 24277120);
    bridgeMainnet = new PolEthERC20BridgeSteward{salt: salt}(OWNER, GUARDIAN, address(AaveV3Ethereum.COLLECTOR));

    polygonFork = vm.createSelectFork(vm.rpcUrl("polygon"), 81902920);
    bridgePolygon = new PolEthERC20BridgeSteward{salt: salt}(OWNER, GUARDIAN, address(AaveV3Polygon.COLLECTOR));

    vm.startPrank(GovernanceV3Polygon.EXECUTOR_LVL_1);
    IAccessControl(address(AaveV3Polygon.COLLECTOR)).grantRole(bytes32("FUNDS_ADMIN"), address(bridgePolygon));
    vm.stopPrank();
  }
}

contract ConstructorTest is Test {
  function test_revertsIf_ownerIsZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
    new PolEthERC20BridgeSteward(address(0), makeAddr("guardian"), makeAddr("collector"));
  }

  function test_revertsIf_guardianIsZeroAddress() public {
    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidZeroAddress.selector);
    new PolEthERC20BridgeSteward(makeAddr("owner"), address(0), makeAddr("collector"));
  }

  function test_revertsIf_collectorIsZeroAddress() public {
    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidZeroAddress.selector);
    new PolEthERC20BridgeSteward(makeAddr("owner"), makeAddr("guardian"), address(0));
  }

  function test_successful() public {
    address owner = makeAddr("owner");
    address guardian = makeAddr("guardian");
    address collector = makeAddr("collector");

    PolEthERC20BridgeSteward bridge = new PolEthERC20BridgeSteward(owner, guardian, collector);

    assertEq(bridge.owner(), owner, "owner not set");
    assertEq(bridge.guardian(), guardian, "guardian not set");
    assertEq(bridge.COLLECTOR(), collector, "collector not set");
  }
}

contract ReceiveTest is PolEthERC20BridgeStewardTest {
  function test_successful_receivesETH() public {
    vm.selectFork(mainnetFork);

    uint256 balanceBefore = address(bridgeMainnet).balance;

    assertEq(address(bridgeMainnet).balance, 0, "bridge should start with no ETH");

    (bool a,) = address(bridgeMainnet).call{value: 1 ether}("");
    assertTrue(a, "ETH transfer to bridge failed");

    assertEq(balanceBefore + 1 ether, address(bridgeMainnet).balance, "bridge ETH balance not increased");
  }

  function test_successful_receivesPOL() public {
    vm.selectFork(polygonFork);

    uint256 balanceBefore = address(bridgePolygon).balance;

    assertEq(address(bridgePolygon).balance, 0, "bridge should start with no POL");

    (bool a,) = address(bridgePolygon).call{value: 1 ether}("");
    assertTrue(a, "POL transfer to bridge failed");

    assertEq(balanceBefore + 1 ether, address(bridgePolygon).balance, "bridge POL balance not increased");
  }
}

contract RescueTokenTest is PolEthERC20BridgeStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.selectFork(mainnetFork);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this)));
    bridgeMainnet.rescueToken(AaveV3EthereumAssets.AAVE_UNDERLYING);
  }

  function test_successful_ownerCaller() public {
    _test_successful(OWNER);
  }

  function test_successful_guardianCaller() public {
    _test_successful(GUARDIAN);
  }

  function _test_successful(address caller) internal {
    vm.selectFork(mainnetFork);
    assertEq(
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(bridgeMainnet)),
      0,
      "bridge should start with no AAVE"
    );

    uint256 aaveAmount = 1_000e18;

    deal(AaveV3EthereumAssets.AAVE_UNDERLYING, address(bridgeMainnet), aaveAmount);

    assertEq(
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(bridgeMainnet)),
      aaveAmount,
      "bridge AAVE not funded"
    );

    uint256 initialCollectorAaveBalance =
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(caller);
    bridgeMainnet.rescueToken(AaveV3EthereumAssets.AAVE_UNDERLYING);
    vm.stopPrank();

    assertEq(
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      initialCollectorAaveBalance + aaveAmount,
      "AAVE not rescued to collector"
    );
    assertEq(
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING).balanceOf(address(bridgeMainnet)), 0, "bridge AAVE not drained"
    );
  }
}

contract RescueEthTest is PolEthERC20BridgeStewardTest {
  function test_revertsIf_invalidCaller() public {
    vm.selectFork(mainnetFork);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this)));
    bridgeMainnet.rescueEth();
  }

  function test_successful_ownerCaller() public {
    _test_successful(OWNER);
  }

  function test_successful_guardianCaller() public {
    _test_successful(GUARDIAN);
  }

  function _test_successful(address caller) internal {
    vm.selectFork(mainnetFork);
    assertEq(address(bridgeMainnet).balance, 0, "bridge should start with no ETH");

    uint256 amount = 1_000e18;

    deal(address(bridgeMainnet), amount);

    assertEq(address(bridgeMainnet).balance, amount, "bridge ETH not funded");

    uint256 initialCollectorBalance = address(AaveV3Ethereum.COLLECTOR).balance;

    vm.startPrank(caller);
    bridgeMainnet.rescueEth();
    vm.stopPrank();

    assertEq(
      address(AaveV3Ethereum.COLLECTOR).balance, initialCollectorBalance + amount, "ETH not rescued to collector"
    );
    assertEq(address(bridgeMainnet).balance, 0, "bridge ETH not drained");
  }
}

contract MaxRescueTest is PolEthERC20BridgeStewardTest {
  function test_maxRescue() public {
    vm.selectFork(mainnetFork);
    assertEq(bridgeMainnet.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), 0, "maxRescue should be 0 when unfunded");

    uint256 mintAmount = 1_000_000e18;
    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(bridgeMainnet), mintAmount);

    assertEq(
      bridgeMainnet.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), mintAmount, "maxRescue should equal balance"
    );
  }
}

contract IsTokenMapped is PolEthERC20BridgeStewardTest {
  function test_revertsIf_invalidChain() public {
    vm.selectFork(polygonFork);
    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidChain.selector);
    bridgePolygon.isTokenMapped(AaveV3PolygonAssets.USDC_UNDERLYING);
  }

  function test_successful_returnsTrue() public {
    vm.selectFork(mainnetFork);

    assertTrue(bridgeMainnet.isTokenMapped(AaveV3PolygonAssets.USDC_UNDERLYING), "mapped token reported as unmapped");
  }

  function test_successful_returnsFalse() public {
    vm.selectFork(mainnetFork);

    assertFalse(bridgeMainnet.isTokenMapped(makeAddr("new-erc20-token")), "unmapped token reported as mapped");
  }
}

contract SetTokenAllowedTest is PolEthERC20BridgeStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(GUARDIAN);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, GUARDIAN));
    bridgePolygon.setTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, true);
    vm.stopPrank();
  }

  function test_revertsIf_invalidZeroAddress() public {
    vm.selectFork(polygonFork);
    vm.startPrank(OWNER);
    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidZeroAddress.selector);
    bridgePolygon.setTokenAllowed(address(0), true);
    vm.stopPrank();
  }

  function test_revertsIf_invalidChain() public {
    vm.selectFork(mainnetFork);
    vm.startPrank(OWNER);
    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidChain.selector);
    bridgeMainnet.setTokenAllowed(AaveV3EthereumAssets.USDC_UNDERLYING, true);
    vm.stopPrank();
  }

  function test_revertsIf_tokenConfigurationUnchanged() public {
    vm.selectFork(polygonFork);
    vm.startPrank(OWNER);

    bridgePolygon.setTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, true);

    vm.expectRevert(
      abi.encodeWithSelector(
        IPolEthERC20BridgeSteward.TokenConfigurationUnchanged.selector, AaveV3PolygonAssets.USDC_UNDERLYING, true
      )
    );
    bridgePolygon.setTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, true);

    vm.stopPrank();
  }

  function test_successful_allow() public {
    vm.selectFork(polygonFork);
    vm.startPrank(OWNER);

    assertFalse(bridgePolygon.allowedTokens(AaveV3PolygonAssets.USDC_UNDERLYING), "token should start disallowed");

    vm.expectEmit(true, true, true, true, address(bridgePolygon));
    emit IPolEthERC20BridgeSteward.SetTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, true);
    bridgePolygon.setTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, true);

    assertTrue(bridgePolygon.allowedTokens(AaveV3PolygonAssets.USDC_UNDERLYING), "token not allowed after enabling");
  }

  function test_successful_disallow() public {
    vm.selectFork(polygonFork);
    vm.startPrank(OWNER);

    bridgePolygon.setTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, true);
    assertTrue(bridgePolygon.allowedTokens(AaveV3PolygonAssets.USDC_UNDERLYING), "token not allowed after enabling");

    vm.expectEmit(true, true, true, true, address(bridgePolygon));
    emit IPolEthERC20BridgeSteward.SetTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, false);
    bridgePolygon.setTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, false);

    assertFalse(bridgePolygon.allowedTokens(AaveV3PolygonAssets.USDC_UNDERLYING), "token still allowed after disabling");
  }
}

contract BridgeTest is PolEthERC20BridgeStewardTest {
  function test_revertsIf_invalidChain() public {
    vm.selectFork(mainnetFork);

    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidChain.selector);
    vm.startPrank(OWNER);
    bridgeMainnet.bridge(AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_revertsIf_invalidCaller() public {
    vm.selectFork(polygonFork);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this)));
    bridgePolygon.bridge(AaveV3PolygonAssets.USDC_UNDERLYING, 1_000e6);
  }

  function test_revertsIf_tokenNotAllowed() public {
    vm.selectFork(polygonFork);
    vm.startPrank(OWNER);
    vm.expectRevert(IPolEthERC20BridgeSteward.TokenNotAllowed.selector);
    bridgePolygon.bridge(AaveV3PolygonAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.selectFork(polygonFork);
    vm.startPrank(OWNER);
    bridgePolygon.setTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, true);
    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidZeroAmount.selector);
    bridgePolygon.bridge(AaveV3PolygonAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_successful_ownerCaller() public {
    _test_successful(OWNER);
  }

  function test_successful_guardianCaller() public {
    _test_successful(GUARDIAN);
  }

  function _test_successful(address caller) internal {
    vm.selectFork(polygonFork);

    uint256 amount = 1_000e6;
    // Collector holds aTokens; load with some underlying tokens required for the test.
    deal(AaveV3PolygonAssets.USDC_UNDERLYING, address(AaveV3Polygon.COLLECTOR), amount);

    assertEq(
      IERC20(AaveV3PolygonAssets.USDC_UNDERLYING).balanceOf(address(bridgePolygon)),
      0,
      "bridge should start with no USDC"
    );

    // `setTokenAllowed` is owner-only; allowlist as owner before bridging as `caller`.
    vm.prank(OWNER);
    bridgePolygon.setTokenAllowed(AaveV3PolygonAssets.USDC_UNDERLYING, true);

    vm.expectEmit(true, true, true, true, address(bridgePolygon));
    emit IPolEthERC20BridgeSteward.Bridge(AaveV3PolygonAssets.USDC_UNDERLYING, amount);
    vm.prank(caller);
    bridgePolygon.bridge(AaveV3PolygonAssets.USDC_UNDERLYING, amount);

    assertEq(
      IERC20(AaveV3PolygonAssets.USDC_UNDERLYING).balanceOf(address(bridgePolygon)), 0, "bridge USDC not withdrawn"
    );
  }
}

contract BridgePolTest is PolEthERC20BridgeStewardTest {
  function test_revertsIf_invalidChain() public {
    vm.selectFork(mainnetFork);

    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidChain.selector);
    vm.startPrank(OWNER);
    bridgeMainnet.bridgePol(1_000e6, false);
    vm.stopPrank();
  }

  function test_revertsIf_invalidCaller() public {
    vm.selectFork(polygonFork);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this)));
    bridgePolygon.bridgePol(1_000e6, false);
  }

  function test_revertsIf_zeroAmount() public {
    vm.selectFork(polygonFork);

    vm.startPrank(OWNER);
    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidZeroAmount.selector);
    bridgePolygon.bridgePol(0, false);

    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidZeroAmount.selector);
    bridgePolygon.bridgePol(0, true);
    vm.stopPrank();
  }

  function test_revertsIf_tokenNotAllowed() public {
    vm.selectFork(polygonFork);

    vm.startPrank(OWNER);
    vm.expectRevert(IPolEthERC20BridgeSteward.TokenNotAllowed.selector);
    bridgePolygon.bridgePol(1_000e6, false);
    vm.stopPrank();
  }

  function test_successful_ownerCaller_noUnwrap() public {
    _test_successful(OWNER, false);
  }

  function test_successful_guardianCaller_noUnwrap() public {
    _test_successful(GUARDIAN, false);
  }

  function test_successful_ownerCaller_withUnwrap() public {
    _test_successful(OWNER, true);
  }

  function test_successful_guardianCaller_withUnwrap() public {
    _test_successful(GUARDIAN, true);
  }

  function _test_successful(address caller, bool unwrap) internal {
    vm.selectFork(polygonFork);

    uint256 amount = 1_000e6;

    assertEq(
      IERC20(AaveV3PolygonAssets.WPOL_UNDERLYING).balanceOf(address(bridgePolygon)),
      0,
      "bridge should start with no WPOL"
    );
    assertEq(address(bridgePolygon).balance, 0, "bridge should start with no POL");

    // `setTokenAllowed` is owner-only; allowlist as owner before bridging as `caller`.
    vm.prank(OWNER);
    bridgePolygon.setTokenAllowed(AaveV3PolygonAssets.WPOL_UNDERLYING, true);

    vm.expectEmit();
    emit IPolEthERC20BridgeSteward.Bridge(bridgePolygon.POL_POLYGON(), amount);
    vm.prank(caller);
    bridgePolygon.bridgePol(amount, unwrap);

    assertEq(
      IERC20(AaveV3PolygonAssets.WPOL_UNDERLYING).balanceOf(address(bridgePolygon)), 0, "bridge WPOL not withdrawn"
    );
    assertEq(address(bridgePolygon).balance, 0, "bridge POL not withdrawn");
  }
}

contract ExitTest is PolEthERC20BridgeStewardTest {
  function test_revertsIf_invalidChain() public {
    vm.selectFork(polygonFork);

    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidChain.selector);
    vm.prank(OWNER);
    bridgePolygon.exit(AaveV3EthereumAssets.USDC_UNDERLYING, new bytes(0));
  }

  function test_revertsIf_zeroEth() public {
    vm.selectFork(mainnetFork);

    bytes memory burnProof = "";
    vm.mockCall(
      bridgeMainnet.ROOT_CHAIN_MANAGER(),
      abi.encodeWithSelector(IRootChainManager.exit.selector, burnProof),
      abi.encode()
    );

    address ethMockAddress = bridgeMainnet.ETH_MOCK_ADDRESS();
    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidZeroAmount.selector);
    bridgeMainnet.exit(ethMockAddress, burnProof);
  }

  function test_revertsIf_zeroToken() public {
    vm.selectFork(mainnetFork);

    bytes memory burnProof = "";
    vm.mockCall(
      bridgeMainnet.ROOT_CHAIN_MANAGER(),
      abi.encodeWithSelector(IRootChainManager.exit.selector, burnProof),
      abi.encode()
    );

    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidZeroAmount.selector);
    bridgeMainnet.exit(AaveV3EthereumAssets.USDC_UNDERLYING, burnProof);
  }

  function test_revertsIf_proofAlreadyProcessed() public {
    vm.selectFork(mainnetFork);

    bytes memory burnProof =
      hex"f90b7f841d64b820b901605a3ebbdce0b458c848c75ece30aebdc7f404de9f42a1a1d2fff616f4681f8239a5727c70050724191597596befd50c2db26c8c13cc424292fb8dca25990eec222a5378609f41effc1b6f8370a2fa3bff9c1701b0d63108094bc6255a69ffbdd28cdc2237e927128485372aaad7d4164d37669d61d82add0bcb6b8fb1ab7726d81a766ee748222e6253d91038cb42b06614c20fda1f61ede914ee3971321a91ba9674397ca6114056014024786d3b74639d792036e10be9fcca25cc63df3e90e9ce68a4c38ebdd54385ed78e7003995b50975ea080eac5178729d59ffe8c39ba44dce41d776560d9f83de07337ba28cf16a69f99c3be4c8f5001825b11a3e49fb966bcc41e4b74e001be2248c2e7d8319fddb180775cdf18660fa475f8b84db41cefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e030e0542044c7c3e032f92fdf59c763bff5ec2b5c0b34323fff644d44074033f18402bf7ab28464d3b68aa0cb3e23ec4a01a3517fdb7d985bbcd704d8d243c4b6baac426457e5e2b9febad1a01ab4bd6b4a9aef048d60e20a15ad53347c92418591ac1bcafc493834c0b0bc37b9036802f9036401840184b1b4b9010000000200000000000000000008000000000000000000000000100000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000040008000000800000000000000000000100000000000000000000020000000000000000000800000000000000000180000010000004001041000000040000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000080000000000000000000004000000002000000000801000000000004000000000000000000120000000020000000008000000000000000000000000001000000000000200000000800100000f90258f89b942791bca1f2de4661ed88a30c99a7a9449aa84174f863a0ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3efa0000000000000000000000000ca807a3e47684caee82fda347729788639ab9ee8a00000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000f4240f87994ca807a3e47684caee82fda347729788639ab9ee8e1a0884edad9ce6fa2440d8a54cc123490eb96d2768479d49ff9c7366125a9424364b8400000000000000000000000002791bca1f2de4661ed88a30c99a7a9449aa8417400000000000000000000000000000000000000000000000000000000000f4240f9013d940000000000000000000000000000000000001010f884a04dfe1bbbcf077ddc3e01291eea2d5c70c2b422b415d95645b9adcfd678cb1d63a00000000000000000000000000000000000000000000000000000000000001010a00000000000000000000000002fb7d6beb9ad75c1ffd392681cc68171b8551107a00000000000000000000000009ead03f7136fc6b4bdb0780b00a1c14ae5a8b6d0b8a000000000000000000000000000000000000000000000000000047f88eb62fdf8000000000000000000000000000000000000000000000000f6299bdc7ee7898c000000000000000000000000000000000000000000000231bb90e991a999704a000000000000000000000000000000000000000000000000f6251c5393848b94000000000000000000000000000000000000000000000231bb95691a94fc6e42b90659f90656f8d1a0edd856137974cc770c8ff2f0ae9691f6c343a5c3ea042cf43226064241cb4b48a060098e59303c6f97eb4ee11a31d7ff224886f7ee97e47046ffc12ae2cb345607a08c1c9ddcde956a2188fecf78ac3ffe88c5300e39016cedbc726eaa480528f2d9a0af1a8f4ebb2c2f62619a683563a51fcf38e82d6213ad60506a1f4472145a3d52a06a5a57546f33675a2827617483ba12e200a7666f107115010549cc72ce933a5c808080a04b654e084485e25f10ab6e63905b7b0320f3da65ed062eee77511204089557af8080808080808080f90211a0d18ede4a1807a43ea2daf1f43d94127479f5a5406ba4d9e1e1820b9fabc23f1ca0ae8d8894a06c033da2ef24d0e4b7f4d985fea9e4a808d0616a93e17c7d5ca556a08a42f3eed60ecb787277f3534c848ac3e881be498993840a4c550764414c45e7a0db5ed558b0871c5828866ff7ff1cdb6b7b28cce715c74837c704308e4e85d8d8a0e00d8c69aee0605693c270aa8bd5e4c156bf6782952df288e8f3002963ad51d1a06568d90c67a2972365abd5f2606aa2529d39cb7bc23eb0a130d673080697d715a0747a3b807241f10bee3360edb4345a815328fb885c8e8f693e1af88503c41bc4a01767769f78e7f63f7142b0468c85a7a98aad577dd31044167c60e4d77e5d5ad2a09e8fddbe949014bb311de991cb543da9fb3104cf4db4f87e4e800911c1d99f7da0de90b23b0cf3a2685afd3b221a1660d8655212ca01c82c5680a81f807e2b3aada0281f75fda5226a1f34390b09765843e2af5a3644ba577a555431b7f2dcef2c86a094065d6acf8901d70605b0c198b0ff5df364efc232f6c536c7df5a7632b4a7bea0a32affd2aad98f44bce23eed618177c1a51cdd617ef72ec8be8d55bda90bf59fa099a19c0a99d4913f691877ce52612a1da389b99ab2a51c471346ee07575f0780a0b948b78e59be6f2a016c545d93ae7efdf615bf212bbdc1fa568bc2c96752c044a09e07bfdc8af384b3f2f1a65561bfd28ebd85d3f2abbfba13108d25a38a25a1cd80f9036c20b9036802f9036401840184b1b4b9010000000200000000000000000008000000000000000000000000100000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000040008000000800000000000000000000100000000000000000000020000000000000000000800000000000000000180000010000004001041000000040000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000080000000000000000000004000000002000000000801000000000004000000000000000000120000000020000000008000000000000000000000000001000000000000200000000800100000f90258f89b942791bca1f2de4661ed88a30c99a7a9449aa84174f863a0ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3efa0000000000000000000000000ca807a3e47684caee82fda347729788639ab9ee8a00000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000f4240f87994ca807a3e47684caee82fda347729788639ab9ee8e1a0884edad9ce6fa2440d8a54cc123490eb96d2768479d49ff9c7366125a9424364b8400000000000000000000000002791bca1f2de4661ed88a30c99a7a9449aa8417400000000000000000000000000000000000000000000000000000000000f4240f9013d940000000000000000000000000000000000001010f884a04dfe1bbbcf077ddc3e01291eea2d5c70c2b422b415d95645b9adcfd678cb1d63a00000000000000000000000000000000000000000000000000000000000001010a00000000000000000000000002fb7d6beb9ad75c1ffd392681cc68171b8551107a00000000000000000000000009ead03f7136fc6b4bdb0780b00a1c14ae5a8b6d0b8a000000000000000000000000000000000000000000000000000047f88eb62fdf8000000000000000000000000000000000000000000000000f6299bdc7ee7898c000000000000000000000000000000000000000000000231bb90e991a999704a000000000000000000000000000000000000000000000000f6251c5393848b94000000000000000000000000000000000000000000000231bb95691a94fc6e4282003580";

    vm.expectRevert("RootChainManager: EXIT_ALREADY_PROCESSED");
    bridgeMainnet.exit(AaveV3EthereumAssets.USDC_UNDERLYING, burnProof);
  }

  function test_revertsIf_failedToSendEth() public {
    vm.selectFork(mainnetFork);

    address ethMockAddress = bridgeMainnet.ETH_MOCK_ADDRESS();

    bytes memory burnProof = "";
    vm.mockCall(
      bridgeMainnet.ROOT_CHAIN_MANAGER(),
      abi.encodeWithSelector(IRootChainManager.exit.selector, burnProof),
      abi.encode()
    );
    // Make the ETH-forwarding call to the collector (empty calldata) revert.
    vm.mockCallRevert(address(AaveV3Ethereum.COLLECTOR), new bytes(0), bytes("collector rejects ETH"));
    deal(address(bridgeMainnet), 1 ether);

    // `Address.sendValue` surfaces a failed transfer as `Errors.FailedCall`.
    vm.expectRevert(Errors.FailedCall.selector);
    bridgeMainnet.exit(ethMockAddress, burnProof);
  }

  function test_successful_erc20() public {
    vm.selectFork(mainnetFork);

    uint256 amount = 1_000e6;

    bytes memory burnProof = "";
    vm.mockCall(
      bridgeMainnet.ROOT_CHAIN_MANAGER(),
      abi.encodeWithSelector(IRootChainManager.exit.selector, burnProof),
      abi.encode()
    );
    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(bridgeMainnet), amount);

    uint256 collectorBalanceBefore =
      IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.expectEmit(true, true, true, true, address(bridgeMainnet));
    emit IPolEthERC20BridgeSteward.WithdrawToCollector(AaveV3EthereumAssets.USDC_UNDERLYING, amount);
    bridgeMainnet.exit(AaveV3EthereumAssets.USDC_UNDERLYING, burnProof);

    assertEq(
      IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      collectorBalanceBefore + amount,
      "USDC not forwarded to collector"
    );
    assertEq(
      IERC20(AaveV3EthereumAssets.USDC_UNDERLYING).balanceOf(address(bridgeMainnet)), 0, "bridge USDC not drained"
    );
  }

  function test_successful_eth() public {
    vm.selectFork(mainnetFork);

    uint256 amount = 1 ether;
    address ethMockAddress = bridgeMainnet.ETH_MOCK_ADDRESS();

    bytes memory burnProof = "";
    vm.mockCall(
      bridgeMainnet.ROOT_CHAIN_MANAGER(),
      abi.encodeWithSelector(IRootChainManager.exit.selector, burnProof),
      abi.encode()
    );
    deal(address(bridgeMainnet), amount);

    uint256 collectorBalanceBefore = address(AaveV3Ethereum.COLLECTOR).balance;

    vm.expectEmit(true, true, true, true, address(bridgeMainnet));
    emit IPolEthERC20BridgeSteward.WithdrawToCollector(ethMockAddress, amount);
    bridgeMainnet.exit(ethMockAddress, burnProof);

    assertEq(
      address(AaveV3Ethereum.COLLECTOR).balance, collectorBalanceBefore + amount, "ETH not forwarded to collector"
    );
    assertEq(address(bridgeMainnet).balance, 0, "bridge ETH not drained");
  }
}

contract ExitPolTest is PolEthERC20BridgeStewardTest {
  function test_revertsIf_invalidChain() public {
    vm.selectFork(polygonFork);

    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidChain.selector);
    bridgePolygon.exitPol();
  }

  function test_successful() public {
    vm.selectFork(mainnetFork);

    address pol = bridgeMainnet.POL_MAINNET();
    uint256 amount = 1_000e18;

    // Mock processExits
    vm.mockCall(
      bridgeMainnet.WITHDRAW_MANAGER(),
      abi.encodeWithSelector(IWithdrawManager.processExits.selector, pol),
      abi.encode()
    );
    deal(pol, address(bridgeMainnet), amount);

    uint256 collectorBalanceBefore = IERC20(pol).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.expectEmit(true, true, true, true, address(bridgeMainnet));
    emit IPolEthERC20BridgeSteward.WithdrawToCollector(pol, amount);
    bridgeMainnet.exitPol();

    assertEq(
      IERC20(pol).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      collectorBalanceBefore + amount,
      "POL not forwarded to collector"
    );
    assertEq(IERC20(pol).balanceOf(address(bridgeMainnet)), 0, "bridge POL not drained");
  }
}

contract ConfirmPolExitTest is PolEthERC20BridgeStewardTest {
  function test_revertsIf_invalidChain() public {
    vm.selectFork(polygonFork);

    vm.expectRevert(IPolEthERC20BridgeSteward.InvalidChain.selector);
    bridgePolygon.confirmPolExit(new bytes(0));
  }

  function test_revertsIf_proofAlreadyProcessed() public {
    vm.selectFork(mainnetFork);

    bytes memory burnProof =
      hex"f90d298422e1e6b0b90120433b0d2d0234f58cd9e8404894ba9f3687fc8b0927c359b4c9977f182677eed901942bbf20f1fd9032d1b173b911d2e1d9c0c9de6ae79f6e1330d16e09c833ca452ce56e950ea226ca527012f881475efdd7c622f17394e632a743de1ef352a8b72395afa69ed1137763e1c64f796e1e90a7b85f377f95f03d3ea1eba29f7ee50a60268d6d6a86697fd881c0f18ea8e643b3365e7dc533940650d7606b9d824994b9a9c26e68990484952e8955fdbb8a01177074bc0872e63af46be69c9a0ee3150e0114ebc8a68469240747e157b6a667ed8df73ec4560b77dd60c6dcc1d47517e30d0a87fde2ab53b50ba69a2355ba1086b1b9b88648a8110c4f01a0c57d952b9e4499ec65c0442fc2210d7a54856bb36d5b5fb080f1bfb36b0df40d04cdd784033864598465de198ba0ba95e013f19a21f66a47256c2e42b006ec54f3d13e4cd4ce32cbdba025859e46a01c7d305fdf034cd665c96da4d8902557e4e29b54116e0fd4a235fb16421248d6b9046d02f90469018303f667b9010000000000000000000000000000000000000200000000000000000000000000000000000000000000000810100000000000008000000000000000000000000000000000000000000000000000000000800000000000000000000100000000000000000000000080000000000000000000000000000020000080000000001000000000000000000000080000000000000000000000000004000000000000000000200000000000000000000000000000000000000000000000000000000000004000000000000000000001000000000000000000000000800000108000200000000100000000000000080000000000000000000000000000000000000000100000f9035ef9013d940000000000000000000000000000000000001010f884a0e6497e3ee548a3372136af2fcb0696db31fc6cf20260707645068bd3fe97f3c4a00000000000000000000000000000000000000000000000000000000000001010a0000000000000000000000000ebaca92a7be0b5f658c0770a81951bba22da5638a00000000000000000000000000000000000000000000000000000000000001010b8a00000000000000000000000000000000000000000000008812d5ac25c01b45bf000000000000000000000000000000000000000000000088133e07ef64641f1f000000000000000000000000000000000000000001c5e2e002e82004460d76f970000000000000000000000000000000000000000000000000685bc9a448d960000000000000000000000000000000000000000001c5e36815bdcc2a0628bcb87f8dc940000000000000000000000000000000000001010f863a0ebff2602b3f468259e1e99f613fed6691f3a6526effe6ef3e768ba7ae7a36c4fa00000000000000000000000007d1afa7b718fb893db30a3abc0cfc608aacfebb0a0000000000000000000000000ebaca92a7be0b5f658c0770a81951bba22da5638b8600000000000000000000000000000000000000000000008812d5ac25c01b45bf00000000000000000000000000000000000000000000000000685bc9a448d96000000000000000000000000000000000000000000000000000685bc9a448d9600f9013d940000000000000000000000000000000000001010f884a04dfe1bbbcf077ddc3e01291eea2d5c70c2b422b415d95645b9adcfd678cb1d63a00000000000000000000000000000000000000000000000000000000000001010a0000000000000000000000000ebaca92a7be0b5f658c0770a81951bba22da5638a0000000000000000000000000fcccd43296d9c1601a904eca9b339d94a5e5e098b8a00000000000000000000000000000000000000000000000000008ff34526de00000000000000000000000000000000000000000000000088134d9397f946a5bf00000000000000000000000000000000000000000000009e56bc92173ffaf923400000000000000000000000000000000000000000000088134d03a4b41fc7bf00000000000000000000000000000000000000000000009e56bd220a8521d7234b9073ef9073bf8d1a0d6213f494e7bb1418661069c6da13302d80fb5401182aa96d08220bc0dc8e071a09f6c1782a3c25bf4f666c950141efa981d6e384dcba2f7d6e187494e6b6da64ea0e2802b6c219907c6c4df3941d375d6af0178a87942214cd316153b7b80ba0b86a028698766cbf0cbe3ea9d11207f42080892266da139cbb88dfde2f61e9110f094a0bd71b87290463b0d762268927681cc8eb886ab9aa795e17afdb805288c72b515808080a0ace20d838d862dad238ab335ab3beaee728905d708276f3cb0959ef87a4c862f8080808080808080f901f180a034a531f189309d3615eaa5355b802540eec79d070a52783155500c7b6dbd90f3a038c800c74acdbfb17409a84d9fec28ddb1880095996693fe214604e8b41f02dba027d6ab89f4c64dc0fbd39a63fed8aa2456afc345c8d56e3b1f035dc58027b7f4a03260d7a2ef33945fff14a7d4254a54eb4dddfe2c8666296fc84d726532044082a0f218f242a23fb2006706d42b3e962e6606d5bae8ee2ee46dccd20c51479ae8dda060def2876dd04c270193c01b0911bcb2cf205bdd97fde1b411c1af54b98eb90fa09031ddbf92abfdcf8a5097ec49926df6ce56c600c1e9ecfd6ac5dff3003ddfc0a04962eac743a962f31f72999756fb6280262a2795ed61c5af866352aa140c63ada0bcaaf83e7f037d8965cff1cc28f1580c33958d46717fbf8556b3cea24a78b657a0c843c1561e9e5b73f9dd8b9dbf76d642509dac5f2c8181e8eabc09ec1ebfd1dda09686974194e882ff96c8c8dc0d4adee666b6ea074f6d297fc3de17e0de35b460a0408c89cc15230136f4a3d3e945d8c9ff1affe7360315de4079162eef95164210a0550a8f4f040ebf7fc1c58c4c0689f9e97b0079ef8d29d3ac31471e3d05e52e0da0a8fe18a87d802e43448d1b9ad5c0e3029018a1b47ba25dc2e8f85e82d8dfcaf3a045053b7bbc7d3081fdbc9eb37620c558888a8e9e8deabc89ada98a599862f88080f9047120b9046d02f90469018303f667b9010000000000000000000000000000000000000200000000000000000000000000000000000000000000000810100000000000008000000000000000000000000000000000000000000000000000000000800000000000000000000100000000000000000000000080000000000000000000000000000020000080000000001000000000000000000000080000000000000000000000000004000000000000000000200000000000000000000000000000000000000000000000000000000000004000000000000000000001000000000000000000000000800000108000200000000100000000000000080000000000000000000000000000000000000000100000f9035ef9013d940000000000000000000000000000000000001010f884a0e6497e3ee548a3372136af2fcb0696db31fc6cf20260707645068bd3fe97f3c4a00000000000000000000000000000000000000000000000000000000000001010a0000000000000000000000000ebaca92a7be0b5f658c0770a81951bba22da5638a00000000000000000000000000000000000000000000000000000000000001010b8a00000000000000000000000000000000000000000000008812d5ac25c01b45bf000000000000000000000000000000000000000000000088133e07ef64641f1f000000000000000000000000000000000000000001c5e2e002e82004460d76f970000000000000000000000000000000000000000000000000685bc9a448d960000000000000000000000000000000000000000001c5e36815bdcc2a0628bcb87f8dc940000000000000000000000000000000000001010f863a0ebff2602b3f468259e1e99f613fed6691f3a6526effe6ef3e768ba7ae7a36c4fa00000000000000000000000007d1afa7b718fb893db30a3abc0cfc608aacfebb0a0000000000000000000000000ebaca92a7be0b5f658c0770a81951bba22da5638b8600000000000000000000000000000000000000000000008812d5ac25c01b45bf00000000000000000000000000000000000000000000000000685bc9a448d96000000000000000000000000000000000000000000000000000685bc9a448d9600f9013d940000000000000000000000000000000000001010f884a04dfe1bbbcf077ddc3e01291eea2d5c70c2b422b415d95645b9adcfd678cb1d63a00000000000000000000000000000000000000000000000000000000000001010a0000000000000000000000000ebaca92a7be0b5f658c0770a81951bba22da5638a0000000000000000000000000fcccd43296d9c1601a904eca9b339d94a5e5e098b8a00000000000000000000000000000000000000000000000000008ff34526de00000000000000000000000000000000000000000000000088134d9397f946a5bf00000000000000000000000000000000000000000000009e56bc92173ffaf923400000000000000000000000000000000000000000000088134d03a4b41fc7bf00000000000000000000000000000000000000000000009e56bd220a8521d723482000501";

    vm.expectRevert("Withdrawer and burn exit tx do not match");
    bridgeMainnet.confirmPolExit(burnProof);
  }

  function test_successful() public {
    vm.selectFork(mainnetFork);

    bytes memory burnProof = hex"1234";
    vm.mockCall(
      bridgeMainnet.ERC20_PREDICATE_BURN(),
      abi.encodeWithSelector(IERC20PredicateBurnOnly.startExitWithBurntTokens.selector, burnProof),
      abi.encode()
    );

    vm.expectEmit(true, true, true, true, address(bridgeMainnet));
    emit IPolEthERC20BridgeSteward.ConfirmExit(burnProof);
    bridgeMainnet.confirmPolExit(burnProof);
  }
}
