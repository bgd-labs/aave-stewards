// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";

import {IPriceOracleGetter} from "aave-address-book/AaveV3.sol";
import {DataTypes, ILendingPool} from "aave-address-book/AaveV2.sol";

import {ChainlinkEthereum} from "aave-address-book/ChainlinkEthereum.sol";
import {ChainlinkPolygon} from "aave-address-book/ChainlinkPolygon.sol";

import {ClinicStewardBase} from "./ClinicStewardBase.sol";

contract ClinicStewardV2 is ClinicStewardBase {
  /// @param pool The address of the Aave Pool.
  /// @param collector The address of the Aave collector.
  /// @param admin The address of the admin. He will receive the `DEFAULT_ADMIN_ROLE` role.
  /// @param cleanupRoleRecipient The address of the `CLEANUP_ROLE` role recipient.
  /// @param initialBudget The initial available budget, in dollar value (with 8 decimals).
  constructor(address pool, address collector, address admin, address cleanupRoleRecipient, uint256 initialBudget)
    ClinicStewardBase(pool, collector, admin, cleanupRoleRecipient, initialBudget)
  {
    ORACLE = ILendingPool(pool).getAddressesProvider().getPriceOracle();
  }

  function _getReserveAToken(address asset) internal view override returns (address) {
    DataTypes.ReserveData memory reserveData = ILendingPool(address(POOL)).getReserveData(asset);

    return reserveData.aTokenAddress;
  }

  function _getReserveVariableDebtToken(address asset) internal view override returns (address) {
    DataTypes.ReserveData memory reserveData = ILendingPool(address(POOL)).getReserveData(asset);

    return reserveData.variableDebtTokenAddress;
  }

  function _getOraclePrice(address asset) internal view override returns (uint256) {
    uint256 priceFromOracle = IPriceOracleGetter(ORACLE).getAssetPrice(asset);

    if (block.chainid == 1 || block.chainid == 137) {
      // @note In Aave V2 Polygon, Ethereum Core and AMM an oracle has ETH as a base currency
      if (block.chainid == 1) {
        // `ChainlinkEthereum.ETH_USD` has 8 decimals
        return priceFromOracle * uint256(AggregatorInterface(ChainlinkEthereum.ETH_USD).latestAnswer()) / 1e18;
      } else {
        // `ChainlinkPolygon.ETH_USD` has 8 decimals
        return priceFromOracle * uint256(AggregatorInterface(ChainlinkPolygon.ETH_USD).latestAnswer()) / 1e18;
      }
    } else {
      return priceFromOracle;
    }
  }
}
