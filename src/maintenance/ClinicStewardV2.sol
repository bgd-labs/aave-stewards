// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPriceOracleGetter} from "aave-address-book/AaveV3.sol";

import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Polygon, AaveV3PolygonAssets} from "aave-address-book/AaveV3Polygon.sol";
import {DataTypes, ILendingPool} from "aave-address-book/AaveV2.sol";

import {ClinicStewardBase} from "./ClinicStewardBase.sol";

contract ClinicStewardV2 is ClinicStewardBase {
  /// @param pool The address of the Aave Pool.
  /// @param oracle The address of the Aave Oracle.
  /// @param collector The address of the Aave collector.
  /// @param admin The address of the admin. He will receive the `DEFAULT_ADMIN_ROLE` role.
  /// @param cleanupRoleRecipient The address of the `CLEANUP_ROLE` role recipient.
  /// @param initialBudget The initial available budget, in dollar value (with 8 decimals).
  constructor(
    address pool,
    address oracle,
    address collector,
    address admin,
    address cleanupRoleRecipient,
    uint256 initialBudget
  ) ClinicStewardBase(pool, oracle, collector, admin, cleanupRoleRecipient, initialBudget) {}

  function _getReserveAToken(address asset) internal view override returns (address) {
    DataTypes.ReserveData memory reserveData = ILendingPool(address(POOL)).getReserveData(asset);

    return reserveData.aTokenAddress;
  }

  function _getReserveVariableDebtToken(address asset) internal view override returns (address) {
    DataTypes.ReserveData memory reserveData = ILendingPool(address(POOL)).getReserveData(asset);

    return reserveData.variableDebtTokenAddress;
  }

  function _getOraclePrice(address asset) internal view override returns (uint256) {
    if (block.chainid == 1 || block.chainid == 137) {
      // @note In Aave V2 Polygon, Ethereum Core and AMM an oracle has ETH as a base currency
      uint256 ethPrice = IPriceOracleGetter(ORACLE).getAssetPrice(asset);

      if (block.chainid == 1) {
        return ethPrice * IPriceOracleGetter(AaveV3Ethereum.ORACLE).getAssetPrice(AaveV3EthereumAssets.WETH_UNDERLYING)
          / 1e18;
      } else {
        return
          ethPrice * IPriceOracleGetter(AaveV3Polygon.ORACLE).getAssetPrice(AaveV3PolygonAssets.WETH_UNDERLYING) / 1e18;
      }
    } else {
      return IPriceOracleGetter(ORACLE).getAssetPrice(asset);
    }
  }
}
