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

  address constant WBTC_SVR_ORACLE = 0x270A3a705837e8Ec52C3dECd083bf9796654cb74;

  function setUp() external {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21882843);
    // deployment configures oracle for cbBTC
    steward = DeploySvrOracleSteward_Lib._deployMainnet();
    vm.prank(AaveV3Ethereum.ACL_ADMIN);
    AaveV3Ethereum.ACL_MANAGER.addAssetListingAdmin(address(steward));
  }

  function test_configureOracle() public {
    vm.prank(steward.owner());
    ISvrOracleSteward.AssetOracle memory config =
      ISvrOracleSteward.AssetOracle({asset: AaveV3EthereumAssets.cbBTC_UNDERLYING, svrOracle: address(WBTC_SVR_ORACLE)});
    steward.configureOracle(config);

    (address cachedOracle, address svrOracle) = steward.getOracleConfig(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    address wbtcOracle = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    assertEq(svrOracle, WBTC_SVR_ORACLE);
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
  }

  function test_disableSvrOracle_shouldRevertIfNotConfig() external {
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
