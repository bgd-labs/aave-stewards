// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IArbEthERC20BridgeSteward
/// @notice Defines the behaviour of the ArbEthERC20BridgeSteward.
///         Adapted from IAaveArbEthERC20Bridge to include Steward Role.
interface IArbEthERC20BridgeSteward {
    /// @dev Function cannot be called on this network
    error InvalidChain();

    /// @dev Provided address cannot be the zero-address
    error InvalidZeroAddress();

    /// @dev Token has not been approved for bridging
    error TokenNotAllowed();

    /// @dev Amount must be greater than zero
    error InvalidZeroAmount();

    struct TokenConfig {
        address l1Token;
        address gateway;
    }

    /// @notice Emitted when bridging an ERC20 token from Arbitrum to Mainnet
    /// @param token Address of the Arbitrum token
    /// @param l1token Address of the equivalent Mainnet token
    /// @param amount Amount of tokens bridged
    /// @param to Address receiving token on Mainnet
    /// @param nonce Nonce of the bridge transaction
    event Bridge(
        address indexed token,
        address indexed l1token,
        uint256 amount,
        address indexed to,
        uint256 nonce
    );

    /// @notice Emitted when bridging native ETH from Arbitrum to Mainnet
    /// @param amount Amount of ETH bridged
    /// @param to Address receiving ETH on Mainnet
    /// @param nonce Nonce of the bridge transaction
    event BridgeNative(uint256 amount, address indexed to, uint256 nonce);

    /// @notice Emitted when a token mapping is updated
    /// @param l2Token Address of the token on Arbitrum
    /// @param l1Token Address of the corresponding token on Mainnet
    /// @param gateway Address of the L2 gateway used for bridging
    event TokenMappingUpdated(
        address indexed l2Token,
        address l1Token,
        address gateway
    );

    /// @notice Bridges ERC20 token from Arbitrum Collector to Mainnet Collector.
    ///         The token must have a valid config set via `setTokenMapping`.
    /// @param token The ERC20 address on Arbitrum
    /// @param amount The amount of ERC20 token to bridge
    function bridge(address token, uint256 amount) external;

    /// @notice Bridges native ETH from Arbitrum Collector to Mainnet Collector.
    ///         Pulls WETH from the Collector, unwraps it, and bridges as ETH via ArbSys.
    ///         WETH must be mapped via `setTokenMapping`.
    /// @param amount Amount of ETH to bridge
    function bridgeNative(uint256 amount) external;

    /// @notice Sets a token mapping for bridging.
    /// @dev Only callable on Arbitrum.
    /// @param l2Token Address of the token on Arbitrum
    /// @param l1Token Address of the corresponding token on Mainnet
    /// @param gateway Address of the L2 gateway for this token
    function setTokenMapping(
        address l2Token,
        address l1Token,
        address gateway
    ) external;

    /// @notice Removes a token mapping, disabling bridging for that token.
    /// @dev Only callable on Arbitrum.
    /// @param l2Token Address of the token on Arbitrum
    function removeTokenMapping(address l2Token) external;

    /// @notice Rescues the specified token back to the Collector
    /// @param token The address of the ERC20 token to rescue
    function rescueToken(address token) external;

    /// @notice Rescues ETH from the contract back to the Collector
    function rescueEth() external;

    /// @notice Returns the ArbSys precompile address
    function ARB_SYS() external view returns (address);

    /// @notice Returns instance of Aave V3 Collector
    function COLLECTOR() external view returns (address);

    /// @notice Returns the Aave Collector on Mainnet
    function MAINNET_COLLECTOR() external view returns (address);

    /// @notice Returns the token config for an L2 token
    /// @param l2Token Address of the token on Arbitrum
    /// @return l1Token Address of the corresponding token on Mainnet
    /// @return gateway Address of the L2 gateway for this token
    function tokenConfigs(
        address l2Token
    ) external view returns (address l1Token, address gateway);

    /// @notice Returns the current nonce
    function nonce() external view returns (uint256);
}
