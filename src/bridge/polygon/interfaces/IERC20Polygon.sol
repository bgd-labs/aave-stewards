// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20Polygon {
  function balanceOf(address account) external view returns (uint256);

  function transfer(address to, uint256 amount) external returns (bool);

  function withdraw(uint256 amount) external payable;
}
