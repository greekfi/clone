// SPDX-License-Identifier: BSD
pragma solidity ^0.8.4;

/// @title Clones2WithImmutableArgs
/// @notice Deterministic (CREATE2) version of `ClonesWithImmutableArgs`. The
///         proxy runtime is identical, so implementations can use the same
///         `Clone.sol` reader.
/// @dev    Diverges from the original wighawag library by taking `salt` as a
///         parameter instead of hardcoding it to 0 (the original would revert
///         on the second deploy of the same `impl` + `data`).
///
///         Callers SHOULD namespace `salt` by `msg.sender` (e.g.
///         `keccak256(abi.encode(msg.sender, userSalt))`) when the salt-space
///         is user-controlled. Otherwise an attacker can front-run a known
///         deterministic deployment and grief the legitimate deployer.
library Clones2WithImmutableArgs {
    error CreateFail();
    error DataTooLong();
    error ZeroImplementation();

    /// @notice Max length of the appended immutable args. See
    ///         `ClonesWithImmutableArgs.MAX_DATA_LENGTH`.
    uint256 internal constant MAX_DATA_LENGTH = 24519;

    /// @notice Deploys a CREATE2 clone of `implementation` with `data` baked
    ///         in. Reverts if the resulting address is already occupied.
    function clone2(address implementation, bytes32 salt, bytes memory data)
        internal
        returns (address payable instance)
    {
        bytes memory bytecode = _creationBytecode(implementation, data);
        assembly ("memory-safe") {
            instance := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (instance == address(0)) revert CreateFail();
    }

    /// @notice Predicts the CREATE2 address of `clone2(implementation, salt, data)`
    ///         when called from `deployer`. Does not check whether the clone
    ///         has actually been deployed.
    function addressOfClone2(address deployer, address implementation, bytes32 salt, bytes memory data)
        internal
        pure
        returns (address predicted)
    {
        bytes32 bytecodeHash = keccak256(_creationBytecode(implementation, data));
        predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash))))
        );
    }

    function _creationBytecode(address implementation, bytes memory data) private pure returns (bytes memory) {
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
