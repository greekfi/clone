# clone

A small Solidity library for deploying minimal-proxy clones with
immutable args appended to the proxy runtime and forwarded to the
implementation's calldata on every `DELEGATECALL`.

- **`ClonesWithImmutableArgs.clone`** — plain `CREATE` deploy.
- **`ClonesWithImmutableArgs.clone2` / `addressOfClone2`** — `CREATE2`
  deploy + deterministic address prediction.

Both paths produce the same proxy runtime, so the same on-implementation
reader works for either (the original wighawag `Clone.sol` is the canonical
reader).

## Origin

Forked from [`wighawag/clones-with-immutable-args`](https://github.com/wighawag/clones-with-immutable-args)
at commit `196f1ec` (master tip, frozen since 2023). Same BSD license. The
runtime bytecode is byte-identical to the upstream — battle-tested in
production at Bunni, Sudoswap, 0xSplits, etc.

## What this fork changes

- **`CREATE` and `CREATE2` paths in one library** sharing a single
  creation-bytecode builder.
- **`uint16(runSize)` truncation bug fixed.** Upstream advertised
  `MAX_DATA_LENGTH = 65533`, but values above 24519 cause silent
  truncation of the runtime-size field in the creation prelude. The new
  cap is the EIP-170-derived `24519 = 24576 − 55 − 2` (max runtime,
  minus proxy logic, minus length suffix).
- **`clone2` takes `salt` as a parameter.** Upstream hardcoded salt to 0,
  meaning a second deploy with the same `impl` + `data` always reverted.
- **`addressOfClone2` takes `deployer` as a parameter.** Upstream
  hardcoded `address(this)`, making prediction-on-behalf impossible.
- **`implementation == address(0)` check.** Catches a silent-failure
  mode where `DELEGATECALL` to the zero address "succeeds" with empty
  return data.
- **`abi.encodePacked` construction** instead of 100 lines of pointer
  arithmetic. Output bytecode is unchanged; readability isn't.
- **`assembly ("memory-safe")`** on the `create` / `create2` blocks.

## Install

```bash
forge install greekfi/clone
```

```solidity
import {ClonesWithImmutableArgs} from "clone/src/ClonesWithImmutableArgs.sol";
```

Add to `remappings.txt`:

```
clone/=lib/clone/
```

## Usage

```solidity
// Plain CREATE
address payable instance = ClonesWithImmutableArgs.clone(
    implementation,
    abi.encodePacked(strike, collateral, expirationDate, isPut)
);

// CREATE2 with caller-namespaced salt to prevent griefing
bytes32 salt = keccak256(abi.encode(msg.sender, userSalt));
address payable det = ClonesWithImmutableArgs.clone2(implementation, salt, data);

// Predict the address without deploying
address predicted = ClonesWithImmutableArgs.addressOfClone2(
    address(this), implementation, salt, data
);
```

The implementation contract reads its appended args via
`calldataload`. Inherit from the bundled `Clone` contract:

```solidity
import {Clone} from "clone/src/Clone.sol";

contract MyImpl is Clone {
    function strike() external pure returns (uint256) { return _getArgUint256(0); }
    function collateral() external pure returns (address) { return _getArgAddress(32); }
}
```

`Clone.sol` is byte-identical to upstream wighawag — it provides
`_getArgUint256` / `_getArgAddress` / `_getArgUint64` / `_getArgUint8`
helpers.

## Limits

- `data.length ≤ 24519` (`MAX_DATA_LENGTH`). Reverts `DataTooLong` above.
- `implementation != address(0)`. Reverts `ZeroImplementation`.
- Proxy runtime size: `55 + data.length + 2` bytes (must fit EIP-170).
- Creation bytecode size: `67 + data.length` bytes (must fit EIP-3860).

## Footguns the library can't fix

- **`clone2` salt namespacing.** If your salt-space is user-supplied,
  hash it together with `msg.sender` before passing it in — otherwise
  any caller can front-run a known deterministic deployment.
- **Don't trust `_getArg*` on the implementation template.** When the
  template is called directly (not through a clone), the appended args
  are attacker-controlled via calldata padding. Authenticate based on a
  registry of known clones, not on values read from immutable args.

## Audit status

Not formally audited. The runtime bytecode is identical to upstream
wighawag, which has been live in production at scale for years
(Bunni, Sudoswap, 0xSplits) with no on-chain exploit attributed to
the bytecode itself. The diff vs. upstream is small and reviewable.

## License

BSD-2-Clause, matching upstream.
