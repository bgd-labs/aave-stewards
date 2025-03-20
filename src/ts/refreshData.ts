import { Address } from "viem";

async function refresh() {
  const users: {
    user: Address;
    chain_id: number;
    pool: Address;
    reserve: Address;
    scaled_variable_debt: string;
  }[] = await (await fetch("https://api.onaave.com/baddebt/get")).json();

  const payloads = users.reduce(
    (acc, value) => {
      if (!acc[value.chain_id])
        acc[value.chain_id] = { chainId: value.chain_id, users: [] };
      acc[value.chain_id].users.push(value.user);
      return acc;
    },
    {} as Record<number, { chainId: number; users: Address[] }>,
  );
  const myHeaders = new Headers();
  myHeaders.append("Content-Type", "application/json");

  for (const payload of Object.values(payloads)) {
    await (
      await fetch("https://api.onaave.com/positions/update", {
        method: "POST",
        headers: myHeaders,
        body: JSON.stringify(payload),
      })
    ).json();
  }
}

refresh();
