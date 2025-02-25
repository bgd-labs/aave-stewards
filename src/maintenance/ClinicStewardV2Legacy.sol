// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILendingPool} from "aave-address-book/AaveV2.sol";
import {ClinicSteward} from "./ClinicSteward.sol";

/**
 * @title ClinicStewardV2Legacy
 * @author BGD Labs
 * @notice This is an adaption of the ClinicSteward for legacy V2 pools.
 * Check the documentation of ClinicSteward for detailed information.
 */
contract ClinicStewardV2Legacy is ClinicSteward {
  constructor(address pool, address collector, address admin, address cleanupRoleRecipient)
    ClinicSteward(pool, collector, admin, cleanupRoleRecipient)
  {}

  function _getAToken(address asset) internal view virtual override returns (address) {
    return ILendingPool(address(POOL)).getReserveData(asset).aTokenAddress;
  }

  function _getVToken(address asset) internal view virtual override returns (address) {
    return ILendingPool(address(POOL)).getReserveData(asset).variableDebtTokenAddress;
  }
}
