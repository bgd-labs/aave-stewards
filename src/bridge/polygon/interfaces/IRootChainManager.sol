// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRootChainManager {
  function childToRootToken(address token) external view returns (address);

  function exit(bytes calldata inputData) external;
}
