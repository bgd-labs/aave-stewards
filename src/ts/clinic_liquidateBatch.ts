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
import { AaveV3Ethereum } from "@bgd-labs/aave-address-book";

const base = 500_000;
const maxLiquidationsPerTx = Math.floor((blockGasLimit - base) / 210_000);
function getGasLimit(txns: number) {
  return BigInt((base + txns * 210_000) * 1.2);
}
for (const { chain, pool, txType } of CHAIN_POOL_MAP) {
  console.log(`######### Starting on ${chain.name} #########`);
  const { walletClient, account } = getOperator(chain);
  const prices: {
    timestamp: number;
    tokenPrices: {
      chainId: number;
      token: string;
      latestAnswer: string;
      decimals: number;
    }[];
  } = await (
    await fetch("https://api.onaave.com/v4/markets/hot?timestamp=0")
  ).json();

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
        const debt = value.positions.find((p) => {
          if (!p.scaledVariableDebt) return false;
          if (p.scaledVariableDebt === "0") return false;
          const debtPrice = prices.tokenPrices.find(
            (t) => t.token === p.reserve,
          )!;
          const asset = Object.values(pool.ASSETS).find(
            (a) => a.UNDERLYING === p.reserve,
          );
          const value =
            (BigInt(debtPrice.latestAnswer) * BigInt(p.scaledVariableDebt)) /
            1n ** BigInt(asset.decimals);
          if (value == 0n) return false;
          return true;
        });
        const collateral = value.positions.find((p) => {
          if (!p.usingAsCollateral) return false;
          if (!p.scaledATokenBalance) return false;
          if (p.scaledATokenBalance === "0") return false;
          const collateralPrice = prices.tokenPrices.find(
            (t) => t.token === p.reserve,
          )!;
          const asset = Object.values(pool.ASSETS).find(
            (a) => a.UNDERLYING === p.reserve,
          );
          const value =
            (BigInt(collateralPrice.latestAnswer) *
              BigInt(p.scaledATokenBalance)) /
            1n ** BigInt(asset.decimals);
          if (value == 0n) return false;
          return true;
        });
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

        async function liquidate(batch: Address[]) {
          console.log(
            `liquidating ${batch.length} users with debt ${debt} and collateral ${collateral}`,
          );
          const params = [
            debt as Address,
            collateral as Address,
            batch,
            debt === AaveV3Ethereum.ASSETS.GHO.UNDERLYING ? false : true,
          ] as const;
          // slightly overestimate the gas, just to be sure
          const actualGas = getGasLimit(batch.length);
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
        if (liquidateBatch.length) {
          if (liquidateBatch.length > maxLiquidationsPerTx) {
            while (liquidateBatch.length != 0) {
              await liquidate(liquidateBatch.splice(0, maxLiquidationsPerTx));
            }
          } else {
            await liquidate(liquidateBatch);
          }
        }
      }
    }
  }
  await liquidateBatch();
}
