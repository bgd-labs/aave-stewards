// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IL2Gateway
/// @notice Interface for the Arbitrum L2 Gateway
interface IL2Gateway {
    /// @notice Initiates a token withdrawal from L2 to L1
    /// @param l1Token Address of the L1 token
    /// @param to Recipient address on L1
    /// @param amount Amount of tokens to bridge
    /// @param data Additional data for the bridge message
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        bytes calldata data
    ) external payable returns (bytes memory);
}
