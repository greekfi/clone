// SPDX-License-Identifier: BSD
pragma solidity ^0.8.4;

/// @title ClonesWithImmutableArgs
/// @notice Deploys minimal-proxy clones that forward immutable args to the
///         implementation's calldata on every DELEGATECALL. Provides both the
///         plain `CREATE` deploy (`clone`) and the deterministic `CREATE2`
///         deploy (`clone2`).
/// @dev    The proxy runtime is the calldata-appending variant pioneered by
///         wighawag/zefram.eth/nick.eth. Implementations read appended args via
///         `calldataload(sub(calldatasize(), ...))` — see paired `Clone.sol`.
///         Output bytecode is byte-identical to the original assembly version,
///         and `clone`/`clone2` produce the same runtime for the same inputs.
///
///         `clone2` diverges from the original wighawag library by taking
///         `salt` as a parameter instead of hardcoding it to 0 (the original
///         would revert on the second deploy of the same `impl` + `data`).
///         Callers SHOULD namespace `salt` by `msg.sender` (e.g.
///         `keccak256(abi.encode(msg.sender, userSalt))`) when the salt-space
///         is user-controlled. Otherwise an attacker can front-run a known
///         deterministic deployment and grief the legitimate deployer.
library ClonesWithImmutableArgs {
    error CreateFail();
    error DataTooLong();
    error ZeroImplementation();

    /// @notice Max length of the appended immutable args. Derived from EIP-170
    ///         (24576-byte runtime cap) minus the 55-byte proxy logic and the
    ///         2-byte length suffix: 24576 - 55 - 2 = 24519. Above this the
    ///         runtime size overflows `uint16(runSize)` in the creation prelude
    ///         and would silently deploy a truncated, broken proxy on chains
    ///         that ever raise EIP-170.
    uint256 internal constant MAX_DATA_LENGTH = 24519;

    /// @notice Deploys a clone of `implementation` with `data` baked into its
    ///         runtime code and appended to every delegatecall's calldata.
    function clone(address implementation, bytes memory data) internal returns (address payable instance) {
        bytes memory bytecode = creation(implementation, data);
        assembly ("memory-safe") {
            instance := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        if (instance == address(0)) revert CreateFail();
    }

    /// @notice Deploys a CREATE2 clone of `implementation` with `data` baked
    ///         in. Reverts if the resulting address is already occupied.
    function clone2(address implementation, bytes32 salt, bytes memory data) internal returns (address payable instance) {
        bytes memory bytecode = creation(implementation, data);
        assembly ("memory-safe") {
            instance := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (instance == address(0)) revert CreateFail();
    }

    /// @notice Off-chain CREATE2 address prediction for `clone2`. Kept as a
    ///         reference comment rather than live code: it is a pure helper with
    ///         no on-chain callers, so it does not need to be part of the audited
    ///         surface. Callers can predict the address off-chain (e.g. in JS, or
    ///         a non-deployed contract) by hashing the same creation bytecode:
    ///
    ///     function addressOfClone2(address deployer, address implementation, bytes32 salt, bytes memory data)
    ///         internal
    ///         pure
    ///         returns (address predicted)
    ///     {
    ///         bytes32 bytecodeHash = keccak256(creation(implementation, data));
    ///         predicted = address(
    ///             uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash))))
    ///         );
    ///     }

    /// @notice Builds the creation bytecode shared by `clone` and `clone2`.
    ///         Public so off-chain callers / tests can derive the CREATE2 address
    ///         without re-implementing the byte layout.
    ///      Layout:
    ///        creation prelude (10):  61 <runSize> 3d 81 60 0a 3d 39 f3
    ///        runtime (55 + extraLength):
    ///          copy calldata:          3d 3d 3d 3d 36 3d 3d 37
    ///          push extraLength:       61 <extraLength>
    ///          codecopy appended args: 60 37 36 39 36
    ///          push extraLength again: 61 <extraLength>
    ///          delegatecall + return:  01 3d 73 <impl> 5a f4 3d 3d 93 80 3e 60 35 57 fd 5b f3
    ///          appended args:          <data><uint16(data.length)>
    ///      `extraLength = data.length + 2`; the 2-byte length suffix at the end
    ///      of the runtime tells `Clone._getImmutableArgsOffset` how far back to
    ///      seek from calldatasize.
    function creation(address implementation, bytes memory data) public pure returns (bytes memory) {
        if (implementation == address(0)) revert ZeroImplementation();
        if (data.length > MAX_DATA_LENGTH) revert DataTooLong();

        uint256 extraLength = data.length + 2;
        uint256 runSize = 0x37 + extraLength;

        return abi.encodePacked(
            hex"61",
            uint16(runSize),
            hex"3d81600a3d39f3",
            hex"3d3d3d3d363d3d37",
            hex"61",
            uint16(extraLength),
            hex"6037363936",
            hex"61",
            uint16(extraLength),
            hex"013d73",
            implementation,
            hex"5af43d3d93803e603557fd5bf3",
            data,
            uint16(data.length)
        );
    }
}
