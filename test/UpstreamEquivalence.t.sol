// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {ClonesWithImmutableArgs} from "../src/ClonesWithImmutableArgs.sol";
import {Clone} from "../src/Clone.sol";
import {ClonesWithImmutableArgs as UpstreamCWIA} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";

contract Impl is Clone {
    function a256(uint256 o) external pure returns (uint256) {
        return _getArgUint256(o);
    }

    function aAddr(uint256 o) external pure returns (address) {
        return _getArgAddress(o);
    }

    function a64(uint256 o) external pure returns (uint64) {
        return _getArgUint64(o);
    }

    function a8(uint256 o) external pure returns (uint8) {
        return _getArgUint8(o);
    }
}

/// @notice Audit-inheritance evidence. This library is a fork of
///         wighawag/clones-with-immutable-args (see Clone.sol). These tests
///         prove the deployed proxy bytecode is byte-for-byte identical to the
///         upstream-audited implementation, so a reviewer can confirm
///         equivalence by diff rather than auditing the assembly from scratch.
contract UpstreamEquivalenceTest is Test {
    Impl impl;

    function setUp() public {
        impl = new Impl();
    }

    /// @dev THE key test: this fork's `clone()` must emit byte-identical runtime
    ///      code to upstream wighawag's `clone()` for the same (impl, data).
    function test_byteIdentical_toUpstreamWighawag() public {
        bytes memory data = abi.encodePacked(uint256(0xABCDEF), address(impl), uint64(99), uint8(7));

        address ours = ClonesWithImmutableArgs.clone(address(impl), data);
        address upstream = UpstreamCWIA.clone(address(impl), data);

        assertEq(ours.code, upstream.code, "runtime bytecode diverged from audited upstream");
    }

    /// @dev Identity must hold across arg lengths, including the edge cases.
    function testFuzz_byteIdentical_toUpstream(bytes calldata data) public {
        vm.assume(data.length <= ClonesWithImmutableArgs.MAX_DATA_LENGTH);
        address ours = ClonesWithImmutableArgs.clone(address(impl), data);
        address upstream = UpstreamCWIA.clone(address(impl), data);
        assertEq(ours.code, upstream.code, "runtime diverged from upstream for this length");
    }

    /// @dev A clone deployed by upstream is read identically by this fork's
    ///      reader (same calldata-forwarding layout) — and vice versa.
    function test_readerCompatible_withUpstream() public {
        bytes memory data = abi.encodePacked(uint256(0xABCDEF), address(impl), uint64(99), uint8(7));

        address ours = ClonesWithImmutableArgs.clone(address(impl), data);
        address upstream = UpstreamCWIA.clone(address(impl), data);

        assertEq(Impl(upstream).a256(0), Impl(ours).a256(0), "uint256");
        assertEq(Impl(upstream).aAddr(32), Impl(ours).aAddr(32), "address");
        assertEq(Impl(upstream).a64(52), Impl(ours).a64(52), "uint64");
        assertEq(Impl(upstream).a8(60), Impl(ours).a8(60), "uint8");
    }

    /// @dev Reader offset-arithmetic coverage: whatever is packed in must read
    ///      back out, at every supported type/offset, for random values.
    function testFuzz_argRoundTrip(uint256 u256, address a, uint64 u64, uint8 u8) public {
        bytes memory data = abi.encodePacked(u256, a, u64, u8);
        Impl c = Impl(ClonesWithImmutableArgs.clone(address(impl), data));

        assertEq(c.a256(0), u256, "uint256");
        assertEq(c.aAddr(32), a, "address");
        assertEq(c.a64(52), u64, "uint64");
        assertEq(c.a8(60), u8, "uint8");
    }
}
