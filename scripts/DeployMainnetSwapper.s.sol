// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";

import {MainnetSwapSteward} from "../src/finance/MainnetSwapSteward.sol";

library DeploymentLibrary {
  function _deployMainnet(
    address initialOwner,
    address initialGuardian,
    address collector,
    address initialMilkman,
    address initialPriceChecker,
    address initialLimitOrderPriceChecker,
    address initialComposableCow,
    address initialHandler,
    address initialRelayer
  ) internal {
    Create2Utils.create2Deploy(
      "v1",
      type(MainnetSwapSteward).creationCode,
      abi.encode(
        initialOwner,
        initialGuardian,
        collector,
        initialMilkman,
        initialPriceChecker,
        initialLimitOrderPriceChecker,
        initialComposableCow,
        initialHandler,
        initialRelayer
      )
    );
  }
}

contract Deploy is Script {
  // https://app.safe.global/home?safe=eth:0x22740deBa78d5a0c24C58C740e3715ec29de1bFa
  // Signers are:
  // Marc (AaveChan) - 0x329c54289Ff5D6B7b7daE13592C6B1EDA1543eD4
  // Matt (TokenLogic) - 0xb647055A9915bF9c8021a684E175A353525b9890
  // Chaos Labs - 0x5d49dBcdd300aECc2C311cFB56593E71c445d60d
  // Val (LlamaRisk) - 0xbA037E4746ff58c55dc8F27a328C428F258DDACb
  address constant FINANCE_STEWARD_SAFE = 0x22740deBa78d5a0c24C58C740e3715ec29de1bFa;

  // https://etherscan.io/address/0x060373D064d0168931dE2AB8DDA7410923d06E88
  address public constant MILKMAN = 0x060373D064d0168931dE2AB8DDA7410923d06E88;

  // https://etherscan.io/address/0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c
  address public constant PRICE_CHECKER = 0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c;

  // https://etherscan.io/address/0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802
  address public constant LIMIT_ORDER_PRICE_CHECKER = 0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802;

  // https://etherscan.io/address/0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74
  address public constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;

  // https://etherscan.io/address/0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5
  address public constant TWAP_HANDLER = 0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5;

  // https://etherscan.io/address/0xC92E8bdf79f0507f65a392b0ab4667716BFE0110
  address public constant COW_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

  function run() external {
    vm.startBroadcast();
    DeploymentLibrary._deployMainnet(
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      FINANCE_STEWARD_SAFE,
      address(AaveV3Ethereum.COLLECTOR),
      MILKMAN,
      PRICE_CHECKER,
      LIMIT_ORDER_PRICE_CHECKER,
      COMPOSABLE_COW,
      TWAP_HANDLER,
      COW_RELAYER
    );
    vm.stopBroadcast();
  }
}
