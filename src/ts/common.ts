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
  SendTransactionReturnType,
  Address,
  keccak256,
  toBytes,
  toHex,
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
import { getBlockNumber } from "viem/actions";

export const CHAIN_POOL_MAP = [
  {
    chain: linea,
    pool: AaveV3Linea,
    txType: "eip1559",
    gasLimit: 30_000_000,
  },
  {
    chain: arbitrum,
    pool: AaveV3Arbitrum,
    txType: "eip1559",
    gasLimit: 32_000_000,
  },
  {
    chain: avalanche,
    pool: AaveV3Avalanche,
    txType: "eip1559",
    gasLimit: 15_000_000,
  },
  { chain: base, pool: AaveV3Base, txType: "eip1559", gasLimit: 116_000_000 },
  { chain: bsc, pool: AaveV3BNB, txType: "eip1559", gasLimit: 120_000_000 },
  {
    chain: gnosis,
    pool: AaveV3Gnosis,
    txType: "eip1559",
    gasLimit: 17_000_000,
  },
  {
    chain: mainnet,
    pool: AaveV3Ethereum,
    txType: "eip1559",
    gasLimit: 34_000_000,
  },
  {
    chain: mainnet,
    pool: AaveV3EthereumLido,
    txType: "eip1559",
    gasLimit: 34_000_000,
  },
  {
    chain: metis,
    pool: AaveV3Metis,
    txType: "legacy",
    gasLimit: 30_000_000,
  },
  {
    chain: polygon,
    pool: AaveV3Polygon,
    txType: "eip1559",
    gasLimit: 30_000_000,
  },
  {
    chain: optimism,
    pool: AaveV3Optimism,
    txType: "eip1559",
    gasLimit: 60_000_000,
  },
  { chain: zksync, pool: AaveV3ZkSync, txType: "eip1559", gasLimit: 5_000_000 },
  {
    chain: scroll,
    pool: AaveV3Scroll,
    txType: "eip1559",
    gasLimit: 5_000_000,
  },
] as const;

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
    transport: http(rpc, {
      onFetchRequest: async (request, init) => {
        if ((init.body as string).includes("eth_sendPrivateTransaction")) {
          const signature = await account.signMessage({
            message: keccak256(toBytes(init.body?.toString()!)),
          });
          return {
            ...init,
            url: "https://relay.flashbots.net",
            headers: {
              "X-Flashbots-Signature": `${account.address}:${signature}`,
            },
          };
        }
      },
    }),
  })
    .extend((client) => ({
      async sendPrivateTransaction(args: TransactionRequest) {
        const request = await client.prepareTransactionRequest(args);
        const signedTx = await client.signTransaction(request);
        (await client.request({
          method: "eth_sendPrivateTransaction" as any,
          params: [
            {
              tx: signedTx,
              maxBlockNumber: toHex((await getBlockNumber(client)) + 100n),
              preferences: {
                fast: true,
                privacy: {
                  hints: ["hash"],
                  builders: ["flashbots", "beaverbuild.org", "Titan", "rsync"],
                },
              },
            },
          ] as any,
        })) as SendTransactionReturnType;
        return keccak256(signedTx);
      },
    }))
    .extend(publicActions);
  return { walletClient, account };
}

export function getBlockGasLimit(gasLimit: number) {
  return (BigInt(gasLimit) * 40n) / 100n;
}

export async function refreshUsers(data: {
  chainId: number;
  users: Address[];
}) {
  const myHeaders = new Headers();
  myHeaders.append("Content-Type", "application/json");

  await (
    await fetch("https://api.onaave.com/positions/update", {
      method: "POST",
      headers: myHeaders,
      body: JSON.stringify(data),
    })
  ).json();
}
