// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";

import {MainnetSwapSteward} from "../src/finance/MainnetSwapSteward.sol";

library DeploymentLibrary {
    // https://app.safe.global/home?safe=eth:0x22740deBa78d5a0c24C58C740e3715ec29de1bFa
    // Signers are:
    // Marc (AaveChan) - 0x329c54289Ff5D6B7b7daE13592C6B1EDA1543eD4
    // Matt (TokenLogic) - 0xb647055A9915bF9c8021a684E175A353525b9890
    // Chaos Labs - 0x5d49dBcdd300aECc2C311cFB56593E71c445d60d
    // Val (LlamaRisk) - 0xbA037E4746ff58c55dc8F27a328C428F258DDACb
    address constant FINANCE_STEWARD_SAFE =
        0x22740deBa78d5a0c24C58C740e3715ec29de1bFa;

    function _deployMainnet(
        address admin,
        ICollector collector,
        address[] memory poolsV2,
        address[] memory poolsV3
    ) internal {
        Create2Utils.create2Deploy(
            "v1",
            type(MainnetSwapSteward).creationCode,
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
    function run() external {
        vm.startBroadcast();
        // if (block.chainid == ChainIds.MAINNET) {
        //     DeploymentLibrary._deployMainnet();
        // }
    }
}
