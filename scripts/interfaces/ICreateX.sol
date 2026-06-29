// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Minimal interface for the CreateX deterministic-deployment factory.
/// @dev CreateX is deployed at the same address (0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed)
///      on Ethereum, Polygon and most other chains, which is what allows CREATE3 to resolve
///      to the same address across networks. See https://github.com/pcaversaccio/createx
interface ICreateX {
  /// @notice Deploys `initCode` via CREATE3 using a salt that is first run through CreateX's
  ///         `_guard` logic. The resulting address depends only on the CreateX address and the
  ///         guarded salt, so it is independent of `initCode` (constructor args included).
  function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);

  /// @notice Computes the CREATE3 address for an already-guarded salt, using CreateX as deployer.
  function computeCreate3Address(bytes32 guardedSalt) external view returns (address computedAddress);
}
