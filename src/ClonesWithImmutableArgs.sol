// SPDX-License-Identifier: BSD
pragma solidity ^0.8.4;

/// @title ClonesWithImmutableArgs
/// @notice Deploys minimal-proxy clones that forward immutable args to the
///         implementation's calldata on every DELEGATECALL.
/// @dev    The proxy runtime is the calldata-appending variant pioneered by
///         wighawag/zefram.eth/nick.eth. Implementations read appended args via
///         `calldataload(sub(calldatasize(), ...))` — see paired `Clone.sol`.
///         Output bytecode is byte-identical to the original assembly version.
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
        if (implementation == address(0)) revert ZeroImplementation();
        if (data.length > MAX_DATA_LENGTH) revert DataTooLong();

        // extraLength = data.length + 2 (the 2-byte length suffix at the end
        // of the runtime tells `Clone._getImmutableArgsOffset` how far back
        // to seek from calldatasize).
        uint256 extraLength = data.length + 2;
        uint256 runSize = 0x37 + extraLength;

        // Layout of the creation bytecode:
        //   creation prelude (10):  61 <runSize> 3d 81 60 0a 3d 39 f3
        //   runtime (55 + extraLength):
        //     copy calldata:          3d 3d 3d 3d 36 3d 3d 37
        //     push extraLength:       61 <extraLength>
        //     codecopy appended args: 60 37 36 39 36
        //     push extraLength again: 61 <extraLength>
        //     delegatecall + return:  01 3d 73 <impl> 5a f4 3d 3d 93 80 3e 60 35 57 fd 5b f3
        //     appended args:          <data><uint16(data.length)>
        bytes memory bytecode = abi.encodePacked(
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

        assembly ("memory-safe") {
            instance := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        if (instance == address(0)) revert CreateFail();
    }
}
