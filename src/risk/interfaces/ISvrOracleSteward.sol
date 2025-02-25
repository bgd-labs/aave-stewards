// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";

interface ISvrOracleSteward {
  struct AssetOracle {
    address asset;
    address svrOracle;
  }

  event SvrOracleConfigChanged(address indexed asset, address currentOracle, address svrOracle);

  error OracleDeviation(int256 oldPrice, int256 newPrice);
  error UnknownOracle();
  error NoSvrOracleConfigured();
  error NoCachedOracle();
  error ZeroAddress();
  error InvalidOracleDecimals();

  /**
   * @return The address of the PoolAddressesProvider of the Pool controlled by teh steward.
   */
  function POOL_ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);

  /**
   * @notice Returns the oracle configuration for a given asset.
   * @param asset The asset to fetch the configuration for.
   * @return (cachedOracle, svrOracle)
   */
  function getOracleConfig(address asset) external view returns (address, address);

  /**
   * @notice Updates or adds a svrOracle for a selected asset.
   * @param configInput A configuration input struct containing the asset and svrOracle.
   */
  function configureOracle(AssetOracle calldata configInput) external;
}
