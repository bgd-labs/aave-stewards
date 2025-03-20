/**
 * This script:
 * 1. fetches bad debt positions via an api.
 * 2. validates that all positions are in fact bad debt.
 * 3. creates batches of transactions
 * 4. simulates the txn & then executes the txn
 */
import { Hex, Address, getContract } from "viem";
import { IPool_ABI } from "@bgd-labs/aave-address-book/abis";
import { IClinicSteward_ABI } from "./abis/IClinicSteward";
import { decodeUserConfiguration } from "@bgd-labs/toolbox";
import {
  blockGasLimit,
  botAddress,
  CHAIN_POOL_MAP,
  getOperator,
} from "./common";
import { ChainId } from "@bgd-labs/rpc-env";
import { AaveV3Ethereum } from "@bgd-labs/aave-address-book";

// This is a rough estimate on how much txns should be included in one batch
const base = 400_000;
const maxRepaymentsPerTx = Math.floor((blockGasLimit - base) / 95_000);
function getGasLimit(txns: number) {
  return BigInt((base + txns * 95_000) * 1.2);
}

for (const { chain, pool, txType } of CHAIN_POOL_MAP) {
  console.log(`######### Starting on ${chain.name} #########`);
  const { account, walletClient } = getOperator(chain);

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
            const { collateralAssetIds, borrowedAssetIds } =
              decodeUserConfiguration(
                (await poolContract.read.getUserConfiguration([user.user]))
                  .data,
              );
            return {
              ...user,
              collateralAssetIds,
              borrowedAssetIds,
            };
          }),
      )
    ).filter((x) => {
      if (x.borrowedAssetIds.length == 0 || x.collateralAssetIds.length != 0) {
        // some inconsistency on the api, so we just ignore these ones
        return false;
      }
      return true;
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
      if (repayBatch.length) {
        if (repayBatch.length > maxRepaymentsPerTx) {
          console.log(
            "chunking the repayment in multiple parts, please rerun the script in a few minutes once the db is updated",
          );
          repayBatch = repayBatch.slice(0, maxRepaymentsPerTx);
        }
        console.log(
          `repaying on behalf of ${repayBatch.length} users on ${chain.name}`,
        );
        const params = [
          reserve as Hex,
          repayBatch,
          chain.id === ChainId.mainnet &&
          reserve === AaveV3Ethereum.ASSETS.GHO.UNDERLYING
            ? false
            : true,
        ] as const;
        // slightly overestimate the gas, just to be sure
        const actualGas = getGasLimit(repayBatch.length);
        try {
          const { request, result } = await walletClient.simulateContract({
            account: botAddress,
            address: pool.CLINIC_STEWARD,
            abi: IClinicSteward_ABI,
            functionName: "batchRepayBadDebt",
            // last parameter determines if aTokens should be used for the repayment
            args: params,
            type: txType,
            gas: actualGas,
          });
          console.log("simulation succeeded");
          try {
            console.log("trying to execute repayment");
            const hash = await walletClient.writeContract({
              ...request,
              account,
              gas: actualGas,
            });
            await walletClient.waitForTransactionReceipt({
              confirmations: 5,
              hash,
            });
            console.log("transaction confirmed");
          } catch (e) {
            console.log(request, e);
          }
        } catch (e) {
          console.log(`Error simulating ${actualGas} ${params}`);
        }
      }
    }
  }
  await repayBatch();
}
