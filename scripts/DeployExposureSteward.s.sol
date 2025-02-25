// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

import {AaveV2Ethereum} from "aave-address-book/AaveV2Ethereum.sol";
import {AaveV2EthereumAMM} from "aave-address-book/AaveV2EthereumAMM.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3EthereumLido} from "aave-address-book/AaveV3EthereumLido.sol";
import {AaveV3EthereumEtherFi} from "aave-address-book/AaveV3EthereumEtherFi.sol";
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

import {AaveV3ZkSync} from "aave-address-book/AaveV3ZkSync.sol";
import {GovernanceV3ZkSync} from "aave-address-book/GovernanceV3ZkSync.sol";

import {PoolExposureSteward} from "../src/finance/PoolExposureSteward.sol";

address constant FINANCE_MULTISIG = address(0);

library DeploymentLibrary {
  function _deploy(address admin, ICollector collector, address[] memory poolsV2, address[] memory poolsV3) internal {
    Create2Utils.create2Deploy(
      "v1",
      type(PoolExposureSteward).creationCode,
      abi.encode(admin, FINANCE_MULTISIG, address(collector), poolsV2, poolsV3)
    );
  }

  function _deployZk(address admin, ICollector collector, address[] memory poolsV2, address[] memory poolsV3) internal {
    new PoolExposureSteward{salt: "v1"}(admin, FINANCE_MULTISIG, address(collector), poolsV2, poolsV3);
  }
}

contract Deploy is Script {
  function deploy() internal {
    vm.startBroadcast();
    if (block.chainid == ChainIds.MAINNET) {
      address[] memory poolsV2 = new address[](2);
      poolsV2[0] = address(AaveV2Ethereum.POOL);
      poolsV2[1] = address(AaveV2EthereumAMM.POOL);
      address[] memory poolsV3 = new address[](3);
      poolsV3[0] = address(AaveV3Ethereum.POOL);
      poolsV3[1] = address(AaveV3EthereumLido.POOL);
      poolsV3[2] = address(AaveV3EthereumEtherFi.POOL);
      DeploymentLibrary._deploy(GovernanceV3Ethereum.EXECUTOR_LVL_1, AaveV3Ethereum.COLLECTOR, poolsV2, poolsV3);
    }
    if (block.chainid == ChainIds.POLYGON) {
      //...
    }
    if (block.chainid == ChainIds.AVALANCHE) {
      //...
    }
    if (block.chainid == ChainIds.OPTIMISM) {
      //...
    }
    if (block.chainid == ChainIds.ARBITRUM) {
      //...
    }
    if (block.chainid == ChainIds.SCROLL) {
      //...
    }
    if (block.chainid == ChainIds.BASE) {
      //...
    }
    if (block.chainid == ChainIds.ZKSYNC) {
      //...
    }
    if (block.chainid == ChainIds.BNB) {
      //...
    }
    if (block.chainid == ChainIds.GNOSIS) {
      //...
    }
    if (block.chainid == ChainIds.METIS) {
      //...
    }
    if (block.chainid == ChainIds.LINEA) {
      //...
    }
  }
}
