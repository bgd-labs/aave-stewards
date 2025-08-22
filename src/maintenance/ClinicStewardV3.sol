// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPriceOracleGetter, IPool} from "aave-address-book/AaveV3.sol";

import {ClinicStewardBase} from "./ClinicStewardBase.sol";

contract ClinicStewardV3 is ClinicStewardBase {
  /// @param pool The address of the Aave Pool.
  /// @param collector The address of the Aave collector.
  /// @param admin The address of the admin. He will receive the `DEFAULT_ADMIN_ROLE` role.
  /// @param cleanupRoleRecipient The address of the `CLEANUP_ROLE` role recipient.
  /// @param initialBudget The initial available budget, in dollar value (with 8 decimals).
  constructor(address pool, address collector, address admin, address cleanupRoleRecipient, uint256 initialBudget)
    ClinicStewardBase(pool, collector, admin, cleanupRoleRecipient, initialBudget)
  {
    ORACLE = IPool(pool).ADDRESSES_PROVIDER().getPriceOracle();
  }

  function _getReserveAToken(address asset) internal view override returns (address) {
    return POOL.getReserveAToken(asset);
  }

  function _getReserveVariableDebtToken(address asset) internal view override returns (address) {
    return POOL.getReserveVariableDebtToken(asset);
  }

  function _getOraclePrice(address asset) internal view override returns (uint256) {
    return IPriceOracleGetter(ORACLE).getAssetPrice(asset);
  }
}
