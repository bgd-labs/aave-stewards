// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {EthereumScript, PolygonScript} from "solidity-utils/contracts/utils/ScriptUtils.sol";

import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Polygon} from "aave-address-book/AaveV3Polygon.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {GovernanceV3Polygon} from "aave-address-book/GovernanceV3Polygon.sol";

import {PolEthERC20BridgeSteward} from "src/bridge/polygon/PolEthERC20BridgeSteward.sol";
import {ICreateX} from "./interfaces/ICreateX.sol";

// Financial Service Provider of the DAO acting as guardian (TokenLogic).
address constant GUARDIAN = 0x3765A685a401622C060E5D700D9ad89413363a91;

// CreateX is deployed at this same address on Ethereum, Polygon and most other chains.
// Using a cross-chain-consistent factory is what makes CREATE3 resolve to the same steward
// address on both networks. (The aave-address-book CREATE_3_FACTORY is at a DIFFERENT address
// on Ethereum vs Polygon, so it cannot be used for a cross-chain deterministic deployment.)
ICreateX constant CREATE_X = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

// Entropy / version for the salt. Occupies the 11 bytes after the deployer address and flag byte.
bytes11 constant SALT_ENTROPY = "ERC20Bridge";

library DeploymentLibrary {
  /// @dev Builds a CreateX "msg.sender protected" salt: bytes [0:20] are the broadcasting EOA and
  ///      byte 20 is the redeploy-protection flag set to 0x00. Because the leading bytes match the
  ///      caller, CreateX guards the salt as keccak256(abi.encode(msg.sender, salt)) - it includes
  ///      msg.sender but NOT block.chainid. Consequences:
  ///        - same EOA  -> same address on Ethereum and Polygon (no chain-id mixed in);
  ///        - other EOA -> different guarded salt -> cannot occupy this address (front-run safe).
  ///      Under `vm.startBroadcast`, msg.sender seen by CreateX is the broadcasting account, so the
  ///      deployer is bound automatically without hardcoding it.
  function deploy(address owner, address guardian, address collector) internal returns (address steward) {
    bytes32 salt = bytes32(abi.encodePacked(msg.sender, bytes1(0x00), SALT_ENTROPY));
    steward = CREATE_X.deployCreate3(
      salt, abi.encodePacked(type(PolEthERC20BridgeSteward).creationCode, abi.encode(owner, guardian, collector))
    );
    console2.log("PolEthERC20BridgeSteward deployed at", steward);
  }
}

// make deploy-ledger contract=scripts/DeployPolEthBridgeSteward.s.sol:DeployEthereum chain=mainnet
contract DeployEthereum is EthereumScript {
  function run() external broadcast {
    DeploymentLibrary.deploy(
      GovernanceV3Ethereum.EXECUTOR_LVL_1, // owner
      GUARDIAN,
      address(AaveV3Ethereum.COLLECTOR)
    );
  }
}

// make deploy-ledger contract=scripts/DeployPolEthBridgeSteward.s.sol:DeployPolygon chain=polygon
contract DeployPolygon is PolygonScript {
  function run() external broadcast {
    DeploymentLibrary.deploy(
      GovernanceV3Polygon.EXECUTOR_LVL_1, // owner
      GUARDIAN,
      address(AaveV3Polygon.COLLECTOR)
    );
  }
}
