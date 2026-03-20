# Aave Arbitrum -> Mainnet ERC20 Bridge Steward

Currently there is no easy way for the Collector on Arbitrum to withdraw funds via bridging to Ethereum mainnet. An upgrade to the Collector to be made to bridge directly, however, with this approach, we can assign a Guardian the role to bridge as is done with other networks such as Polygon and Optimism.

Adapted from the existing [AaveArbEthERC20Bridge](https://arbiscan.io/address/0x0335ffa9af5ce05590d6c9a75b645470e07744a9) (`0x0335ffa9af5ce05590d6c9a75b645470e07744a9`) to include a Steward Role so the AFC (guardian) can bridge funds without requiring an AIP submission each time.

The official Arbitrum documentation can be found [here](https://docs.arbitrum.io/build-decentralized-apps/token-bridging/token-bridge-erc20).

## Security Considerations

Not all ERC20 tokens on Arbitrum are compatible with the standard gateway. Each token uses a specific L2 gateway for bridging. Governance must only allowlist tokens that can be bridged via their respective gateways. Tokens that rely on custom bridges or external protocols must **NOT** be added to the token mapping:

- **Native USDC**: Bridged via Circle's CCTP, not through the standard gateway.
- **wstETH**: Uses a custom bridge maintained by Lido.

## Functions

`function bridge(address token, uint256 amount) external`

Callable on Arbitrum by owner or guardian. Pulls `amount` of `token` from the Arbitrum Collector, then bridges to the Mainnet Collector via the token's configured L2 gateway. The token must have a valid config set via `setTokenMapping`.

`function bridgeNative(uint256 amount) external`

Callable on Arbitrum by owner or guardian. Bridges native ETH to the Mainnet Collector. Pulls WETH from the Collector, unwraps it, and bridges as ETH via the `ArbSys` precompile. WETH must be mapped via `setTokenMapping`.

`function setTokenMapping(address l2Token, address l1Token, address gateway) external`

Callable on Arbitrum by owner only (governance). Sets the L1 token address and L2 gateway corresponding to an L2 token.

**Only tokens that have been mapped can be bridged.** The mapping starts empty; governance must explicitly allow each token.

`function removeTokenMapping(address l2Token) external`

Callable on Arbitrum by owner only (governance). Removes a token mapping, disabling bridging for that token.

`function rescueToken(address token) external`

Callable on Arbitrum by owner or guardian. Rescues ERC20 tokens stuck in the contract back to the Arbitrum Collector.

`function rescueEth() external`

Callable on Arbitrum by owner or guardian. Rescues native ETH stuck in the contract back to the Arbitrum Collector.

`function nonce() external view returns (uint256)`

Returns the current bridge nonce. Each bridge operation increments the nonce.

## Finalizing the Bridge

After calling `bridge()` on Arbitrum, it takes ~7 days for the withdrawal to be available (optimistic rollup). Once available, the withdrawal can be finalized on Mainnet.

A burn proof is generated via the `aave-cli` tool, which can be found [here](https://github.com/TokenLogic-com-au/aave-cli-tools).

The command to generate the proof is:

`yarn start arbitrum-bridge-exit <TX_HASH> <INDEX> <ARBITRUM_BLOCK_OF_TX>`

Where `TX_HASH` is the hash of the bridge transaction on Arbitrum, `INDEX` is the withdrawal index (if there are 3 tokens bridged in the same transaction, the indexes will be 0, 1 and 2), and `ARBITRUM_BLOCK_OF_TX` is the block the bridge transaction happened at.

## Known Gateway Addresses (L2)

| Token  | Gateway                                      |
| ------ | -------------------------------------------- |
| USDC.e | `0x096760F208390250649E3e8763348E783AEF5562` |
| WETH   | `0x6c411aD3E74De3E7Bd422b94A27770f5B86C623B` |
| WBTC   | `0x09e9222E96E7B4AE2a407B98d48e330053351EEe` |
| DAI    | `0x09e9222E96E7B4AE2a407B98d48e330053351EEe` |
| LINK   | `0x09e9222E96E7B4AE2a407B98d48e330053351EEe` |
| ARB    | `0x09e9222E96E7B4AE2a407B98d48e330053351EEe` |

## Transactions

| Token | Bridge | Exit |
| ----- | ------ | ---- |
| TBD   |        |      |

## Deployed Address

Arbitrum: [TBD](https://arbiscan.io/address/TBD)
