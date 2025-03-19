import {
  arbitrum,
  avalanche,
  base,
  bsc,
  gnosis,
  linea,
  mainnet,
  metis,
  optimism,
  polygon,
  zksync,
  scroll,
} from "viem/chains";
import {
  Chain,
  createWalletClient,
  Hex,
  http,
  TransactionRequest,
  publicActions,
} from "viem";
import {
  AaveV3Arbitrum,
  AaveV3Ethereum,
  AaveV3Optimism,
  AaveV3EthereumLido,
  AaveV3BNB,
  AaveV3Base,
  AaveV3Avalanche,
  AaveV3Polygon,
  AaveV3Gnosis,
  AaveV3Metis,
  AaveV3Linea,
  AaveV3ZkSync,
  AaveV3Scroll,
} from "@bgd-labs/aave-address-book";
import { getRPCUrl } from "@bgd-labs/rpc-env";
import { privateKeyToAccount } from "viem/accounts";

export const CHAIN_POOL_MAP = [
  // { chain: linea, pool: AaveV3Linea, txType: "eip1559" }, has no positions
  // { chain: arbitrum, pool: AaveV3Arbitrum, txType: "eip1559" },
  // { chain: avalanche, pool: AaveV3Avalanche, txType: "eip1559" },
  // { chain: base, pool: AaveV3Base, txType: "eip1559" },
  // { chain: bsc, pool: AaveV3BNB, txType: "eip1559" },
  // { chain: gnosis, pool: AaveV3Gnosis , txType: "eip1559"},
  // { chain: mainnet, pool: AaveV3Ethereum, txType: "eip1559" },
  // { chain: mainnet, pool: AaveV3EthereumLido, txType: "eip1559" },
  { chain: metis, pool: AaveV3Metis, txType: "legacy" },
  // { chain: scroll, pool: AaveV3Scroll, txType: "eip1559" },
  // { chain: polygon, pool: AaveV3Polygon, txType: "eip1559" },
  // { chain: optimism, pool: AaveV3Optimism, txType: "eip1559" },
  // { chain: zksync, pool: AaveV3ZkSync, txType: "eip1559" }, has no positions
];
// This is not the chain block gas limit, but a rough number on how much gas the txn should consume
export const blockGasLimit = 6_000_000;

export const botAddress = "0x3Cbded22F878aFC8d39dCD744d3Fe62086B76193";

export function getOperator(chain: Chain) {
  const rpc = getRPCUrl(chain.id as any, {
    alchemyKey: process.env.ALCHEMY_API_KEY!,
    quicknodeToken: process.env.QUICKNODE_TOKEN,
    quicknodeEndpointName: process.env.QUICKNODE_ENDPOINT_NAME,
  });
  const account = privateKeyToAccount(process.env.PRIVATE_KEY! as Hex);
  const walletClient = createWalletClient({
    account,
    chain: chain,
    transport: http(rpc),
  })
    .extend((client) => ({
      async sendPrivateTransaction(args: TransactionRequest) {
        const signed = await client.signTransaction(args);
        return client.request({
          method: "eth_sendPrivateTransaction" as any,
          params: [{ tx: signed, preferences: { fast: true } }] as any,
        });
      },
    }))
    .extend(publicActions);
  return { walletClient, account };
}
