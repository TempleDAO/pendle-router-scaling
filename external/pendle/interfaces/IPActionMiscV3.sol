// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IPAllActionTypeV3.sol";
import {SwapDataExtra, IPSwapAggregator} from "../router/swap-aggregator/IPSwapAggregator.sol";

/// Refer to IPAllActionTypeV3.sol for details on the parameters
interface IPActionMiscV3 {
    function mintSyFromToken(
        address receiver,
        address SY,
        uint256 minSyOut,
        TokenInput calldata input
    ) external payable returns (uint256 netSyOut);

    function redeemSyToToken(
        address receiver,
        address SY,
        uint256 netSyIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut);

    function redeemPyToToken(
        address receiver,
        address YT,
        uint256 netPyIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyInterm);

    function swapTokensToTokens(
        IPSwapAggregator pendleSwap,
        SwapDataExtra[] calldata swaps,
        uint256[] calldata netSwaps
    ) external payable returns (uint256[] memory netOutFromSwaps);

    function callAndReflect(
        address payable reflector,
        bytes calldata selfCall1,
        bytes calldata selfCall2,
        bytes calldata reflectCall
    ) external payable returns (bytes memory selfRes1, bytes memory selfRes2, bytes memory reflectRes);
}
