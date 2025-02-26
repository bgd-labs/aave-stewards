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
 * the idea is to slowly enable the feeds one by one, while also maintainging the ability to swap back in extreme situations.
 *
 * --- Security considerations
 *
 * The contract requires the "AssetListing" or "PoolAdmin" role in order to be able to replace oracles.
 * Due to the narrow scope of the contract ifself, only oracles can be replaces, no other role permissions can be exercised.
 *
 * The owner role which will be assigned to the governance short executor can list new svrOracles.
 * The guardian role can enable and disable oracles configured by the governance.
 *
 * While the SvrOracle should report the same price as the current Oracle, currently the Svr is served from a different DON.
 * In practice this means that there are slight deviations on the oracle prices.
 * To ensure proper functionality, before activating a Svr it is ensured that the reported price is within narrow bounds (0.1% deviation).
 *
 * --- Limitations
 *
 * When configuring a svrOracle for an asset, the current oracle is cached.
 * The system will only allow siwthing between the cached and the svrOracle.
 * If the oracle changes e.g. via a governanceProposal, the steward will no longer be able to enable the svrOracle.
 * To resume functionality the svr would need to be reconfigured.
 */
contract SvrOracleSteward is OwnableWithGuardian, ISvrOracleSteward {
  /// @inheritdoc ISvrOracleSteward
  IPoolAddressesProvider public immutable POOL_ADDRESSES_PROVIDER;

  // stores the configured svr oracles
  mapping(address asset => address svrOracle) internal _svrOracles;
  // stores a snapshot of the oracle at configuration time
  mapping(address asset => address cachedOracle) internal _oracleCache;

  constructor(
    IPoolAddressesProvider addressesProvider,
    AssetOracle[] memory initialConfigs,
    address initialOwner,
    address initialGuardian
  ) OwnableWithGuardian(initialOwner, initialGuardian) {
    POOL_ADDRESSES_PROVIDER = addressesProvider;
    for (uint256 i = 0; i < initialConfigs.length; i++) {
      _configureOracle(initialConfigs[i].asset, initialConfigs[i].svrOracle);
    }
  }

  /// @inheritdoc ISvrOracleSteward
  function getOracleConfig(address asset) external view returns (address, address) {
    return (_oracleCache[asset], _svrOracles[asset]);
  }

  /// @inheritdoc ISvrOracleSteward
  function configureOracle(AssetOracle calldata configInput) external onlyOwner {
    _configureOracle(configInput.asset, configInput.svrOracle);
  }

  /// @inheritdoc ISvrOracleSteward
  function enableSvrOracle(address asset) external onlyGuardian {
    address svrOracle = _svrOracles[asset];
    if (svrOracle == address(0)) revert NoSvrOracleConfigured();
    IAaveOracle oracle = IAaveOracle(POOL_ADDRESSES_PROVIDER.getPriceOracle());
    address currentOracle = oracle.getSourceOfAsset(asset);
    if (currentOracle != _oracleCache[asset]) revert UnknownOracle();
    _withinAllowedDeviation(svrOracle, currentOracle);

    address[] memory assets = new address[](1);
    assets[0] = asset;
    address[] memory feeds = new address[](1);
    feeds[0] = svrOracle;
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
    int256 average = (oldPrice + newPrice) / 2;
    // allow deviation of <0.1%
    if (difference * 1e4 > average * 10) revert OracleDeviation(oldPrice, newPrice);
  }

  /**
   * @notice configures a new svrOracle for a specified asset.
   * @param asset The address of the asset
   * @param svrOracle The address of the svrOracle to be used for the asset
   */
  function _configureOracle(address asset, address svrOracle) internal {
    if (asset == address(0) || svrOracle == address(0)) revert ZeroAddress();
    if (AggregatorInterface(svrOracle).decimals() != 8) revert InvalidOracleDecimals();
    IAaveOracle oracle = IAaveOracle(POOL_ADDRESSES_PROVIDER.getPriceOracle());
    address currentOracle = oracle.getSourceOfAsset(asset);
    _oracleCache[asset] = currentOracle;
    _svrOracles[asset] = svrOracle;
    emit SvrOracleConfigChanged(asset, currentOracle, svrOracle);
  }
}
