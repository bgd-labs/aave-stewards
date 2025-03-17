/**
 * This script:
 * 1. fetches bad debt positions via an api.
 * 2. validates that all positions are in fact bad debt.
 * 3. creates batches of transactions
 * 4. simulates the txn & then executes the txn
 */
import {
  createWalletClient,
  Hex,
  http,
  TransactionRequest,
  publicActions,
  Address,
  getContract,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arbitrum } from "viem/chains";
import { getRPCUrl } from "@bgd-labs/rpc-env";
import { AaveV3Arbitrum } from "@bgd-labs/aave-address-book";
import { IPool_ABI } from "@bgd-labs/aave-address-book/abis";
import { IClinicSteward_ABI } from "./abis/IClinicSteward";

const chain = arbitrum;
const pool = AaveV3Arbitrum;
// This is not the chain block gas limit, but a rough number on how much gas the txn should consume
const blockGasLimit = 5_000_000;
// This is a rough estimate on how much txns should be included in one batch
const maxRepaymentsPerTx = Math.floor(blockGasLimit / 80_000);
const rpc = getRPCUrl(chain.id, {
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

const poolContract = getContract({
  abi: IPool_ABI,
  address: pool.POOL,
  client: walletClient,
});

async function repayBatch() {
  const users: {
    user: Address;
    chain_id: number;
    pool: Address;
    reserve: Address;
    scaled_variable_debt: string;
  }[] = await (await fetch("https://api.onaave.com/baddebt/get")).json();
  const filteredUsers = (
    await Promise.all(
      users
        .filter((u) => u.pool === pool.POOL && chain.id === u.chain_id)
        .map(async (user) => {
          const data = await poolContract.read.getUserAccountData([user.user]);
          return { ...user, hf: data[5] };
        }),
    )
  ).filter((x) => {
    if (x.hf > 0) console.log(`api error ${x.user} has no pure bad debt`);
    else return true;
  });
  const aggregatedUsers = filteredUsers.reduce(
    (acc, val) => {
      if (!acc[val.reserve]) acc[val.reserve] = [];
      acc[val.reserve].push(val.user);
      return acc;
    },
    {} as Record<Address, Address[]>,
  );
  for (const reserve of Object.keys(aggregatedUsers)) {
    let repayBatch: Address[] = aggregatedUsers[reserve];
    if (repayBatch.length > maxRepaymentsPerTx) {
      console.log(
        "chunking the repayment in multiple parts, please rerun the script in a few minutes once the db is updated",
      );
      repayBatch = repayBatch.slice(0, maxRepaymentsPerTx);
    }
    const params = [reserve as Hex, aggregatedUsers[reserve], true] as const;
    // slightly overestimate the gas, just to be sure
    const actualGas = BigInt(Math.floor(blockGasLimit * 1.2));
    try {
      const { request } = await walletClient.simulateContract({
        account: account,
        address: pool.CLINIC_STEWARD,
        abi: IClinicSteward_ABI,
        functionName: "batchRepayBadDebt",
        // last parameter determines if aTokens should be used for the repayment
        args: params,
        type: "eip1559",
        gas: actualGas,
      });
      const hash = await walletClient.writeContract({
        ...request,
        gas: actualGas,
      });
      await walletClient.waitForTransactionReceipt({
        confirmations: 5,
        hash,
      });
      console.log("transaction confirmed");
    } catch (e) {
      console.log(`Error simulating ${params}`);
    }
  }
}
repayBatch();
