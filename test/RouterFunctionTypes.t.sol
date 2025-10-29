// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {
    ApproxParams,
    TokenInput,
    TokenOutput,
    LimitOrderData
} from "pendle-core-v2-public/contracts/interfaces/IPAllActionTypeV3.sol";
import {
    IPSwapAggregator,
    SwapDataExtra
} from "pendle-core-v2-public/contracts/router/swap-aggregator/IPSwapAggregator.sol";

struct SwapExactTokenForPt {
    address receiver;
    address market;
    uint256 minPtOut;
    ApproxParams guessPtOut;
    TokenInput input;
    LimitOrderData limit;
}

struct SwapExactPtForToken {
    address receiver;
    address market;
    uint256 exactPtIn;
    TokenOutput output;
    LimitOrderData limit;
}

struct SwapExactTokenForYt {
    address receiver;
    address market;
    uint256 minYtOut;
    ApproxParams guessYtOut;
    TokenInput input;
    LimitOrderData limit;
}

struct SwapExactYtForToken {
    address receiver;
    address market;
    uint256 exactYtIn;
    TokenOutput output;
    LimitOrderData limit;
}

struct SwapExactSyForPt {
    address receiver;
    address market;
    uint256 exactSyIn;
    uint256 minPtOut;
    ApproxParams guessPtOut;
    LimitOrderData limit;
}

struct SwapExactPtForSy {
    address receiver;
    address market;
    uint256 exactPtIn;
    uint256 minSyOut;
    LimitOrderData limit;
}

struct SwapExactSyForYt {
    address receiver;
    address market;
    uint256 exactSyIn;
    uint256 minYtOut;
    ApproxParams guessYtOut;
    LimitOrderData limit;
}

struct SwapExactYtForSy {
    address receiver;
    address market;
    uint256 exactYtIn;
    uint256 minSyOut;
    LimitOrderData limit;
}

struct RedeemSyToToken {
    address receiver;
    address SY;
    uint256 netSyIn;
    TokenOutput output;
}

struct MintSyFromToken {
    address receiver;
    address SY;
    uint256 minSyOut;
    TokenInput input;
}

struct CallAndReflect {
    address payable reflector;
    bytes selfCall1;
    bytes selfCall2;
    bytes reflectCall;
}

struct RedeemPyToToken {
    address receiver;
    address YT;
    uint256 netPyIn;
    TokenOutput output;
}

struct SwapTokensToTokens {
    IPSwapAggregator pendleSwap;
    SwapDataExtra[] swaps;
    uint256[] netSwaps;
}
