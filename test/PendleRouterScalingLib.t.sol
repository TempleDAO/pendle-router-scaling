// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";

import {stdError} from "forge-std/StdError.sol";
import {SwapType, SwapData} from "pendle-core-v2-public/contracts/router/swap-aggregator/IPSwapAggregator.sol";
import {IPActionSwapYTV3} from "pendle-core-v2-public/contracts/interfaces/IPActionSwapYTV3.sol";

import {PendleRouterScalingLib} from "src/PendleRouterScalingLib.sol";
import "./RouterFunctionEncoderLib.t.sol";
import {BytesLib} from "src/BytesLib.sol";

// Pendle's convert api doesn't respect `needScale` for the inner PendleSwap call to kyberswap
// For now ignore
bool constant PENDLE_EXCEPTION_mintSyFromToken = true;

// Pendle's swapTokensToTokens hardcodes `needScale` to false - so its not supported
bool constant PENDLE_EXCEPTION_swapTokensToTokens = true;

// wrap to avoid 'call didn't revert at a lower depth than cheatcode call depth'
contract ScalingContractWrapper {
    function scaleCalldata(uint256 newSellAmount, bytes calldata callData)
        external
        pure
        returns (bytes memory scaledCallData)
    {
        // Initial copy
        scaledCallData = callData;

        // Update in place
        PendleRouterScalingLib.scaleCalldata(newSellAmount, scaledCallData);
    }
}

