import { CHAIN_POOL_MAP, getOperator } from "./common";
import { IClinicSteward_ABI } from "./abis/IClinicSteward";
import { getContract } from "viem";

CHAIN_POOL_MAP.map(async ({ chain, pool }) => {
  const { walletClient } = getOperator(chain);
  const contract = getContract({
    abi: IClinicSteward_ABI,
    address: pool.CLINIC_STEWARD,
    client: walletClient,
  });
  const budget = await contract.read.availableBudget();
  console.log(chain.name, budget / BigInt(1e8));
});
