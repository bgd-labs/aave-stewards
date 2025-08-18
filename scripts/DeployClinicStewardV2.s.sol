// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ClinicStewardV2} from "src/maintenance/ClinicStewardV2.sol";
import {ILendingPool, IAaveOracle} from "aave-address-book/AaveV2.sol";
import {ICollector} from "aave-address-book/AaveV3.sol";
import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";

import {AaveV2Polygon} from "aave-address-book/AaveV2Polygon.sol";
import {GovernanceV3Polygon} from "aave-address-book/GovernanceV3Polygon.sol";

import {AaveV2Avalanche} from "aave-address-book/AaveV2Avalanche.sol";
import {GovernanceV3Avalanche} from "aave-address-book/GovernanceV3Avalanche.sol";

import {AaveV2Ethereum} from "aave-address-book/AaveV2Ethereum.sol";
import {AaveV2EthereumAMM} from "aave-address-book/AaveV2EthereumAMM.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";

address constant MULTISIG = 0xdeadD8aB03075b7FBA81864202a2f59EE25B312b;

library DeploymentLibrary {
  function _deploy(ILendingPool pool, IAaveOracle oracle, ICollector collector, address admin, uint256 budget) internal {
    Create2Utils.create2Deploy(
      "v1",
      type(ClinicStewardV2).creationCode,
      abi.encode(address(pool), oracle, address(collector), admin, MULTISIG, budget)
    );
  }
}

contract Deploy is Script {
  function run() external {
    vm.startBroadcast();
    if (block.chainid == ChainIds.MAINNET) {
      DeploymentLibrary._deploy(
        AaveV2Ethereum.POOL,
        AaveV2Ethereum.ORACLE,
        AaveV2Ethereum.COLLECTOR,
        GovernanceV3Ethereum.EXECUTOR_LVL_1,
        30_000e8
      );
      DeploymentLibrary._deploy(
        AaveV2EthereumAMM.POOL,
        AaveV2EthereumAMM.ORACLE,
        AaveV2EthereumAMM.COLLECTOR,
        GovernanceV3Ethereum.EXECUTOR_LVL_1,
        5_000e8
      );
    }
    if (block.chainid == ChainIds.POLYGON) {
      DeploymentLibrary._deploy(
        AaveV2Polygon.POOL, AaveV2Polygon.ORACLE, AaveV2Polygon.COLLECTOR, GovernanceV3Polygon.EXECUTOR_LVL_1, 30_000e8
      );
    }
    if (block.chainid == ChainIds.AVALANCHE) {
      DeploymentLibrary._deploy(
        AaveV2Avalanche.POOL,
        AaveV2Avalanche.ORACLE,
        AaveV2Avalanche.COLLECTOR,
        GovernanceV3Avalanche.EXECUTOR_LVL_1,
        350_000e8
      );
    }
  }
}
