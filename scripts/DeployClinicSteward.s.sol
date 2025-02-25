// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ClinicSteward} from "src/maintenance/ClinicSteward.sol";
import {IPool} from "aave-v3-origin/contracts/interfaces/IPool.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";

import {AaveV3Polygon} from "aave-address-book/AaveV3Polygon.sol";
import {GovernanceV3Polygon} from "aave-address-book/GovernanceV3Polygon.sol";

import {AaveV3Avalanche} from "aave-address-book/AaveV3Avalanche.sol";
import {GovernanceV3Avalanche} from "aave-address-book/GovernanceV3Avalanche.sol";

import {AaveV3Optimism} from "aave-address-book/AaveV3Optimism.sol";
import {GovernanceV3Optimism} from "aave-address-book/GovernanceV3Optimism.sol";

import {AaveV3Arbitrum} from "aave-address-book/AaveV3Arbitrum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";

import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";

import {AaveV3BNB} from "aave-address-book/AaveV3BNB.sol";
import {GovernanceV3BNB} from "aave-address-book/GovernanceV3BNB.sol";

import {AaveV3Gnosis} from "aave-address-book/AaveV3Gnosis.sol";
import {GovernanceV3Gnosis} from "aave-address-book/GovernanceV3Gnosis.sol";

import {AaveV3Scroll} from "aave-address-book/AaveV3Scroll.sol";
import {GovernanceV3Scroll} from "aave-address-book/GovernanceV3Scroll.sol";

import {AaveV3Base} from "aave-address-book/AaveV3Base.sol";
import {GovernanceV3Base} from "aave-address-book/GovernanceV3Base.sol";

import {AaveV3Metis} from "aave-address-book/AaveV3Metis.sol";
import {GovernanceV3Metis} from "aave-address-book/GovernanceV3Metis.sol";

import {AaveV3Linea} from "aave-address-book/AaveV3Linea.sol";
import {GovernanceV3Linea} from "aave-address-book/GovernanceV3Linea.sol";

import {AaveV3EthereumLido} from "aave-address-book/AaveV3EthereumLido.sol";
import {AaveV3EthereumEtherFi} from "aave-address-book/AaveV3EthereumEtherFi.sol";

import {AaveV3ZkSync} from "aave-address-book/AaveV3ZkSync.sol";
import {GovernanceV3ZkSync} from "aave-address-book/GovernanceV3ZkSync.sol";

address constant ACI_MULTISIG = 0xac140648435d03f784879cd789130F22Ef588Fcd;

library DeploymentLibrary {
  function _deploy(IPool pool, ICollector collector, address admin) internal {
    Create2Utils.create2Deploy(
      "v1", type(ClinicSteward).creationCode, abi.encode(address(pool), address(collector), admin, ACI_MULTISIG)
    );
  }

  function _deployZk(IPool pool, ICollector collector, address admin) internal {
    // TODO: different addres on zk
    new ClinicSteward{salt: "v1"}(address(pool), address(collector), admin, ACI_MULTISIG);
  }
}

contract Deploy is Script {
  function deploy() internal {
    vm.startBroadcast();
    if (block.chainid == ChainIds.MAINNET) {
      _deploy(AaveV3Ethereum.POOL, AaveV3Ethereum.COLLECTOR, GovernanceV3Mainnet.EXECUTOR_LVL_1);
      _deploy(AaveV3EthereumLido.POOL, AaveV3Ethereum.COLLECTOR, GovernanceV3Mainnet.EXECUTOR_LVL_1);
      _deploy(AaveV3EthereumEtherFi.POOL, AaveV3Ethereum.COLLECTOR, GovernanceV3Mainnet.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.POLYGON) {
      _deploy(AaveV3Polygon.POOL, AaveV3Polygon.COLLECTOR, GovernanceV3Polygon.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.AVALANCHE) {
      _deploy(AaveV3Avalanche.POOL, AaveV3Avalanche.COLLECTOR, GovernanceV3Avalanche.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.OPTIMISM) {
      _deploy(AaveV3Optimism.POOL, AaveV3Optimism.COLLECTOR, GovernanceV3Optimism.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.ARBITRUM) {
      _deploy(AaveV3Arbitrum.POOL, AaveV3Arbitrum.COLLECTOR, GovernanceV3Arbitrum.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.SCROLL) {
      _deploy(AaveV3Scroll.POOL, AaveV3Scroll.COLLECTOR, GovernanceV3Scroll.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.BASE) {
      _deploy(AaveV3Base.POOL, AaveV3Base.COLLECTOR, GovernanceV3Base.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.ZKSYNC) {
      _deployZk(AaveV3ZkSync.POOL, AaveV3ZkSync.COLLECTOR, GovernanceV3ZkSync.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.BNB) {
      _deploy(AaveV3Bnb.POOL, AaveV3Bnb.COLLECTOR, GovernanceV3Bnb.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.GNOSIS) {
      _deploy(AaveV3Gnosis.POOL, AaveV3Gnosis.COLLECTOR, GovernanceV3Gnosis.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.METIS) {
      _deploy(AaveV3Metis.POOL, AaveV3Metis.COLLECTOR, GovernanceV3Metis.EXECUTOR_LVL_1);
    }
    if (block.chainid == ChainIds.LINEA) {
      _deploy(AaveV3Linea.POOL, AaveV3Linea.COLLECTOR, GovernanceV3Linea.EXECUTOR_LVL_1);
    }
  }
}
