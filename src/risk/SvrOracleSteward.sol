// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAaveOracle} from "aave-v3-origin/contracts/interfaces/IAaveOracle.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {ISvrOracleSteward} from "./interfaces/ISvrOracleSteward.sol";

/**
 * @title SvrOracleSteward
 * @author BGD Labs
 * @notice This contract helps with the configuration of SvrOracles.
 * As svrOracles are a rather new development that potentially alters the oracle mechanics on the aave protocol,
 * the idea is to enable the feeds, while also maintainging the ability to swap back in extreme situations.
 *
 * --- Security considerations
 *
 * The contract requires the "AssetListing" or "PoolAdmin" role in order to be able to replace oracles.
 * Due to the narrow scope of the contract itself, only oracles can be replaced, without any extra functionality
 *
 * The owner role which will be assigned to the governance executor lvl1 can enable new svrOracles.
 * The guardian role can revert the configuration to the previous oracle.
 * The guardian will only be able to revert if the currently configured oracle is in fact the svr oracle.
 *
 * While the SvrOracle should report the same price as the current Oracle, currently the Svr is served from a different DON.
 * In practice this means that there are slight deviations on the oracle prices.
 * To ensure proper functionality, before activating a Svr it is ensured that the reported price is within narrow bounds (0.1% deviation).
 */
contract SvrOracleSteward is OwnableWithGuardian, ISvrOracleSteward {
  /// @inheritdoc ISvrOracleSteward
  IPoolAddressesProvider public immutable POOL_ADDRESSES_PROVIDER;

  int256 internal constant BPS_MAX = 100_00;
  // allow deviation of <0.1%
  int256 internal constant MAX_DEVIATION_BPS = 10;

  // stores the configured svr oracles
  mapping(address asset => address svrOracle) internal _svrOracles;
  // stores a snapshot of the oracle at configuration time
  mapping(address asset => address cachedOracle) internal _oracleCache;

  constructor(IPoolAddressesProvider addressesProvider, address initialOwner, address initialGuardian)
    OwnableWithGuardian(initialOwner, initialGuardian)
  {
    POOL_ADDRESSES_PROVIDER = addressesProvider;
  }

  /// @inheritdoc ISvrOracleSteward
  function getOracleConfig(address asset) external view returns (address, address) {
    return (_oracleCache[asset], _svrOracles[asset]);
  }

  /// @inheritdoc ISvrOracleSteward
  function removeOracle(address asset) external onlyOwner {
    _oracleCache[asset] = address(0);
    _svrOracles[asset] = address(0);
    emit SvrOracleConfigChanged(asset, address(0), address(0));
  }

  /// @inheritdoc ISvrOracleSteward
  function enableSvrOracles(AssetOracle[] calldata oracleConfig) external onlyOwner {
    IAaveOracle oracle = IAaveOracle(POOL_ADDRESSES_PROVIDER.getPriceOracle());
    address[] memory assets = new address[](oracleConfig.length);
    address[] memory feeds = new address[](oracleConfig.length);
    for (uint256 i = 0; i < oracleConfig.length; i++) {
      if (AggregatorInterface(oracleConfig[i].svrOracle).decimals() != 8) revert InvalidOracleDecimals();
      if (oracleConfig[i].svrOracle == address(0)) revert ZeroAddress();
      address currentOracle = oracle.getSourceOfAsset(oracleConfig[i].asset);
      _withinAllowedDeviation(currentOracle, oracleConfig[i].svrOracle);
      assets[i] = oracleConfig[i].asset;
      feeds[i] = oracleConfig[i].svrOracle;
      // cache current oracle
      _oracleCache[oracleConfig[i].asset] = currentOracle;
      // cache svr oracle
      _svrOracles[oracleConfig[i].asset] = oracleConfig[i].svrOracle;
      emit SvrOracleConfigChanged(oracleConfig[i].asset, currentOracle, oracleConfig[i].svrOracle);
    }
    oracle.setAssetSources(assets, feeds);
  }

  /// @inheritdoc ISvrOracleSteward
  function disableSvrOracle(address asset) external onlyGuardian {
    address cachedOracle = _oracleCache[asset];
    if (cachedOracle == address(0)) revert NoCachedOracle();

    IAaveOracle oracle = IAaveOracle(POOL_ADDRESSES_PROVIDER.getPriceOracle());
    address currentOracle = oracle.getSourceOfAsset(asset);
    if (currentOracle != _svrOracles[asset]) revert UnknownOracle();

    address[] memory assets = new address[](1);
    assets[0] = asset;
    address[] memory feeds = new address[](1);
    feeds[0] = cachedOracle;
    oracle.setAssetSources(assets, feeds);
  }

  /**
   * @notice While in rare cases the svrOracle might lag behind the vanilla, at least on activation we want to ensure they are in sync.
   * While this does not guarantee proper functionality it provides some additional assurance on activation.
   * @param oldFeed The current feed
   * @param newFeed The svr feed
   */
  function _withinAllowedDeviation(address oldFeed, address newFeed) internal view {
    int256 oldPrice = AggregatorInterface(oldFeed).latestAnswer();
    int256 newPrice = AggregatorInterface(newFeed).latestAnswer();
    int256 difference = oldPrice >= newPrice ? oldPrice - newPrice : newPrice - oldPrice;
    int256 maxDiff = (MAX_DEVIATION_BPS * oldPrice) / BPS_MAX;

    if (difference > maxDiff) revert OracleDeviation(oldPrice, newPrice);
  }
}
