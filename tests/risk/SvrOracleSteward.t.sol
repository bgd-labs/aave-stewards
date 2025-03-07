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
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";

import {ISvrOracleSteward} from "../../src/risk/interfaces/ISvrOracleSteward.sol";
import {SvrOracleSteward, DeploySvrOracleSteward_Lib} from "../../scripts/SvrOracleSteward.s.sol";

contract OracleMock {
  int256 internal _price;
  uint256 internal _decimals;

  constructor(int256 price, uint256 decimals) {
    _price = price;
    _decimals = decimals;
  }

  function latestAnswer() external view returns (int256) {
    return _price;
  }

  function decimals() external view returns (uint256) {
    return _decimals;
  }
}

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

    SvrOracleSteward.AssetOracle[] memory configs = new ISvrOracleSteward.AssetOracle[](1);
    configs[0] = ISvrOracleSteward.AssetOracle({
      asset: AaveV3EthereumAssets.cbBTC_UNDERLYING,
      svrOracle: 0x77E55306eeDb1F94a4DcFbAa6628ef87586BC651
    });
    vm.prank(steward.owner());
    steward.enableSvrOracles(configs);
    address cbBTCOracle = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    assertEq(cbBTCOracle, cbBTC_SVR_ORACLE);
  }

  function test_configureOracle() public {
    vm.prank(steward.owner());
    ISvrOracleSteward.AssetOracle[] memory configs = new ISvrOracleSteward.AssetOracle[](1);
    configs[0] =
      ISvrOracleSteward.AssetOracle({asset: AaveV3EthereumAssets.WBTC_UNDERLYING, svrOracle: address(cbBTC_SVR_ORACLE)});
    steward.enableSvrOracles(configs);

    (address cachedOracle, address svrOracle) = steward.getOracleConfig(AaveV3EthereumAssets.WBTC_UNDERLYING);
    address wbtcOracle = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.WBTC_UNDERLYING);
    assertEq(svrOracle, cbBTC_SVR_ORACLE);
    assertEq(wbtcOracle, cachedOracle);

    vm.prank(steward.owner());
    steward.removeOracle(AaveV3EthereumAssets.WBTC_UNDERLYING);
    (address cachedOracleAfter, address svrOracleAfter) = steward.getOracleConfig(AaveV3EthereumAssets.WBTC_UNDERLYING);
    assertEq(cachedOracleAfter, address(0));
    assertEq(svrOracleAfter, address(0));
    address cbBTCOracle = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.WBTC_UNDERLYING);
    assertEq(cbBTCOracle, cbBTC_SVR_ORACLE);
  }

  function test_configureOracle_shouldRevertWithWrongOracle() external {
    OracleMock decimals18 = new OracleMock(1, 18);
    vm.prank(steward.owner());
    ISvrOracleSteward.AssetOracle[] memory configs = new ISvrOracleSteward.AssetOracle[](1);
    configs[0] =
      ISvrOracleSteward.AssetOracle({asset: AaveV3EthereumAssets.cbBTC_UNDERLYING, svrOracle: address(decimals18)});
    vm.expectRevert(abi.encodeWithSelector(ISvrOracleSteward.InvalidOracleDecimals.selector));
    steward.enableSvrOracles(configs);
  }

  function test_activateSvroracle_shouldRevertIfDeviationExceeded() external {
    address cbBTCOracleBefore = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    int256 currentPrice = AggregatorInterface(cbBTCOracleBefore).latestAnswer();
    vm.mockCall(
      address(cbBTC_SVR_ORACLE),
      abi.encodeWithSelector(AggregatorInterface.latestAnswer.selector),
      abi.encode((currentPrice * 100_11 / 100_00))
    );
    vm.prank(guardian);
    vm.expectRevert(
      abi.encodeWithSelector(ISvrOracleSteward.OracleDeviation.selector, currentPrice, (currentPrice * 100_11 / 100_00))
    );
    steward.enableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);

    vm.mockCall(
      address(cbBTC_SVR_ORACLE),
      abi.encodeWithSelector(AggregatorInterface.latestAnswer.selector),
      abi.encode((currentPrice * 99_89 / 100_00))
    );
    vm.prank(guardian);
    vm.expectRevert(
      abi.encodeWithSelector(ISvrOracleSteward.OracleDeviation.selector, currentPrice, (currentPrice * 99_89 / 100_00))
    );
    steward.enableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
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
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this)));
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
