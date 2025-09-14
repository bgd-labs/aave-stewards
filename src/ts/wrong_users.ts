import { IERC20_ABI, IPool_ABI } from "@bgd-labs/aave-address-book/abis";
import { decodeUserConfiguration } from "@bgd-labs/toolbox";
import { readFileSync } from "node:fs";
import path from "node:path";
import { Address, encodeFunctionData, formatUnits, getContract } from "viem";
import { CHAIN_POOL_MAP, getOperator } from "./common";
import { IERC20Detailed_ABI } from "@bgd-labs/aave-address-book/abis";
import { IAaveOracle_ABI } from "@bgd-labs/aave-address-book/abis";
import { ChainId } from "@bgd-labs/rpc-env";

async function fetchWrongUsers() {
  const file = readFileSync(
    path.join(process.cwd(), "src/ts/indexer_aave_user_positions_rows.csv"),
    "utf-8",
  );
  const lines = file.split(/\r\n|\n/);
  lines.shift();
  lines.pop();
  const data = lines.map((line) => {
    const sections = line.split(",");
    return {
      user: sections[0] as Address,
      chain_id: Number(sections[1]),
      pool: sections[2] as Address,
      reserve: sections[3] as Address,
    };
  });
  const aggregatedData = data.reduce(
    (acc, value) => {
      if (!acc[value.chain_id]) acc[value.chain_id] = {};
      if (!acc[value.chain_id][value.pool])
        acc[value.chain_id][value.pool] = {};
      if (!acc[value.chain_id][value.pool][value.reserve])
        acc[value.chain_id][value.pool][value.reserve] = [];
      acc[value.chain_id][value.pool][value.reserve].push(value.user);
      return acc;
    },
    {} as Record<number, Record<Address, Record<Address, Address[]>>>,
  );
  await Promise.all(
    CHAIN_POOL_MAP.map(async ({ chain, pool, txType, gasLimit }) => {
      const chainData = aggregatedData[chain.id]?.[pool.POOL];
      if (!chainData) return;
      const chainId = chain.id;
      const { walletClient, account } = getOperator(chain);
      const poolContract = getContract({
        abi: IPool_ABI,
        address: pool.POOL,
        client: walletClient,
      });
      const reservesList = await poolContract.read.getReservesList();
      const oracle = getContract({
        abi: IAaveOracle_ABI,
        address: pool.ORACLE,
        client: walletClient,
      });
      for (const [reserve, users] of Object.entries(chainData)) {
        const reserveId = reservesList.findIndex((r) => r === reserve);
        const aToken = await poolContract.read.getReserveAToken([
          reserve as Address,
        ]);
        const tokenContract = getContract({
          abi: IERC20Detailed_ABI,
          address: aToken,
          client: walletClient,
        });

        const filteredUsers = (
          await Promise.all(
            users.map(async (user) => {
              const userData = decodeUserConfiguration(
                (await poolContract.read.getUserConfiguration([user])).data,
              );
              if (!userData.collateralAssetIds.includes(reserveId)) {
                // console.log("wrong flags", user, chainId);
                return false;
              }
              const aBalance = await tokenContract.read.balanceOf([user]);
              if (aBalance !== 0n) {
                // console.log("wrong balance", user, chainId);
                return false;
              }
              return user;
            }),
          )
        ).filter((f) => f) as Address[];
        const symbol = await tokenContract.read.symbol();
        if (filteredUsers.length != 0) {
          const collateralPrice = await oracle.read.getAssetPrice([
            reserve as Address,
          ]);
          const asset = Object.values(pool.ASSETS).find(
            (a) => a.UNDERLYING === reserve,
          );
          let amountNeeded = Math.floor(
            2 / (Number(collateralPrice) / 10 ** asset.decimals),
          );
          amountNeeded = amountNeeded == 0 ? 1 : amountNeeded;
          const totalAmount = formatUnits(
            BigInt(amountNeeded * filteredUsers.length),
            asset.decimals,
          );
          console.log(
            `ChainId: ${chainId}, Reserve: ${symbol}, Users: ${filteredUsers.length}, Amount: ${amountNeeded}, Total: ${totalAmount}`,
          );
          const botBalance = await tokenContract.read.balanceOf([
            account.address,
          ]);
          if (botBalance < BigInt(amountNeeded * filteredUsers.length)) {
            console.log(
              `insufficient balance ${symbol} ${filteredUsers.length}`,
            );
            continue;
          }

          for (const user of filteredUsers) {
            const { request, result } = await walletClient.simulateContract({
              account: account,
              address: aToken,
              abi: IERC20Detailed_ABI,
              functionName: "transfer",
              args: [user, BigInt(amountNeeded)],
              type: txType,
            });
            if (chainId === ChainId.mainnet) {
              const hash = await walletClient.sendPrivateTransaction({
                to: aToken,
                data: encodeFunctionData({
                  abi: IERC20_ABI,
                  functionName: "transfer",
                  args: [user, BigInt(amountNeeded)],
                }),
                type: txType,
                gas: 200_000n,
              });
              console.log(hash);
              await walletClient.waitForTransactionReceipt({
                confirmations: 5,
                hash,
              });
            } else {
              try {
                if (request.gas) request.gas = request.gas * 3n;
                console.log(`trying to execute transfer to ${user}`);
                const hash = await walletClient.writeContract({
                  ...request,
                  account,
                  gas: 200_000n,
                });
                await walletClient.waitForTransactionReceipt({
                  confirmations: 2,
                  hash,
                });
                console.log("transaction confirmed");
              } catch (e) {
                console.log(request, e);
              }
            }
          }
        }
      }
    }),
  );
}
