// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";
import {SvrOracleSteward, ISvrOracleSteward} from "../src/risk/SvrOracleSteward.sol";

library DeploySvrOracleSteward_Lib {
  function _deploy(IPoolAddressesProvider provider, address admin, address guardian)
    internal
    returns (SvrOracleSteward)
  {
    return SvrOracleSteward(
      Create2Utils.create2Deploy("v1", type(SvrOracleSteward).creationCode, abi.encode(provider, admin, guardian))
    );
  }

  function _deployMainnet() internal returns (SvrOracleSteward) {
    return _deploy(
      AaveV3Ethereum.POOL_ADDRESSES_PROVIDER, GovernanceV3Ethereum.EXECUTOR_LVL_1, MiscEthereum.PROTOCOL_GUARDIAN
    );
  }
}

contract Deploy is Script {
  function run() external {
    vm.startBroadcast();
    if (block.chainid == ChainIds.MAINNET) {
      DeploySvrOracleSteward_Lib._deployMainnet();
    }
  }
}
