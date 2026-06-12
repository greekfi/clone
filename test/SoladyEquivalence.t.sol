// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {ClonesWithImmutableArgs} from "../src/ClonesWithImmutableArgs.sol";
import {Clone} from "../src/Clone.sol";
import {LibClone} from "solady/utils/LibClone.sol";

contract SoladyImpl is Clone {
    function a256(uint256 o) external pure returns (uint256) {
        return _getArgUint256(o);
    }
}

/// @notice Documents why Solady's LibClone is NOT the equivalence reference for
///         this library (the reference is wighawag commit 196f1ec — see
///         UpstreamEquivalence.t.sol). Solady is an independent, more-optimized
///         CWIA implementation with a different proxy and a different
///         immutable-args layout, so its audits do not transfer to this code.
///         Pinned against solady v0.1.26.
contract SoladyEquivalenceTest is Test {
    SoladyImpl impl;

    function setUp() public {
        impl = new SoladyImpl();
    }

    /// @dev Solady's proxy is the optimized variant — fewer runtime bytes — so
    ///      it is provably NOT byte-identical to this wighawag-derived library.
    function test_notByteIdentical_toSolady() public {
        bytes memory data = abi.encodePacked(uint256(0xABCDEF), address(impl), uint64(99));

        address ours = ClonesWithImmutableArgs.clone(address(impl), data);
        address solady = LibClone.clone(address(impl), data);

        assertTrue(ours.code.length > solady.code.length, "expected solady proxy to be smaller");
        assertTrue(keccak256(ours.code) != keccak256(solady.code), "unexpected byte-identity with solady");
    }

    /// @dev And the layouts are incompatible: this library appends a trailing
    ///      uint16 length suffix and reads backward from it; Solady encodes the
    ///      length in the creation code and appends no suffix. So this library's
    ///      reader does NOT correctly read a Solady-deployed clone.
    function test_readerNotCompatible_withSolady() public {
        bytes memory data = abi.encodePacked(uint256(0xABCDEF));

        address solady = LibClone.clone(address(impl), data);

        // Reading a Solady clone with this library's reader yields the wrong
        // value (it mislocates the args), confirming the layouts differ.
        assertTrue(SoladyImpl(solady).a256(0) != 0xABCDEF, "layouts unexpectedly matched");
    }
}
