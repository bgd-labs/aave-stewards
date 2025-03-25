# Aave <> CoW Swap: MainnetSwapSteward

The MainnetSwapSteward is a smart contract tool developed in order to more easily allow the Aave DAO to swap its tokens.
Up until now, the DAO relied on custom one-use contracts in order to accomplish the swap of one token for another.
Some examples include the BAL <> AAVE swap from 2022, the acquisition of CRV or the acquisition of B-80BAL-20WETH.
All the instances listed above required significant time to develop, test, and review, all while reinventing the
wheel every time for something that should be easy to reuse.

AaveSwapper facilitates swaps of tokens by the DAO without the constant need to review the contracts that do so.

## How It Works

AaveSwapper relies on [Milkman](https://github.com/charlesndalton/milkman), a smart contract that builds on top of
[COW Swap](https://swap.cow.fi/#/faq/protocol), under the hood in order to find the best possible swap execution for
the DAO while protecting funds from MEV exploits and bad slippage.

AaveSwapper is a permissioned smart contract, and it has two potential privileged users: the owner and the guardian.
The owner will be the DAO (however, ownership can be transferred) and the guardian is an address to be chosen by the
DAO to more easily cancel swaps without relying on governance. AaveSwapper can hold funds and swap for other tokens
and keep them in case the DAO chooses so. AaveSwapper can only withdraw tokens to the Collector contract.

### Methods

```
function swap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    address recipient,
    uint256 amount,
    uint256 slippage
  ) external onlyOwnerOrGuardian
```

Swaps `fromToken` to `toToken` in the specified `amount`. The recipient of the `toToken` and sends the acquired funds to the recipient.

Slippage is specified in basis points, for example `100` is 1% slippage. The maximum amount would be `10_000` for 100% slippage.

A note on slippage and CoW Swap:

Slippage not only accounts for the difference in price, but also gas costs incurred for the swap itself. What follows is an example:
A user wants to swap 100 USDC for DAI, the price is about 1-to-1 as they are both stablecoins. The slippage needed for this trade, with
gas prices of 80 gwei could be over 20%, because the transaction itself might cost around $20 dollars, and then the solver needs an incentive
to do the trade so maybe the actual slippage in price is 1% and it trades at 1.005 cost of DAI per USDC.

For a 1,000,000 USDC to DAI swap, this looks very different. Slippage might be around 0.005% where the solver gets $30, plus gas costs of
around $20 dollars, so setting the slippage to 0.5% or 1% to ensure that the swap is picked up is more than enough. The slippage tolerance
does not mean that's what the trade will definitely trade at. CoW Swap finds the best match and then executes at that price. Solvers are
competing at market prices for swaps all the time and they are incentivized to keep prices tight in order to get picked as executors.

Some tokens that are not "standard" ERC-20, such as Aave Interest Bearing Tokens (aTokens) are more gas consuming because the solvers
take into account the costs of wrapping and unwrapping the tokens. AaveSwapper supports aToken to aToken swaps though it is easier to
swap between underlyings.

Depending on the tokens and amounts, slippage will have to vary. A good heuristic is:

Trades of $1,000,000 worth of value or more, around 0.5-1% slippage.
Trades in the six figures, 1-2%.
Trades in the high five-figures, around 3%.
Trades below $15,000 worth of value, 5% slippage.
Trades in the low thousands and less are not really worth swapping because gas costs are a huge proportion of the swap.

The [CoW Swap UI](https://swap.cow.fi/#/1/swap/WETH) can be checked to get an estimate of slippage if executing at that time.

AaveSwapper uses Chainlink oracles for its slippage protection feature. Governance should enforce that all oracles set are
base-USD (ie: V3 oracles and not V2 oracles). AaveSwapper supports base-ETH swaps as well, but both bases have to be the same.
For example USDC/ETH to AAVE/ETH or USDC/USD to AAVE/USD. It does not support USDC/ETH to AAVE/USD swaps and this can lead to
bad trades because of price differences.

```
function limitSwap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    uint256 amountOut
  ) external onlyOwner
```

Limit orders are used when wanting a specific price and not minding leaving an order open. When dealing with DAO swaps, knowing the price 5 days in advance is hard, and maybe relying on oracles is not what the DAO wants, especially dealing with low-liquidty tokens, or big orders that might move the market a lot but not the Oracle reference price.

The `amountOut` here is in the token that is to be RECEIVED. For example, let's say we want to swap 1 wETH for USDC, and the price is $2,000, and we want to get that or better, we would specify the swap in terms of the USDC to be received, in this case, 2,000 USDC. The `amountOut` is measured in the smallest atom of the currency. For tokens with 18 decimals, this would be quotedin wei. For 6 decimals, it would be in 0.000001 increments.

For example, if swapping 1 wETH for DAI, at a price of 2,000, then the `amountOut` needs to be `2000000000000000000000`. If swapping 1 wETH for USDC, the `amountOut` needs to be `2000000000` instead.

Swap fees/gas costs need to be taken into account, especially for smaller orders. For orders in the hundreds of thousands, or millions, this is just going to be a very tiny amount in percentage terms so it won't really matter much, but for a small order, it might. Take for example, the 1 wETH for USDC swap described above. If the limit order is at 2,000 and gas costs are $50, the trade will not settle until price trades at 2,050 because that needs to be taken from the value of the swap. Alternatively, the limit could be made 1,950 because the DAO wants the trade to settle once it hits 2,000 and not have to worry about it.

Limit orders are best suited for stable-to-stable swaps, especially bigger orders as the gas costs are going to be a tiny franction and swaps are likely to occurr rather easily.

```
function cancelSwap(
    address tradeMilkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    address recipient,
    uint256 amount,
    uint256 slippage
) external onlyOwnerOrGuardian
```

This methods cancels a pending trade. Trades should take just a couple of minutes to be picked up and traded, so if something's not right, the user
should move fast to cancel.

Most likely, this function will be called when a swap is not getting executed because slippage might be too tight and there's no match for it.

```

  function getExpectedOut(
    address priceChecker,
    uint256 amount,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle
  ) public view returns (uint256)
```

Get the expected amount of tokens when doing a swap. Informational only.

`function emergencyTokenTransfer(address token, address recipient, uint256 amount) external onlyRescueGuardian`

Withdrawal function for funds to leave AaveCurator. Only the owner can call this function.

```
  function _getPriceCheckerAndData(
    address fromToken,
    address toToken,
    uint256 slippage
) internal view returns (address, bytes memory)
```

Read-only function to get an idea of how many tokens to expect when performing a swap. This helper can be used
to determine the slippage percentage to submit on the swap.

### Potential Extensions

This library includes some abstract payloads to be used by developers to more easily swap and then handle the acquired assets.

`function deposit(address token, uint256 amount) external onlyOwnerOrGuardian`

Deposits funds held on AaveCurator into Aave V2/Aave V3 on behalf of the Collector, depending on the payload used.

### Deployed Addresses

Please check out https://github.com/charlesndalton/milkman for updates on addresses.

Milkman: [`0x060373D064d0168931dE2AB8DDA7410923d06E88`](https://etherscan.io/address/0x060373D064d0168931dE2AB8DDA7410923d06E88)
Chainlink Price Checker: [`0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c`](https://etherscan.io/address/0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c)
Limit Order Price Checker: [`0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802`](https://etherscan.io/address/0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802)
Mainnet: [`0x`]()

### Sample Swaps

#### Limit Swaps

Sample ERC20 to ERC20 swap with 18 decimals: https://explorer.cow.fi/address/0x75a37623F8308eDaA2C21D8B51B91393A9E4033a
https://etherscan.io/tx/0x2186f0cabbbf1930b436783eca69328bfa5a7453c1c7d9a6ed9d7818b3ad9729

Sample ERC20 to ERC20 swap with 6 decimals:
https://explorer.cow.fi/address/0x141764c308997ec2a3AFE2cBAA1307610b126c01
https://etherscan.io/tx/0x135a6218866f050634bf52e699b93a9374c12cba19d2de104aa8296e86d0ce51
