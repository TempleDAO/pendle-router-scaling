// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

/// @notice Library exposing bytes manipulation.
/// @dev Credit to Morpho:
/// https://github.com/morpho-org/bundler3/blob/dfea9e240ae5bf55f1f49d0084c0f7af6d84a365/src/libraries/BytesLib.sol
library BytesLib {
    error InvalidOffset();

    /// @notice Reads 32 bytes at offset `offset` of memory bytes `data`.
    function get(bytes memory data, uint256 offset) internal pure returns (bytes32 result) {
        if (offset > data.length - 0x20) revert InvalidOffset();
        assembly ("memory-safe") {
            result := mload(add(0x20, add(data, offset)))
        }
    }

    /// @notice Writes `value` at offset `offset` of memory bytes `data`.
    function set(bytes memory data, uint256 offset, bytes32 value) internal pure {
        if (offset > data.length - 0x20) revert InvalidOffset();
        assembly ("memory-safe") {
            mstore(add(0x20, add(data, offset)), value)
        }
    }
}
