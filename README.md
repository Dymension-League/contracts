## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

From a new terminal run:

```shell
avril
```
Then, open a new terminal and type:

```shell
forge script -s="run(bytes32, uint256)" --rpc-url 127.0.0.1:8545 --broadcast --private-key <address-anvil-provides> --no-cache scripts/deploy.s.sol <merkel-root-from-csv> 1000000000000
```

Note that the address, is provided by `avril`.

You can find the contract address by using the following command:

```shell
cat broadcast/deploy.s.sol/31337/run-latest.json | grep -C 1 "CosmoShips"
cat broadcast/deploy.s.sol/31337/run-latest.json | grep -C 1 "GameLeague"

```

Adding those to the frontend's repo `.env` like below, you can use local contracts for local development

```
REACT_APP_LOCAL_COSMOSHIPS_ADDRESS=<address cosmoships>
REACT_APP_LOCAL_GAMELEAGUE_ADDRESS=<address gameleague>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
