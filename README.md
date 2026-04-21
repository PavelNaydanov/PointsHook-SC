# PointsHook

A practice Uniswap v4 hook that rewards users with ERC-1155 "points" for buying a token with ETH.

## How it works

`PointsHook` attaches to an ETH-`TOKEN` pool and implements the `afterSwap` callback:

- Triggers only for pools where `currency0 == address(0)` (native ETH).
- Triggers only on `zeroForOne` swaps (ETH → TOKEN, i.e. the user is buying).
- Mints ERC-1155 points equal to **20% of the ETH spent** to the address encoded in `hookData`.
- If `hookData` is empty or decodes to `address(0)`, no points are minted.

The ERC-1155 `id` is derived from the pool id, so each pool issues its own points collection.

## Layout

```
src/PointsHook.sol          // the hook contract
script/DeployHook.s.sol     // deterministic CREATE2 deployment via HookMiner
test/PointsHook.t.sol       // unit tests
```

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- An RPC URL for the target network (Sepolia for the example below)
- An Etherscan API key for verification

## Setup

```bash
forge install
cp .env.example .env
# fill in ETHERSCAN_API_KEY
```

## Build & Test

```bash
forge build
forge test
```

### Deploy

Deploying the hook is a two-step process: first the deployment itself, then a separate Etherscan verification. The reason is explained below.

**1. Deploy the contract**

```bash
forge script script/DeployHook.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --sig "run(address)" "$PoolManager" \
  --interactives 1
```

`--interactives 1` prompts for the deployer's private key interactively (it is not stored in shell history).

**2. Verify the contract**

After the deployment, wait ~20-30 seconds so Etherscan has time to index the bytecode, then run:

```bash
forge verify-contract \
  $HookAddress \
  src/PointsHook.sol:PointsHook \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(address)" $PoolManager) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch
```

#### Why verification has to be run separately

Uniswap v4 requires that the hook address carry the enabled hook flags in its lowest bits (see `getHookPermissions()`). To produce such an address, `HookMiner` is used to brute-force a salt for a CREATE2 deployment through the canonical CREATE2 factory (`0x4e59b44847b379578588920cA78FbF26c0B4956C`).

When the script writes:

```solidity
PointsHook hook = new PointsHook{salt: salt}(poolManager);
```

Foundry routes the deployment through that factory under the hood (an EOA cannot execute the `CREATE2` opcode directly — it is only available from contracts). As a result:

- The transaction receipt has `to = CREATE2_FACTORY`, not the hook address.
- The actual contract creation is an **internal transaction** inside the factory.
- Etherscan indexes internal txs with a delay, so right after `--broadcast` Foundry's request to Etherscan ("is there bytecode at the hook address?") returns empty and verification fails with:

  ```
  Error: Failed to verify contract: Could not detect deployment:
  Unable to locate ContractCode at 0x...
  ```

Running `forge verify-contract` manually 20-30 seconds later works fine, because by then the Etherscan index has caught up.

Alternatively, you can keep `--verify` in a single call but add retries with a delay:

```bash
forge script script/DeployHook.s.sol \
  --rpc-url $RPC_URL \
  --broadcast --verify \
  --sig "run(address)" "$PoolManager" \
  --interactives 1 \
  --retries 10 --delay 15
```

> **Note on the CREATE2 factory.** The factory at `0x4e59...4956C` is deployed at the same address on most EVM networks (via Nick's method — a presigned tx with no chain-id binding). You can check that it exists on a given network with `cast code 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url <URL>` — if it returns `0x`, the factory needs to be deployed first.

## Disclaimer

This is a learning project. The contract has not been audited — do not use it in production.
