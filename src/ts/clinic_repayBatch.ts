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

// This is a rough estimate on how much txns should be included in one batch
const maxRepaymentsPerTx = Math.floor(blockGasLimit / 80_000);
function getGasLimit(txns: number) {
  return BigInt(400_000 + txns * 120_000);
}

for (const { chain, pool, txType } of CHAIN_POOL_MAP) {
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
            const data = await poolContract.read.getUserAccountData([
              user.user,
            ]);
            const { collateralAssetIds, borrowedAssetIds } =
              decodeUserConfiguration(
                (await poolContract.read.getUserConfiguration([user.user]))
                  .data,
              );
            return {
              ...user,
              collateralBase: data[0],
              hf: data[5],
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
          aggregatedUsers[reserve],
          true,
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
            console.log(e);
          }
        } catch (e) {
          console.log(`Error simulating ${params}`);
        }
      }
    }
  }
  await repayBatch();
}
