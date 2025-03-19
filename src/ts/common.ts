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
} from "@bgd-labs/aave-address-book";
import { getRPCUrl } from "@bgd-labs/rpc-env";
import { privateKeyToAccount } from "viem/accounts";

export const CHAIN_POOL_MAP = [
  // { chain: linea, pool: AaveV3Linea },
  // { chain: arbitrum, pool: AaveV3Arbitrum },
  // { chain: avalanche, pool: AaveV3Avalanche },
  // { chain: base, pool: AaveV3Base },
  // { chain: bsc, pool: AaveV3BNB },
  // { chain: gnosis, pool: AaveV3Gnosis },
  // { chain: mainnet, pool: AaveV3Ethereum },
  // { chain: mainnet, pool: AaveV3EthereumLido },
  { chain: metis, pool: AaveV3Metis },
  // { chain: polygon, pool: AaveV3Polygon },
  // { chain: optimism, pool: AaveV3Optimism },
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
