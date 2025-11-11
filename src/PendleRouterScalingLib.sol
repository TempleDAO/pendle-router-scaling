// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IPActionMiscV3} from "external/pendle/interfaces/IPActionMiscV3.sol";
import {IPActionSwapPTV3} from "external/pendle/interfaces/IPActionSwapPTV3.sol";
import {IPActionSwapYTV3} from "external/pendle/interfaces/IPActionSwapYTV3.sol";
import {BytesLib} from "./BytesLib.sol";

/// @title Pendle Router Calldata Scaling Library
/// @notice Adjust calldata onchain to scale to a new source token amount
/// @dev
///   - Supports (some but not all) calldata when calling the `/convert` endpoint on the Pendle API v2
///   - https://api-v2.pendle.finance/core/docs
///   - `needScale` must be set to true
///   - It is advisable to set a decent slippage margin as not all parameters are updated.
///   - Some functions are not supported, notably `swapTokensToTokens()` when trying to convert 2 non-pendle tokens.
///   - See `_offsetMappings()` for a list of supported Pendle Router functions, as well as the composite `callAndReflect()`
library PendleRouterScalingLib {
    error UnsupportedSelector(bytes4 selector);

    /// @dev Adjust the `callData` such that
    ///  - The 'from' token amount is set to `newSellAmount`
    ///  - The 'to' token min buy amount (for slippage checks) is scaled by the same proportion as the
    ///    'from' token amount delta.
    /// This updates `callData` in place avoiding expensive copies where possible.
    function scaleCalldata(uint256 newSellAmount, bytes memory callData) internal pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 selector = bytes4(callData);

        if (selector == IPActionMiscV3.callAndReflect.selector) {
            // `callAndReflect` is a composite call.
            // The first `params.selfCall1` is scaled, and the other inputs are left as is.

            /*
            function callAndReflect(
                address payable reflector,          <-- word 0
                bytes calldata selfCall1,           <-- contents starts at word 5 (dynamic length)
                bytes calldata selfCall2,           <-- dynamic start & length
                bytes calldata reflectCall          <-- dynamic start & length
            )
            */

            // selfCall1 start == params.selfCall1
            //   4 byte selector + 5 x 32 byte slots = 164
            uint256 selfCall1Offset = 164;

            // Load the selector of the selfCall1
            bytes4 selfCall1Selector = bytes4(BytesLib.get(callData, selfCall1Offset));

            // Scale the `selfCall1` in place
            _scaleCalldata1(newSellAmount, callData, selfCall1Selector, selfCall1Offset);
        } else {
            _scaleCalldata1(newSellAmount, callData, selector, 0);
        }
    }

    function _scaleCalldata1(uint256 newSellAmount, bytes memory callData, bytes4 selector, uint256 selectorOffset)
        private
        pure
    {
        // - The amount of the source token is updated in place
        // - The `min` amount of the destination token is scaled by the change in the source token
        // - The 'guess' params are not updated.
        // - Assumed there are no limits
        // - Assumed that the caller has set `needScale` appropriately when calling the API offchain
        (uint256 sellAmountOffset, uint256 minBuyAmountOffset) = _offsetMappings(selector, selectorOffset);

        // If the new number is the same then nothing else to do
        uint256 oldSellAmount = uint256(BytesLib.get(callData, sellAmountOffset));
        if (oldSellAmount == newSellAmount) return;

        // Update the sell amount directly.
        BytesLib.set(callData, sellAmountOffset, bytes32(newSellAmount));

        // scale the min buy amount by the change in the sell amount.
        // Rounding down is acceptable given the minimal impact to slippage
        uint256 minTokenOut = uint256(BytesLib.get(callData, minBuyAmountOffset)) * newSellAmount / oldSellAmount;
        BytesLib.set(callData, minBuyAmountOffset, bytes32(minTokenOut));
    }

    /// @dev Map known selectors
    function _offsetMappings(bytes4 selector, uint256 actionSelectorOffset)
        private
        pure
        returns (uint256 sellAmountOffset, uint256 minBuyAmountOffset)
    {
        if (selector == IPActionSwapPTV3.swapExactTokenForPt.selector) {
            /*
            function swapExactTokenForPt(
                address receiver,                   <-- word 0
                address market,                     <-- word 1
                uint256 minPtOut,                   <-- word 2
                ApproxParams calldata guessPtOut,   <-- starts at word 3 (5 word long)
                TokenInput calldata input,          <-- starts at word 10 (dynamic length)
                LimitOrderData calldata limit       <-- dynamic
            )
            */

            // sell amount == params.input.netTokenIn (word 1 within TokenInput)
            //   4 byte selector + 11 x 32 byte slots = 365
            sellAmountOffset = 356;

            // min buy amount == params.minPtOut
            //   4 byte selector + 2 x 32 byte slots = 68
            minBuyAmountOffset = 68;
        } else if (selector == IPActionSwapPTV3.swapExactPtForToken.selector) {
            /*
            function swapExactPtForToken(
                address receiver,                   <-- word 0
                address market,                     <-- word 1
                uint256 exactPtIn,                  <-- word 2
                TokenOutput calldata output,        <-- starts at word 5 (dynamic length)
                LimitOrderData calldata limit       <-- dynamic
            )
            */

            // sell amount == params.exactPtIn
            //   4 byte selector + 2 x 32 byte slots = 68
            sellAmountOffset = 68;

            // min buy amount == params.output.minTokenOut (word 1 within TokenOutput)
            //   4 byte selector + 6 x 32 byte slots = 196
            minBuyAmountOffset = 196;
        } else if (selector == IPActionSwapPTV3.swapExactSyForPt.selector) {
            /*
            function swapExactSyForPt(
                address receiver,                   <-- word 0
                address market,                     <-- word 1
                uint256 exactSyIn,                  <-- word 2
                uint256 minPtOut,                   <-- word 3
                ApproxParams calldata guessPtOut,   <-- starts at word 4 (5 word long)
                LimitOrderData calldata limit       <-- starts at word 6 (dynamic length)
            )
            */
            // sell amount == params.exactSyIn
            //   4 byte selector + 2 x 32 byte slots = 68
            sellAmountOffset = 68;

            // min buy amount == params.minPtOut
            //   4 byte selector + 3 x 32 byte slots = 100
            minBuyAmountOffset = 100;
        } else if (selector == IPActionSwapPTV3.swapExactPtForSy.selector) {
            /*
            function swapExactPtForSy(
                address receiver,                   <-- word 0
                address market,                     <-- word 1
                uint256 exactPtIn,                  <-- word 2
                uint256 minSyOut,                   <-- word 3
                LimitOrderData calldata limit       <-- starts at word 5 (dynamic length)
            )
            */
            // sell amount == params.exactPtIn
            //   4 byte selector + 2 x 32 byte slots = 68
            sellAmountOffset = 68;

            // min buy amount == params.minSyOut
            //   4 byte selector + 3 x 32 byte slots = 100
            minBuyAmountOffset = 100;
        } else if (selector == IPActionSwapYTV3.swapExactTokenForYt.selector) {
            /*
            function swapExactTokenForYt(
                address receiver,                   <-- word 0
                address market,                     <-- word 1
                uint256 minYtOut,                   <-- word 2
                ApproxParams calldata guessYtOut,   <-- starts at word 3 (5 word long)
                TokenInput calldata input,          <-- starts at word 10 (dynamic length)
                LimitOrderData calldata limit       <-- dynamic
            )
            */
            // sell amount == params.input.netTokenIn (word 1 within TokenInput)
            //   4 byte selector + 11 x 32 byte slots = 365
            sellAmountOffset = 356;

            // min buy amount == params.minYtOut
            //   4 byte selector + 2 x 32 byte slots = 68
            minBuyAmountOffset = 68;
        } else if (selector == IPActionSwapYTV3.swapExactYtForToken.selector) {
            /*
            function swapExactYtForToken(
                address receiver,                   <-- word 0
                address market,                     <-- word 1
                uint256 exactYtIn,                  <-- word 2
                TokenOutput calldata output,        <-- starts at word 5 (dynamic length)
                LimitOrderData calldata limit       <-- dynamic
            )
            */
            // sell amount == params.exactYtIn
            //   4 byte selector + 2 x 32 byte slots = 68
            sellAmountOffset = 68;

            // min buy amount == params.output.minTokenOut (word 1 within TokenOutput)
            //   4 byte selector + 6 x 32 byte slots = 196
            minBuyAmountOffset = 196;
        } else if (selector == IPActionSwapYTV3.swapExactSyForYt.selector) {
            /*
            function swapExactSyForYt(
                address receiver,                   <-- word 0
                address market,                     <-- word 1
                uint256 exactSyIn,                  <-- word 2
                uint256 minYtOut,                   <-- word 3
                ApproxParams calldata guessYtOut,   <-- starts at word 4 (5 word long)
                LimitOrderData calldata limit       <-- starts at word 6 (dynamic length)
            )
            */
            // sell amount == params.exactSyIn
            //   4 byte selector + 2 x 32 byte slots = 68
            sellAmountOffset = 68;

            // min buy amount == params.minYtOut
            //   4 byte selector + 3 x 32 byte slots = 100
            minBuyAmountOffset = 100;
        } else if (selector == IPActionSwapYTV3.swapExactYtForSy.selector) {
            /*
            function swapExactYtForSy(
                address receiver,                   <-- word 0
                address market,                     <-- word 1
                uint256 exactYtIn,                  <-- word 2
                uint256 minSyOut,                   <-- word 3
                LimitOrderData calldata limit       <-- starts at word 5 (dynamic length)
            )
            */
            // sell amount == params.exactYtIn
            //   4 byte selector + 2 x 32 byte slots = 68
            sellAmountOffset = 68;

            // min buy amount == params.minSyOut
            //   4 byte selector + 3 x 32 byte slots = 100
            minBuyAmountOffset = 100;
        } else if (selector == IPActionMiscV3.redeemSyToToken.selector) {
            /*
            function redeemSyToToken(
                address receiver,                   <-- word 0
                address SY,                         <-- word 1
                uint256 netSyIn,                    <-- word 2
                TokenOutput calldata output         <-- starts at word 4 (dynamic length)
            )
            */
            // sell amount == params.netSyIn
            //   4 byte selector + 2 x 32 byte slots = 68
            sellAmountOffset = 68;

            // min buy amount == params.output.minSyOut (word 1 within TokenOutput)
            //   4 byte selector + 5 x 32 byte slots = 164
            minBuyAmountOffset = 164;
        } else if (selector == IPActionMiscV3.mintSyFromToken.selector) {
            /*
            function mintSyFromToken(
                address receiver,                   <-- word 0
                address SY,                         <-- word 1
                uint256 minSyOut,                   <-- word 2
                TokenInput calldata input           <-- starts at word 4 (dynamic length)
            )
            */
            // sell amount == params.input.netTokenIn
            //   4 byte selector + 5 x 32 byte slots = 164
            sellAmountOffset = 164;

            // min buy amount == params.minSyOut
            //   4 byte selector + 2 x 32 byte slots = 68
            minBuyAmountOffset = 68;
        } else if (selector == IPActionMiscV3.redeemPyToToken.selector) {
            /*
            function redeemPyToToken(
                address receiver,                   <-- word 0
                address YT,                         <-- word 1
                uint256 netPyIn,                    <-- word 2
                TokenOutput calldata output         <-- starts at word 4 (dynamic length)
            )
            */
            // sell amount == params.netPyIn
            //   4 byte selector + 2 x 32 byte slots = 68
            sellAmountOffset = 68;

            // min buy amount == params.output.minTokenOut
            //   4 byte selector + 5 x 32 byte slots = 164
            minBuyAmountOffset = 164;
        } else {
            // There may be other functions we need to support in future, in which case
            revert UnsupportedSelector(selector);
        }

        // Add on the offset to the start of the action function selector
        if (actionSelectorOffset > 0) {
            sellAmountOffset += actionSelectorOffset;
            minBuyAmountOffset += actionSelectorOffset;
        }
    }
}
