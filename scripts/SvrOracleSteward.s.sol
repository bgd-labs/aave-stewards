// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";
import {SvrOracleSteward, ISvrOracleSteward} from "../src/risk/SvrOracleSteward.sol";

library DeploySvrOracleSteward_Lib {
  function _deploy(IPoolAddressesProvider provider, address admin, address guardian)
    internal
    returns (SvrOracleSteward)
  {
    return new SvrOracleSteward(provider, admin, guardian);
  }

  function _deployMainnet() internal returns (SvrOracleSteward) {
    return _deploy(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER, GovernanceV3Ethereum.EXECUTOR_LVL_1, address(1));
  }
}
