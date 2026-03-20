// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IArbSys
/// @notice Interface for the Arbitrum ArbSys precompile (0x64)
interface IArbSys {
    /// @notice Sends ETH from L2 to L1
    /// @param destination Address to receive the ETH on L1
    /// @return Unique identifier for the L2-to-L1 transaction
    function withdrawEth(
        address destination
    ) external payable returns (uint256);
}
