import { Address, Chain, encodeFunctionData, getContract, Hex } from "viem";
import {
  blockGasLimit,
  botAddress,
  CHAIN_POOL_MAP,
  getOperator,
} from "./common";
import { IPool_ABI } from "@bgd-labs/aave-address-book/abis";
import { IClinicSteward_ABI } from "./abis/IClinicSteward";
import { ChainId } from "@bgd-labs/rpc-env";

const maxLiquidationsPerTx = Math.floor((blockGasLimit - 500_000) / 300_000);
function getGasLimit(txns: number) {
  return BigInt(600_000 + txns * 350_000);
}
for (const { chain, pool, txType } of CHAIN_POOL_MAP) {
  const { walletClient, account } = getOperator(chain);

  const poolContract = getContract({
    abi: IPool_ABI,
    address: pool.POOL,
    client: walletClient,
  });

  async function liquidateBatch() {
    const users: {
      hfCount: number;
      hfWithPositions: [
        {
          chainId: number;
          user: Address;
          pool: Address;
          positions: {
            reserve: Address;
            scaledVariableDebt: string | null;
            usingAsCollateral: boolean;
            scaledATokenBalance: string | null;
          }[];
        },
      ];
    } = await (
      await fetch(
        `https://api.onaave.com/healthFactor/get?chainId=${chain.id}&pool=${pool.POOL}&page=1&pageSize=10000`,
      )
    ).json();
    const aggregatedUsers = users.hfWithPositions.reduce(
      (acc, value) => {
        const debt = value.positions.find(
          (p) => p.scaledVariableDebt && p.scaledVariableDebt !== "0",
        );
        const collateral = value.positions.find(
          (p) =>
            p.usingAsCollateral &&
            p.scaledATokenBalance &&
            p.scaledATokenBalance !== "0",
        );
        if (!debt || !collateral) return acc;
        if (!acc[debt.reserve]) acc[debt.reserve] = {};
        if (!acc[debt.reserve][collateral.reserve])
          acc[debt.reserve][collateral.reserve] = [];
        acc[debt.reserve][collateral.reserve].push(value.user);
        return acc;
      },
      {} as Record<Address, Record<Address, Address[]>>,
    );
    for (const debt of Object.keys(aggregatedUsers)) {
      for (const collateral of Object.keys(aggregatedUsers[debt])) {
        let liquidateBatch: Address[] = (
          await Promise.all(
            aggregatedUsers[debt][collateral].map(async (user) => {
              const data = await poolContract.read.getUserAccountData([user]);
              // debt or collateral to small
              if (data[0] == 0n || data[1] == 0n) return;
              // healthy
              if (data[5] > BigInt(1e18)) return;
              return user;
            }),
          )
        ).filter((u) => u);
        if (liquidateBatch.length) {
          if (liquidateBatch.length > maxLiquidationsPerTx) {
            console.log(
              "chunking the repayment in multiple parts, please rerun the script in a few minutes once the db is updated",
            );
            liquidateBatch = liquidateBatch.slice(0, maxLiquidationsPerTx);
          }
          console.log(
            `liquidating ${aggregatedUsers[debt][collateral].length} users with debt ${debt} and collateral ${collateral}`,
          );
          const params = [
            debt as Address,
            collateral as Address,
            liquidateBatch,
            true,
          ] as const;
          // slightly overestimate the gas, just to be sure
          const actualGas = getGasLimit(liquidateBatch.length);
          try {
            const { request } = await walletClient.simulateContract({
              account: botAddress,
              address: pool.CLINIC_STEWARD,
              abi: IClinicSteward_ABI,
              functionName: "batchLiquidate",
              // last parameter determines if aTokens should be used for the repayment
              args: params,
              type: txType,
              gas: actualGas,
            });
            console.log("simulation succeeded");
            try {
              if ((chain as Chain).id === ChainId.mainnet) {
                console.log("mainnet private tx not yet implemented, skipping");
                await walletClient.sendPrivateTransaction({
                  from: botAddress,
                  to: pool.CLINIC_STEWARD,
                  data: encodeFunctionData({
                    abi: IClinicSteward_ABI,
                    functionName: "batchLiquidate",
                    args: params,
                  }),
                  type: txType,
                  gas: actualGas,
                });
              } else {
                console.log("trying to execute liquidation");
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
              }
            } catch (e) {
              console.log(e);
            }
          } catch (e) {
            console.log(`Error simulating ${params}`);
          }
        }
      }
    }
  }
  await liquidateBatch();
}
