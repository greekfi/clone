// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {ClonesWithImmutableArgs} from "../src/ClonesWithImmutableArgs.sol";
import {Clone} from "../src/Clone.sol";

/// @dev Implementation contract exposed via clones. Reads the appended
///      args back through `Clone._getArg*` helpers so the tests verify the
///      full deploy+read round-trip.
contract Impl is Clone {
    function argUint256(uint256 offset) external pure returns (uint256) {
        return _getArgUint256(offset);
    }

    function argAddress(uint256 offset) external pure returns (address) {
        return _getArgAddress(offset);
    }

    function argUint64(uint256 offset) external pure returns (uint64) {
        return _getArgUint64(offset);
    }

    function argUint8(uint256 offset) external pure returns (uint8) {
        return _getArgUint8(offset);
    }
}

contract CloneTest is Test {
    Impl impl;

    function setUp() public {
        impl = new Impl();
    }

    // External wrappers so `vm.expectRevert` can catch reverts from these
    // library calls — library calls would otherwise inline into the test
    // function and revert at the same call depth as the cheatcode.
    function callClone(address i, bytes calldata d) external returns (address payable) {
        return ClonesWithImmutableArgs.clone(i, d);
    }

    function callClone2(address i, bytes32 s, bytes calldata d) external returns (address payable) {
        return ClonesWithImmutableArgs.clone2(i, s, d);
    }

    // --- ClonesWithImmutableArgs.clone --------------------------------------

    function test_clone_readsAllTypes() public {
        uint256 u256 = 0x1122334455667788_99aabbccddeeff00_aaaaaaaaaaaaaaaa_bbbbbbbbbbbbbbbb;
        address a = address(0x1234567890AbcdEF1234567890aBcdef12345678);
        uint64 u64 = 0xfedcba9876543210;
        uint8 u8 = 0xAB;

        bytes memory data = abi.encodePacked(u256, a, u64, u8);
        address payable c = ClonesWithImmutableArgs.clone(address(impl), data);

        assertEq(Impl(c).argUint256(0), u256, "uint256");
        assertEq(Impl(c).argAddress(32), a, "address");
        assertEq(Impl(c).argUint64(52), u64, "uint64");
        assertEq(Impl(c).argUint8(60), u8, "uint8");
    }

    function test_clone_revertsOnZeroImpl() public {
        vm.expectRevert(ClonesWithImmutableArgs.ZeroImplementation.selector);
        this.callClone(address(0), abi.encodePacked(uint256(1)));
    }

    function test_clone_revertsOnDataTooLong() public {
        bytes memory tooLong = new bytes(ClonesWithImmutableArgs.MAX_DATA_LENGTH + 1);
        vm.expectRevert(ClonesWithImmutableArgs.DataTooLong.selector);
        this.callClone(address(impl), tooLong);
    }

    function test_clone_atMaxLength_succeeds() public {
        bytes memory atLimit = new bytes(ClonesWithImmutableArgs.MAX_DATA_LENGTH);
        address payable c = ClonesWithImmutableArgs.clone(address(impl), atLimit);
        assertTrue(c.code.length > 0);
    }

    function test_clone_emptyData_succeeds() public {
        address payable c = ClonesWithImmutableArgs.clone(address(impl), "");
        assertTrue(c.code.length > 0);
    }

    function test_clone_runtimeShape() public {
        bytes memory data = abi.encodePacked(uint256(42));
        address payable c = ClonesWithImmutableArgs.clone(address(impl), data);

        // Proxy runtime = 55 bytes of proxy logic + data + uint16 length suffix.
        assertEq(c.code.length, 55 + data.length + 2, "runtime length");

        // Last 2 bytes are uint16(data.length) — the suffix the reader uses.
        uint256 suffix;
        assembly {
            extcodecopy(c, 0, sub(extcodesize(c), 2), 2)
            suffix := shr(240, mload(0))
        }
        assertEq(suffix, data.length, "length suffix");
    }

    // --- ClonesWithImmutableArgs.clone2 ------------------------------------

    function test_clone2_predictionMatchesDeployment() public {
        bytes memory data = abi.encodePacked(uint256(42), address(impl));
        bytes32 salt = keccak256("test-salt");

        // CREATE2 prediction via the public `creation` helper; mirrors the
        // (commented-out) `addressOfClone2` but keeps it out of audited library code.
        bytes32 bytecodeHash = keccak256(ClonesWithImmutableArgs.creation(address(impl), data));
        address predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));

        address payable actual = ClonesWithImmutableArgs.clone2(address(impl), salt, data);
        assertEq(predicted, actual);
    }

    function test_clone2_differentSaltDifferentAddress() public {
        bytes memory data = abi.encodePacked(uint256(42));
        address payable a = ClonesWithImmutableArgs.clone2(address(impl), bytes32(uint256(1)), data);
        address payable b = ClonesWithImmutableArgs.clone2(address(impl), bytes32(uint256(2)), data);
        assertTrue(a != b);
    }

    function test_clone2_collisionReverts() public {
        bytes memory data = abi.encodePacked(uint256(42));
        bytes32 salt = keccak256("dup");

        ClonesWithImmutableArgs.clone2(address(impl), salt, data);
        vm.expectRevert(ClonesWithImmutableArgs.CreateFail.selector);
        this.callClone2(address(impl), salt, data);
    }

    function test_clone2_readsArgs() public {
        uint256 v = 0xCAFEBABE;
        bytes memory data = abi.encodePacked(v);

        address payable c = ClonesWithImmutableArgs.clone2(address(impl), keccak256("k"), data);
        assertEq(Impl(c).argUint256(0), v);
    }

    function test_clone2_revertsOnZeroImpl() public {
        vm.expectRevert(ClonesWithImmutableArgs.ZeroImplementation.selector);
        this.callClone2(address(0), bytes32(0), "");
    }

    function test_clone2_revertsOnDataTooLong() public {
        bytes memory tooLong = new bytes(ClonesWithImmutableArgs.MAX_DATA_LENGTH + 1);
        vm.expectRevert(ClonesWithImmutableArgs.DataTooLong.selector);
        this.callClone2(address(impl), bytes32(0), tooLong);
    }

    // --- bytecode-equality cross-check ---------------------------------------

    /// @dev `clone2` with any non-colliding salt MUST produce the same runtime
    ///      code as `clone` for the same (impl, data) — that's the contract:
    ///      same proxy, different deploy opcode.
    function test_clone_and_clone2_produceSameRuntime() public {
        bytes memory data = abi.encodePacked(uint256(0xABCDEF), address(impl), uint64(99));

        address payable c1 = ClonesWithImmutableArgs.clone(address(impl), data);
        address payable c2 = ClonesWithImmutableArgs.clone2(address(impl), keccak256("x"), data);

        assertEq(c1.code, c2.code, "runtime mismatch");
    }
}
