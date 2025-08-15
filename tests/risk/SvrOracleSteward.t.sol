// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
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

  constructor(int256 price, uint256 decimals_) {
    _price = price;
    _decimals = decimals_;
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
  address guardian = MiscEthereum.PROTOCOL_GUARDIAN;
  address owner = AaveV3Ethereum.ACL_ADMIN;

  address public constant SVR_BTC_USD = 0x77E55306eeDb1F94a4DcFbAa6628ef87586BC651;
  address public constant SVR_AAVE_USD = 0xF02C1e2A3B77c1cacC72f72B44f7d0a4c62e4a85;
  address public constant SVR_LINK_USD = 0xC7e9b623ed51F033b32AE7f1282b1AD62C28C183;

  function setUp() external {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 22036758);
    // deployment configures svrOracle for cbBTC
    steward = DeploySvrOracleSteward_Lib._deployMainnet();
    vm.prank(AaveV3Ethereum.ACL_ADMIN);
    AaveV3Ethereum.ACL_MANAGER.addAssetListingAdmin(address(steward));
  }

  function _activateSvr() internal {
    SvrOracleSteward.AssetOracle[] memory configs = new ISvrOracleSteward.AssetOracle[](3);
    configs[0] = ISvrOracleSteward.AssetOracle({asset: AaveV3EthereumAssets.cbBTC_UNDERLYING, svrOracle: SVR_BTC_USD});
    configs[1] = ISvrOracleSteward.AssetOracle({asset: AaveV3EthereumAssets.LINK_UNDERLYING, svrOracle: SVR_LINK_USD});
    configs[2] = ISvrOracleSteward.AssetOracle({asset: AaveV3EthereumAssets.AAVE_UNDERLYING, svrOracle: SVR_AAVE_USD});
    steward.enableSvrOracles(configs);
  }

  function test_activateSvrOracle() public {
    address cbBTCOracleBefore = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    vm.prank(steward.owner());
    _activateSvr();
    address cbBTCOracleAfter = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    assertEq(cbBTCOracleAfter, SVR_BTC_USD);

    (address cachedOracle, address svrOracle) = steward.getOracleConfig(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    assertEq(cachedOracle, cbBTCOracleBefore);
    assertEq(svrOracle, SVR_BTC_USD);
  }

  function test_configureOracle() public {
    vm.prank(steward.owner());
    _activateSvr();

    vm.prank(steward.owner());
    steward.removeOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    (address cachedOracleAfter, address svrOracleAfter) = steward.getOracleConfig(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    assertEq(cachedOracleAfter, address(0));
    assertEq(svrOracleAfter, address(0));
  }

  function test_enableSvrOracles_shouldRevertWithWrongOracle() external {
    OracleMock decimals18 = new OracleMock(9642121755000, 18);
    vm.prank(owner);
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
      address(SVR_BTC_USD),
      abi.encodeWithSelector(AggregatorInterface.latestAnswer.selector),
      abi.encode((currentPrice * 101_01 / 100_00))
    );
    vm.prank(owner);
    vm.expectRevert(
      abi.encodeWithSelector(ISvrOracleSteward.OracleDeviation.selector, currentPrice, (currentPrice * 101_01 / 100_00))
    );
    _activateSvr();

    vm.mockCall(
      address(SVR_BTC_USD),
      abi.encodeWithSelector(AggregatorInterface.latestAnswer.selector),
      abi.encode((currentPrice * 98_99 / 100_00))
    );
    vm.prank(owner);
    vm.expectRevert(
      abi.encodeWithSelector(ISvrOracleSteward.OracleDeviation.selector, currentPrice, (currentPrice * 98_99 / 100_00))
    );
    _activateSvr();
  }

  function test_disableSvrOracle_shouldRevertIfNoConfig() external {
    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(ISvrOracleSteward.NoCachedOracle.selector));
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_disableSvrOracle() external {
    address cbBTCOracleBefore = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    vm.prank(owner);
    _activateSvr();

    vm.prank(guardian);
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    address cbBTCOracle = AaveV3Ethereum.ORACLE.getSourceOfAsset(AaveV3EthereumAssets.cbBTC_UNDERLYING);
    assertEq(cbBTCOracle, cbBTCOracleBefore);
  }

  function test_disableSvrOracle_shouldRevertifOutsideOracleChange() external {
    vm.prank(owner);
    _activateSvr();

    address[] memory assets = new address[](1);
    assets[0] = AaveV3EthereumAssets.cbBTC_UNDERLYING;
    address[] memory feeds = new address[](1);
    feeds[0] = address(42);
    vm.prank(owner);
    AaveV3Ethereum.ORACLE.setAssetSources(assets, feeds);

    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(ISvrOracleSteward.UnknownOracle.selector));
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_ifNoGuardian_activateSvrOracle_shouldRevert() external {
    SvrOracleSteward.AssetOracle[] memory configs = new ISvrOracleSteward.AssetOracle[](1);
    configs[0] = ISvrOracleSteward.AssetOracle({
      asset: AaveV3EthereumAssets.cbBTC_UNDERLYING,
      svrOracle: 0x77E55306eeDb1F94a4DcFbAa6628ef87586BC651
    });
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
    steward.enableSvrOracles(configs);
  }

  function test_ifNoGuardian_disableSvrOracle_shouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianInvalidCaller.selector, address(this)));
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }
}
