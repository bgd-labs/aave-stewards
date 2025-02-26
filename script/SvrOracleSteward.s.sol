// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";
import {SvrOracleSteward, ISvrOracleSteward} from "../src/risk/SvrOracleSteward.sol";

library DeploySvrOracleSteward_Lib {
  function _deploy(
    IPoolAddressesProvider provider,
    SvrOracleSteward.AssetOracle[] memory configs,
    address admin,
    address guardian
  ) internal returns (SvrOracleSteward) {
    return new SvrOracleSteward(provider, configs, admin, guardian);
  }

  function _deployMainnet() internal returns (SvrOracleSteward) {
    SvrOracleSteward.AssetOracle[] memory configs = new ISvrOracleSteward.AssetOracle[](1);
    configs[0] = ISvrOracleSteward.AssetOracle({
      asset: AaveV3EthereumAssets.cbBTC_UNDERLYING,
      svrOracle: 0x77E55306eeDb1F94a4DcFbAa6628ef87586BC651
    });
    return _deploy(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER, configs, GovernanceV3Ethereum.EXECUTOR_LVL_1, address(1));
  }
}
