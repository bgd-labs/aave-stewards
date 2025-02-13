// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAaveOracle} from "aave-v3-origin/contracts/interfaces/IAaveOracle.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";

/**
 * --- Security considerations
 *
 * The contract requires the AssetListing or PoolAdmin role in order to be able to replace oracles.
 * Due to the narrow scope of the contract ifself, only oracles can be replaces, no other role permissions can be exercised.
 *
 * The owner role which will be assigned to the governance short executor can list new svrOracles.
 * The guardian role can enable and disable oracles configured by the governance.
 */
contract SvrOracleSteward is OwnableWithGuardian {
  IPoolAddressesProvider immutable POOL_ADDRESSES_PROVIDER;

  event SvrOracleRegistered(address asset, address svrOracle);

  error OracleDeviation(int256 oldPrice, int256 newPrice);
  error CannotReplaceOracleWithItself();
  error NoSvrOracleConfigured();
  error NoCachedOracle();
  error ZeroAddress();
  error InvalidOracleDecimals();

  mapping(address asset => address svrOracle) internal _svrOracles;
  mapping(address asset => address cachedOracle) internal _oracleCache;

  struct AssetOracle {
    address asset;
    address svrOracle;
  }

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

  /**
   * @notice Updates or adds a svrOracle for a selected asset.
   * @param configInput A configuration input struct containing the asset and svrOracle.
   */
  function configureOracle(AssetOracle calldata configInput) external onlyOwner {
    _configureOracle(configInput.asset, configInput.svrOracle);
  }

  /**
   * @notice Enables a previously configured svrOracle.
   * @param asset Address of the asset for which to enable the svrOracle for.
   */
  function enableSvrOracle(address asset) external onlyGuardian {
    address svrOracle = _svrOracles[asset];
    if (svrOracle == address(0)) revert NoSvrOracleConfigured();
    IAaveOracle oracle = IAaveOracle(POOL_ADDRESSES_PROVIDER.getPriceOracle());
    address currentOracle = oracle.getSourceOfAsset(asset);
    if (svrOracle == currentOracle) revert CannotReplaceOracleWithItself();
    _ensureNoDeviation(svrOracle, currentOracle);

    _oracleCache[asset] = currentOracle;
    address[] memory assets = new address[](1);
    assets[0] = asset;
    address[] memory feeds = new address[](1);
    feeds[0] = svrOracle;
    oracle.setAssetSources(assets, feeds);
  }

  /**
   * @notice Disables a previously configured svrOracle.
   * @param asset Address of the asset for which to enable the svrOracle for.
   */
  function disableSvrOracle(address asset) external onlyGuardian {
    address cachedOracle = _oracleCache[asset];
    if (cachedOracle == address(0)) revert NoCachedOracle();

    IAaveOracle oracle = IAaveOracle(POOL_ADDRESSES_PROVIDER.getPriceOracle());
    address currentOracle = oracle.getSourceOfAsset(asset);
    if (cachedOracle == currentOracle) revert CannotReplaceOracleWithItself();

    _oracleCache[asset] = address(0);
    address[] memory assets = new address[](1);
    assets[0] = asset;
    address[] memory feeds = new address[](1);
    feeds[0] = cachedOracle;
    oracle.setAssetSources(assets, feeds);
  }

  /**
   * @notice While in rare cases the svrOracle might lag behind the vanilla, at least on activation we want to ensure they are in sync.
   * While this does not guarantee proper functionality it provides some additional assurance.
   */
  function _ensureNoDeviation(address oldFeed, address newFeed) internal view {
    int256 oldPrice = AggregatorInterface(oldFeed).latestAnswer();
    int256 newPrice = AggregatorInterface(newFeed).latestAnswer();
    if (oldPrice != newPrice) revert OracleDeviation(oldPrice, newPrice);
  }

  /**
   *
   *
   */
  function _configureOracle(address asset, address svrOracle) internal {
    if (asset == address(0) || svrOracle == address(0)) revert ZeroAddress();
    if (AggregatorInterface(svrOracle).decimals() != 8) revert InvalidOracleDecimals();
    _svrOracles[asset] = svrOracle;
    emit SvrOracleRegistered(asset, svrOracle);
  }
}
