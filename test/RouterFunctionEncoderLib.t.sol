// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IPActionMiscV3} from "pendle-core-v2-public/contracts/interfaces/IPActionMiscV3.sol";
import {IPActionSwapPTV3} from "pendle-core-v2-public/contracts/interfaces/IPActionSwapPTV3.sol";
import {IPActionSwapYTV3} from "pendle-core-v2-public/contracts/interfaces/IPActionSwapYTV3.sol";

import "./RouterFunctionTypes.t.sol";

library RouterFunctionEncoderLib {
    error WrongSelector(bytes4 expected, bytes4 got);

    function decode_swapExactTokenForPt(bytes memory callData)
        internal
        pure
        returns (SwapExactTokenForPt memory params)
    {
        _checkSelector(IPActionSwapPTV3.swapExactTokenForPt.selector, callData);
        (params.receiver, params.market, params.minPtOut, params.guessPtOut, params.input, params.limit) =
            abi.decode(_slice(callData, 4), (address, address, uint256, ApproxParams, TokenInput, LimitOrderData));
    }

    function decode_swapExactPtForToken(bytes memory callData)
        internal
        pure
        returns (SwapExactPtForToken memory params)
    {
        _checkSelector(IPActionSwapPTV3.swapExactPtForToken.selector, callData);
        (params.receiver, params.market, params.exactPtIn, params.output, params.limit) =
            abi.decode(_slice(callData, 4), (address, address, uint256, TokenOutput, LimitOrderData));
    }

    function decode_swapExactTokenForYt(bytes memory callData)
        internal
        pure
        returns (SwapExactTokenForYt memory params)
    {
        _checkSelector(IPActionSwapYTV3.swapExactTokenForYt.selector, callData);
        (params.receiver, params.market, params.minYtOut, params.guessYtOut, params.input, params.limit) =
            abi.decode(_slice(callData, 4), (address, address, uint256, ApproxParams, TokenInput, LimitOrderData));
    }

    function decode_swapExactYtForToken(bytes memory callData)
        internal
        pure
        returns (SwapExactYtForToken memory params)
    {
        _checkSelector(IPActionSwapYTV3.swapExactYtForToken.selector, callData);
        (params.receiver, params.market, params.exactYtIn, params.output, params.limit) =
            abi.decode(_slice(callData, 4), (address, address, uint256, TokenOutput, LimitOrderData));
    }

    function decode_swapExactSyForPt(bytes memory callData) internal pure returns (SwapExactSyForPt memory params) {
        _checkSelector(IPActionSwapPTV3.swapExactSyForPt.selector, callData);
        (params.receiver, params.market, params.exactSyIn, params.minPtOut, params.guessPtOut, params.limit) =
            abi.decode(_slice(callData, 4), (address, address, uint256, uint256, ApproxParams, LimitOrderData));
    }

    function decode_swapExactPtForSy(bytes memory callData) internal pure returns (SwapExactPtForSy memory params) {
        _checkSelector(IPActionSwapPTV3.swapExactPtForSy.selector, callData);
        (params.receiver, params.market, params.exactPtIn, params.minSyOut, params.limit) =
            abi.decode(_slice(callData, 4), (address, address, uint256, uint256, LimitOrderData));
    }

    function decode_swapExactSyForYt(bytes memory callData) internal pure returns (SwapExactSyForYt memory params) {
        _checkSelector(IPActionSwapYTV3.swapExactSyForYt.selector, callData);
        (params.receiver, params.market, params.exactSyIn, params.minYtOut, params.guessYtOut, params.limit) =
            abi.decode(_slice(callData, 4), (address, address, uint256, uint256, ApproxParams, LimitOrderData));
    }

    function decode_swapExactYtForSy(bytes memory callData) internal pure returns (SwapExactYtForSy memory params) {
        _checkSelector(IPActionSwapYTV3.swapExactYtForSy.selector, callData);
        (params.receiver, params.market, params.exactYtIn, params.minSyOut, params.limit) =
            abi.decode(_slice(callData, 4), (address, address, uint256, uint256, LimitOrderData));
    }

    function decode_redeemSyToToken(bytes memory callData) internal pure returns (RedeemSyToToken memory params) {
        _checkSelector(IPActionMiscV3.redeemSyToToken.selector, callData);
        (params.receiver, params.SY, params.netSyIn, params.output) =
            abi.decode(_slice(callData, 4), (address, address, uint256, TokenOutput));
    }

    function decode_mintSyFromToken(bytes memory callData) internal pure returns (MintSyFromToken memory params) {
        _checkSelector(IPActionMiscV3.mintSyFromToken.selector, callData);
        (params.receiver, params.SY, params.minSyOut, params.input) =
            abi.decode(_slice(callData, 4), (address, address, uint256, TokenInput));
    }

    function decode_callAndReflect(bytes memory callData) internal pure returns (CallAndReflect memory params) {
        _checkSelector(IPActionMiscV3.callAndReflect.selector, callData);
        (params.reflector, params.selfCall1, params.selfCall2, params.reflectCall) =
            abi.decode(_slice(callData, 4), (address, bytes, bytes, bytes));
    }

    function decode_redeemPyToToken(bytes memory callData) internal pure returns (RedeemPyToToken memory params) {
        _checkSelector(IPActionMiscV3.redeemPyToToken.selector, callData);
        (params.receiver, params.YT, params.netPyIn, params.output) =
            abi.decode(_slice(callData, 4), (address, address, uint256, TokenOutput));
    }

    function decode_swapTokensToTokens(bytes memory callData) internal pure returns (SwapTokensToTokens memory params) {
        _checkSelector(IPActionMiscV3.swapTokensToTokens.selector, callData);
        (params.pendleSwap, params.swaps, params.netSwaps) =
            abi.decode(_slice(callData, 4), (IPSwapAggregator, SwapDataExtra[], uint256[]));
    }

    function _checkSelector(bytes4 expected, bytes memory callData) private pure {
        if (expected != bytes4(callData)) revert WrongSelector(expected, bytes4(callData));
    }

    /// @dev Returns a copy of `subject` sliced from `start` to the end of the bytes.
    /// `start` is a byte offset.
    function _slice(bytes memory subject, uint256 start) private pure returns (bytes memory result) {
        result = _slice(subject, start, type(uint256).max);
    }

    /// @dev Returns a copy of `subject` sliced from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets.
    /// Forked from solady
    function _slice(bytes memory subject, uint256 start, uint256 end) private pure returns (bytes memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            let l := mload(subject) // Subject length.
            if iszero(gt(l, end)) { end := l }
            if iszero(gt(l, start)) { start := l }
            if lt(start, end) {
                result := mload(0x40)
                let n := sub(end, start)
                let i := add(subject, start)
                let w := not(0x1f)
                // Copy the `subject` one word at a time, backwards.
                for { let j := and(add(n, 0x1f), w) } 1 {} {
                    mstore(add(result, j), mload(add(i, j)))
                    j := add(j, w) // `sub(j, 0x20)`.
                    if iszero(j) { break }
                }
                let o := add(add(result, 0x20), n)
                mstore(o, 0) // Zeroize the slot after the bytes.
                mstore(0x40, add(o, 0x20)) // Allocate memory.
                mstore(result, n) // Store the length.
            }
        }
    }
}