contract PendleRouterScalingLibTest is TestBase {
    using RouterFunctionEncoderLib for bytes;

    ScalingContractWrapper public scaler;

    function setUp() public virtual {
        scaler = new ScalingContractWrapper();
    }

    function test_noAmountChange() public {
        CalldataItem[] memory items = loadTestItems();
        CalldataItem memory item;
        for (uint256 i; i < items.length; ++i) {
            item = items[i];
            if (isUnsupported(bytes4(item.data))) {
                vm.expectRevert(
                    abi.encodeWithSelector(PendleRouterScalingLib.UnsupportedSelector.selector, bytes4(item.data))
                );
                scaler.scaleCalldata(item.amountInBN, item.data);
            } else {
                bytes memory scaledData = scaler.scaleCalldata(item.amountInBN, item.data);
                assertEq(scaledData, item.data);
            }
        }
    }

    function test_badCalldataOffset() public {
        vm.expectRevert(abi.encodeWithSelector(BytesLib.InvalidOffset.selector));
        scaler.scaleCalldata(123, abi.encodePacked(IPActionSwapYTV3.swapExactYtForSy.selector, uint256(123)));
    }

    function test_badCalldataShort() public {
        vm.expectRevert(stdError.arithmeticError);
        scaler.scaleCalldata(123, bytes.concat(IPActionSwapYTV3.swapExactYtForSy.selector, hex"1234"));
    }

    function test_all_fromJson() public {
        CalldataItem[] memory items = loadTestItems();
        CalldataItem memory item;
        for (uint256 i; i < items.length; ++i) {
            item = items[i];
            if (isEqual(item.method, "callAndReflect")) {
                handle_callAndReflect(item);
            } else {
                handleInner(item);
            }
        }
    }

    function handleInner(CalldataItem memory item) private {
        if (isEqual(item.method, "mintSyFromToken")) {
            handle_mintSyFromToken(item);
        } else if (isEqual(item.method, "redeemPyToToken")) {
            handle_redeemPyToToken(item);
        } else if (isEqual(item.method, "redeemSyToToken")) {
            handle_redeemSyToToken(item);
        } else if (isEqual(item.method, "swapExactPtForSy")) {
            handle_swapExactPtForSy(item);
        } else if (isEqual(item.method, "swapExactPtForToken")) {
            handle_swapExactPtForToken(item);
        } else if (isEqual(item.method, "swapExactSyForPt")) {
            handle_swapExactSyForPt(item);
        } else if (isEqual(item.method, "swapExactSyForYt")) {
            handle_swapExactSyForYt(item);
        } else if (isEqual(item.method, "swapExactTokenForPt")) {
            handle_swapExactTokenForPt(item);
        } else if (isEqual(item.method, "swapExactTokenForYt")) {
            handle_swapExactTokenForYt(item);
        } else if (isEqual(item.method, "swapExactYtForSy")) {
            handle_swapExactYtForSy(item);
        } else if (isEqual(item.method, "swapExactYtForToken")) {
            handle_swapExactYtForToken(item);
        } else if (isEqual(item.method, "swapTokensToTokens")) {
            handle_swapTokensToTokens(item);
        } else {
            revert UnhandledFunction(item.method);
        }
    }

    function assertValid(SwapData memory a, bytes4 selector) internal pure {
        assertTrue(a.swapType == SwapType.NONE || a.swapType == SwapType.KYBERSWAP, "swapData.swapType");
        assertTrue(a.extRouter == KYBER_ROUTER_V2 || a.extRouter == address(0), "swapData.extRouter");
        assertTrue(
            a.extRouter == KYBER_ROUTER_V2
                ? bytes4(a.extCalldata) == 0xe21fd0e9  /* kyber.swap(...) */
                : a.extCalldata.length == 0,
            "swapData.extCalldata"
        );

        if (
            (selector == IPActionMiscV3.mintSyFromToken.selector && PENDLE_EXCEPTION_mintSyFromToken)
                || (selector == IPActionMiscV3.swapTokensToTokens.selector && PENDLE_EXCEPTION_swapTokensToTokens)
        ) {
            // skip the check
        } else {
            assertEq(a.needScale, a.extRouter == KYBER_ROUTER_V2, "swapData.needScale");
        }
    }

    function assertValid(TokenInput memory a, CalldataItem memory item, bytes4 selector) internal pure {
        assertEq(a.tokenIn, item.tokenInAddr, "input.tokenIn");
        assertEq(a.netTokenIn, item.amountInBN, "input.netTokenIn");
        assertNotEq(a.tokenMintSy, address(0), "input.tokenMintSy");
        assertTrue(a.pendleSwap == PENDLE_SWAP || a.pendleSwap == address(0), "input.pendleSwap");
        assertValid(a.swapData, selector);
    }

    function assertValid(TokenOutput memory a, CalldataItem memory item, bytes4 selector) internal pure {
        assertEq(a.tokenOut, item.tokenOutAddr, "output.tokenOut");
        assertGt(a.minTokenOut, 0, "output.minTokenOut");
        assertNotEq(a.tokenRedeemSy, address(0), "output.tokenRedeemSy");
        assertTrue(a.pendleSwap == PENDLE_SWAP || a.pendleSwap == address(0), "output.pendleSwap");
        assertValid(a.swapData, selector);
    }

    function assertValid(ApproxParams memory a) internal pure {
        assertGt(a.guessMin, 0, "guessMin > 0");
        assertGt(a.guessMax, 0, "guessMax > 0");
        assertGt(a.guessOffchain, 0, "guessOffchain > 0");
        assertGt(a.maxIteration, 0, "maxIteration > 0");
        assertGt(a.eps, 0, "eps > 0");
    }

    function handle_swapExactTokenForPt(CalldataItem memory item) private view {
        bytes4 selector = IPActionSwapPTV3.swapExactTokenForPt.selector;
        SwapExactTokenForPt memory params = item.data.decode_swapExactTokenForPt();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.market, address(0), "market");
        assertGt(params.minPtOut, 0, "minPtOut");
        assertValid(params.guessPtOut);
        assertValid(params.input, item, selector);
        // Not checking expected limit details as it may change per query

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        SwapExactTokenForPt memory scaledParams = scaledData.decode_swapExactTokenForPt();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.market, params.market, "market");
        assertEq(scaledParams.minPtOut, add5Pct(params.minPtOut), "minPtOut");
        assertMatching(scaledParams.guessPtOut, params.guessPtOut);
        assertMatching(scaledParams.input, params.input);
        assertMatching(scaledParams.limit, params.limit);
    }

    function handle_swapExactPtForToken(CalldataItem memory item) private view returns (bytes memory scaledData) {
        bytes4 selector = IPActionSwapPTV3.swapExactPtForToken.selector;
        SwapExactPtForToken memory params = item.data.decode_swapExactPtForToken();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.market, address(0), "market");
        assertEq(params.exactPtIn, item.amountInBN, "exactPtIn");
        assertValid(params.output, item, selector);
        // Not checking expected limit details as it may change per query

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        SwapExactPtForToken memory scaledParams = scaledData.decode_swapExactPtForToken();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.market, params.market, "market");
        assertEq(scaledParams.exactPtIn, add5Pct(params.exactPtIn), "exactPtIn");
        assertMatching(scaledParams.output, params.output);
        assertMatching(scaledParams.limit, params.limit);
    }

    function handle_swapExactTokenForYt(CalldataItem memory item) private view {
        bytes4 selector = IPActionSwapYTV3.swapExactTokenForYt.selector;
        SwapExactTokenForYt memory params = item.data.decode_swapExactTokenForYt();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.market, address(0), "market");
        assertGt(params.minYtOut, 0, "minYtOut");
        assertValid(params.guessYtOut);
        assertValid(params.input, item, selector);
        // Not checking expected limit details as it may change per query

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        SwapExactTokenForYt memory scaledParams = scaledData.decode_swapExactTokenForYt();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.market, params.market, "market");
        assertEq(scaledParams.minYtOut, add5Pct(params.minYtOut), "minYtOut");
        assertMatching(scaledParams.guessYtOut, params.guessYtOut);
        assertMatching(scaledParams.input, params.input);
        assertMatching(scaledParams.limit, params.limit);
    }

    function handle_swapExactYtForToken(CalldataItem memory item) private view {
        bytes4 selector = IPActionSwapYTV3.swapExactYtForToken.selector;
        SwapExactYtForToken memory params = item.data.decode_swapExactYtForToken();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.market, address(0), "market");
        assertGt(params.exactYtIn, 0, "minYtOut");
        assertValid(params.output, item, selector);
        // Not checking expected limit details as it may change per query

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        SwapExactYtForToken memory scaledParams = scaledData.decode_swapExactYtForToken();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.market, params.market, "market");
        assertEq(scaledParams.exactYtIn, add5Pct(params.exactYtIn), "exactYtIn");
        assertMatching(scaledParams.output, params.output);
        assertMatching(scaledParams.limit, params.limit);
    }

    function handle_swapExactSyForPt(CalldataItem memory item) private view {
        SwapExactSyForPt memory params = item.data.decode_swapExactSyForPt();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.market, address(0), "market");
        assertEq(params.exactSyIn, item.amountInBN, "exactSyIn");
        assertGt(params.minPtOut, 0, "minPtOut");
        assertValid(params.guessPtOut);
        // Not checking expected limit details as it may change per query

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        SwapExactSyForPt memory scaledParams = scaledData.decode_swapExactSyForPt();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.market, params.market, "market");
        assertEq(scaledParams.exactSyIn, add5Pct(params.exactSyIn), "exactSyIn");
        assertEq(scaledParams.minPtOut, add5Pct(params.minPtOut), "minPtOut");
        assertMatching(scaledParams.guessPtOut, params.guessPtOut);
        assertMatching(scaledParams.limit, params.limit);
    }

    function handle_swapExactPtForSy(CalldataItem memory item) private view {
        SwapExactPtForSy memory params = item.data.decode_swapExactPtForSy();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.market, address(0), "market");
        assertEq(params.exactPtIn, item.amountInBN, "exactPtIn");
        assertGt(params.minSyOut, 0, "minSyOut");
        // Not checking expected limit details as it may change per query

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        SwapExactPtForSy memory scaledParams = scaledData.decode_swapExactPtForSy();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.market, params.market, "market");
        assertEq(scaledParams.exactPtIn, add5Pct(params.exactPtIn), "exactPtIn");
        assertEq(scaledParams.minSyOut, add5Pct(params.minSyOut), "minSyOut");
        assertMatching(scaledParams.limit, params.limit);
    }

    function handle_swapExactSyForYt(CalldataItem memory item) private view {
        SwapExactSyForYt memory params = item.data.decode_swapExactSyForYt();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.market, address(0), "market");
        assertEq(params.exactSyIn, item.amountInBN, "exactSyIn");
        assertGt(params.minYtOut, 0, "minYtOut");
        assertValid(params.guessYtOut);
        // Not checking expected limit details as it may change per query

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        SwapExactSyForYt memory scaledParams = scaledData.decode_swapExactSyForYt();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.market, params.market, "market");
        assertEq(scaledParams.exactSyIn, add5Pct(params.exactSyIn), "exactSyIn");
        assertEq(scaledParams.minYtOut, add5Pct(params.minYtOut), "minYtOut");
        assertMatching(scaledParams.guessYtOut, params.guessYtOut);
        assertMatching(scaledParams.limit, params.limit);
    }

    function handle_swapExactYtForSy(CalldataItem memory item) private view {
        SwapExactYtForSy memory params = item.data.decode_swapExactYtForSy();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.market, address(0), "market");
        assertEq(params.exactYtIn, item.amountInBN, "exactYtIn");
        assertGt(params.minSyOut, 0, "minSyOut");
        // Not checking expected limit details as it may change per query

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        SwapExactYtForSy memory scaledParams = scaledData.decode_swapExactYtForSy();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.market, params.market, "market");
        assertEq(scaledParams.exactYtIn, add5Pct(params.exactYtIn), "exactYtIn");
        assertEq(scaledParams.minSyOut, add5Pct(params.minSyOut), "minSyOut");
        assertMatching(scaledParams.limit, params.limit);
    }

    function handle_redeemSyToToken(CalldataItem memory item) private view {
        bytes4 selector = IPActionMiscV3.redeemSyToToken.selector;
        RedeemSyToToken memory params = item.data.decode_redeemSyToToken();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.SY, address(0), "SY");
        assertEq(params.netSyIn, item.amountInBN, "netSyIn");
        assertValid(params.output, item, selector);

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        RedeemSyToToken memory scaledParams = scaledData.decode_redeemSyToToken();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.SY, params.SY, "SY");
        assertEq(scaledParams.netSyIn, add5Pct(params.netSyIn), "netSyIn");
        assertMatching(scaledParams.output, params.output);
    }

    function handle_mintSyFromToken(CalldataItem memory item) private view {
        bytes4 selector = IPActionMiscV3.mintSyFromToken.selector;
        MintSyFromToken memory params = item.data.decode_mintSyFromToken();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.SY, address(0), "SY");
        assertGt(params.minSyOut, 0, "minSyOut");
        assertValid(params.input, item, selector);

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        MintSyFromToken memory scaledParams = scaledData.decode_mintSyFromToken();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.SY, params.SY, "SY");
        assertEq(scaledParams.minSyOut, add5Pct(params.minSyOut), "minSyOut");
        assertMatching(scaledParams.input, params.input);
    }

    function handle_redeemPyToToken(CalldataItem memory item) private view {
        bytes4 selector = IPActionMiscV3.redeemPyToToken.selector;
        RedeemPyToToken memory params = item.data.decode_redeemPyToToken();

        assertEq(params.receiver, item.from, "receiver");
        assertNotEq(params.YT, address(0), "YT");
        assertEq(params.netPyIn, item.amountInBN, "netPyIn");
        assertValid(params.output, item, selector);

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        RedeemPyToToken memory scaledParams = scaledData.decode_redeemPyToToken();

        assertEq(scaledParams.receiver, params.receiver, "receiver");
        assertEq(scaledParams.YT, params.YT, "YT");
        assertEq(scaledParams.netPyIn, add5Pct(params.netPyIn), "netPyIn");
        assertMatching(scaledParams.output, params.output);
    }

    function handle_callAndReflect(CalldataItem memory item) private view {
        CallAndReflect memory params = item.data.decode_callAndReflect();

        bytes4 selfCall1Selector = bytes4(params.selfCall1);
        bytes memory scaledSelfCall1;
        {
            assertEq(params.reflector, PENDLE_REFLECTOR);
            assertGt(params.selfCall1.length, 0, "selfCall1 length");

            // Need to check the inner call
            if (selfCall1Selector == IPActionSwapPTV3.swapExactPtForToken.selector) {
                CalldataItem memory innerItem;
                innerItem.from = PENDLE_REFLECTOR;
                innerItem.amountInBN = item.amountInBN;
                innerItem.data = params.selfCall1;
                innerItem.tokenOutAddr = underlyingTokenOfPt(item.tokenInAddr);
                scaledSelfCall1 = handle_swapExactPtForToken(innerItem);
            } else {
                revert UnhandledCallAndReflectFunction(selfCall1Selector);
            }

            assertEq(params.selfCall2.length, 0, "selfCall2 length"); // not used in these examples yet
            assertGt(params.reflectCall.length, 0, "reflectCall length");
        }

        // Add 5% to the sell amount, and verify only the two fields have changed (by the same 5%)
        bytes memory scaledData = scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
        CallAndReflect memory scaledParams = scaledData.decode_callAndReflect();

        assertEq(scaledParams.reflector, params.reflector, "scaled reflector");
        assertEq(scaledParams.selfCall1, scaledSelfCall1, "scaled selfCall1");
        assertEq(scaledParams.selfCall2, params.selfCall2, "scaled selfCall2");
        assertEq(scaledParams.reflectCall, params.reflectCall, "scaled reflectCall");
    }

    function handle_swapTokensToTokens(CalldataItem memory item) private {
        bytes4 selector = IPActionMiscV3.swapTokensToTokens.selector;
        SwapTokensToTokens memory params = item.data.decode_swapTokensToTokens();

        assertEq(address(params.pendleSwap), PENDLE_SWAP, "pendleSwap");
        assertEq(params.swaps.length, 1, "swaps.length");
        assertEq(params.swaps[0].tokenIn, item.tokenInAddr, "swaps[0].tokenIn");
        assertEq(params.swaps[0].tokenOut, item.tokenOutAddr, "swaps[0].tokenOut");
        assertGt(params.swaps[0].minOut, 0, "swaps[0].minOut");
        assertValid(params.swaps[0].swapData, selector);
        assertEq(params.netSwaps.length, 1, "netSwaps.length");
        assertEq(params.netSwaps[0], item.amountInBN, "netSwaps[0]");

        // The scaling lib can't handle this, because the underlying Pendle Router hardcodes
        // `needScale` to false
        vm.expectRevert(abi.encodeWithSelector(PendleRouterScalingLib.UnsupportedSelector.selector, selector));
        scaler.scaleCalldata(add5Pct(item.amountInBN), item.data);
    }
}
