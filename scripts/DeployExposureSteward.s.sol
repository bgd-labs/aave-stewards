// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "aave-v3-origin/contracts/interfaces/IPool.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";

import {AaveV2Polygon} from "aave-address-book/AaveV2Polygon.sol";
import {AaveV3Polygon} from "aave-address-book/AaveV3Polygon.sol";
import {GovernanceV3Polygon} from "aave-address-book/GovernanceV3Polygon.sol";

import {AaveV2Avalanche} from "aave-address-book/AaveV2Avalanche.sol";
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

import {AaveV3Sonic} from "aave-address-book/AaveV3Sonic.sol";
import {GovernanceV3Sonic} from "aave-address-book/GovernanceV3Sonic.sol";

import {AaveV3Linea} from "aave-address-book/AaveV3Linea.sol";
import {GovernanceV3Linea} from "aave-address-book/GovernanceV3Linea.sol";

import {PoolExposureSteward} from "../src/finance/PoolExposureSteward.sol";

// https://app.safe.global/home?safe=eth:0x22740deBa78d5a0c24C58C740e3715ec29de1bFa
// Signers are:
// Marc (AaveChan) - 0x329c54289Ff5D6B7b7daE13592C6B1EDA1543eD4
// Matt (TokenLogic) - 0xb647055A9915bF9c8021a684E175A353525b9890
// Chaos Labs - 0x5d49dBcdd300aECc2C311cFB56593E71c445d60d
// Val (LlamaRisk) - 0xbA037E4746ff58c55dc8F27a328C428F258DDACb
address constant FINANCE_STEWARD_SAFE = 0x22740deBa78d5a0c24C58C740e3715ec29de1bFa;

library DeploymentLibrary {
    function _deploy(
        address admin,
        ICollector collector,
        address[] memory poolsV2,
        address[] memory poolsV3
    ) internal {
        Create2Utils.create2Deploy(
            "v1",
            type(PoolExposureSteward).creationCode,
            abi.encode(
                admin,
                FINANCE_STEWARD_SAFE,
                address(collector),
                poolsV2,
                poolsV3
            )
        );
    }
}

contract Deploy is Script {
    function deploy() internal {
        vm.startBroadcast();
        if (ChainIds.MAINNET == block.chainid) {
            address[] memory poolsV2 = new address[](2);
            poolsV2[0] = address(AaveV2Ethereum.POOL);
            poolsV2[1] = address(AaveV2EthereumAMM.POOL);
            address[] memory poolsV3 = new address[](3);
            poolsV3[0] = address(AaveV3Ethereum.POOL);
            poolsV3[1] = address(AaveV3EthereumLido.POOL);
            poolsV3[2] = address(AaveV3EthereumEtherFi.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Ethereum.EXECUTOR_LVL_1,
                AaveV3Ethereum.COLLECTOR,
                poolsV2,
                poolsV3
            );
        }

        if (ChainIds.POLYGON == block.chainid) {
            address[] memory poolsV2 = new address[](1);
            poolsV2[0] = address(AaveV2Polygon.POOL);
            address[] memory poolsV3 = new address[](1);
            poolsV3[0] = address(AaveV3Polygon.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Polygon.EXECUTOR_LVL_1,
                AaveV3Polygon.COLLECTOR,
                poolsV2,
                poolsV3
            );
        }

        if (ChainIds.AVALANCHE == block.chainid) {
            address[] memory poolsV2 = new address[](1);
            poolsV2[0] = address(AaveV2Avalanche.POOL);
            address[] memory poolsV3 = new address[](1);
            poolsV3[0] = address(AaveV3Avalanche.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Avalanche.EXECUTOR_LVL_1,
                AaveV3Avalanche.COLLECTOR,
                poolsV2,
                poolsV3
            );
        }

        address[] memory initialPoolsV2 = new address[](0);
        address[] memory initialPoolsV3 = new address[](1);
        if (ChainIds.OPTIMISM == block.chainid) {
            initialPoolsV3[0] = address(AaveV3Optimism.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Optimism.EXECUTOR_LVL_1,
                AaveV3Optimism.COLLECTOR,
                initialPoolsV2,
                initialPoolsV3
            );
        }

        if (ChainIds.ARBITRUM == block.chainid) {
            initialPoolsV3[0] = address(AaveV3Optimism.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Optimism.EXECUTOR_LVL_1,
                AaveV3Optimism.COLLECTOR,
                initialPoolsV2,
                initialPoolsV3
            );
        }

        if (ChainIds.SCROLL == block.chainid) {
            initialPoolsV3[0] = address(AaveV3Scroll.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Scroll.EXECUTOR_LVL_1,
                AaveV3Scroll.COLLECTOR,
                initialPoolsV2,
                initialPoolsV3
            );
        }

        if (ChainIds.BASE == block.chainid) {
            initialPoolsV3[0] = address(AaveV3Base.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Base.EXECUTOR_LVL_1,
                AaveV3Base.COLLECTOR,
                initialPoolsV2,
                initialPoolsV3
            );
        }

        if (ChainIds.BNB == block.chainid) {
            initialPoolsV3[0] = address(AaveV3BNB.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3BNB.EXECUTOR_LVL_1,
                AaveV3BNB.COLLECTOR,
                initialPoolsV2,
                initialPoolsV3
            );
        }

        if (ChainIds.GNOSIS == block.chainid) {
            initialPoolsV3[0] = address(AaveV3Gnosis.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Gnosis.EXECUTOR_LVL_1,
                AaveV3Gnosis.COLLECTOR,
                initialPoolsV2,
                initialPoolsV3
            );
        }

        if (ChainIds.SONIC == block.chainid) {
            initialPoolsV3[0] = address(AaveV3Sonic.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Sonic.EXECUTOR_LVL_1,
                AaveV3Sonic.COLLECTOR,
                initialPoolsV2,
                initialPoolsV3
            );
        }

        if (ChainIds.LINEA == block.chainid) {
            initialPoolsV3[0] = address(AaveV3Linea.POOL);
            DeploymentLibrary._deploy(
                GovernanceV3Linea.EXECUTOR_LVL_1,
                AaveV3Linea.COLLECTOR,
                initialPoolsV2,
                initialPoolsV3
            );
        }
    }
}
