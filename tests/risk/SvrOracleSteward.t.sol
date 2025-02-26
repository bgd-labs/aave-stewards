// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {GovV3Helpers} from "aave-helpers/src/GovV3Helpers.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {
  Ownable, OwnableWithGuardian, IWithGuardian
} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";

import {ISvrOracleSteward} from "../../src/risk/interfaces/ISvrOracleSteward.sol";
import {SvrOracleSteward, DeploySvrOracleSteward_Lib} from "../../script/SvrOracleSteward.s.sol";

contract SvrOracleStewardBaseTest is Test {
  SvrOracleSteward internal steward;
  address guardian = address(1);

  address constant cbBTC_SVR_ORACLE = 0x77E55306eeDb1F94a4DcFbAa6628ef87586BC651;

  function setUp() external {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21882843);
    // deployment configures svrOracle for cbBTC
    steward = DeploySvrOracleSteward_Lib._deployMainnet();
    vm.prank(AaveV3Ethereum.ACL_ADMIN);
    AaveV3Ethereum.ACL_MANAGER.addAssetListingAdmin(address(steward));
  }

  function test_configureOracle() public {
    vm.prank(steward.owner());
    ISvrOracleSteward.AssetOracle memory config = ISvrOracleSteward.AssetOracle({
      asset: AaveV3EthereumAssets.cbBTC_UNDERLYING,
      svrOracle: address(cbBTC_SVR_ORACLE)
    });
    steward.configureOracle(config);

    (address cachedOracle, address svrOracle) = steward.getOracleConfig(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    address wbtcOracle = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    assertEq(svrOracle, cbBTC_SVR_ORACLE);
    assertEq(wbtcOracle, cachedOracle);
  }

  function test_activateSvrOracle_shouldRevertIfNotConfig() public {
    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(ISvrOracleSteward.NoSvrOracleConfigured.selector));
    steward.enableSvrOracle(AaveV3EthereumAssets.WBTC_UNDERLYING);
  }

  function test_activateSvroracle() public {
    vm.prank(guardian);
    steward.enableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    address cbBTCOracle = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    assertEq(cbBTCOracle, cbBTC_SVR_ORACLE);
  }

  function test_activateSvroracle_shouldRevertIfOracleChangedOutside() public {
    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.cbBTC_UNDERLYING;
    address[] memory feeds = new address[](1);
    feeds[0] = address(42);
    vm.prank(steward.owner());
    AaveV3Ethereum.ORACLE.setAssetSources(assets, feeds);

    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(ISvrOracleSteward.UnknownOracle.selector));
    steward.enableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_disableSvrOracle_shouldRevertIfNotConfig() external {
    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(ISvrOracleSteward.UnknownOracle.selector));
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_disableSvrOracle() external {
    address cbBTCOracleBefore = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    test_activateSvroracle();

    vm.prank(guardian);
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    address cbBTCOracle = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    assertEq(cbBTCOracle, cbBTCOracleBefore);
  }

  function test_disableSvrOracle_shouldRevertifOutsideOracleChange() external {
    test_activateSvroracle();

    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.cbBTC_UNDERLYING;
    address[] memory feeds = new address[](1);
    feeds[0] = address(42);
    vm.prank(steward.owner());
    AaveV3Ethereum.ORACLE.setAssetSources(assets, feeds);

    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(ISvrOracleSteward.UnknownOracle.selector));
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_ifNoGuardian_activateSvrOracle_shouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianInvalidCaller.selector, address(this)));
    steward.enableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_ifNoGuardian_disableSvrOracle_shouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianInvalidCaller.selector, address(this)));
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_ifNoOwner_configureOracle_shouldRevert() external {
    ISvrOracleSteward.AssetOracle memory config =
      ISvrOracleSteward.AssetOracle({asset: address(9), svrOracle: address(100)});

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
    steward.configureOracle(config);
  }
}
