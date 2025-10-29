// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test, StdChains} from "forge-std/Test.sol";
import {Order} from "pendle-core-v2-public/contracts/interfaces/IPLimitRouter.sol";
import {
    ApproxParams,
    TokenInput,
    TokenOutput,
    LimitOrderData
} from "pendle-core-v2-public/contracts/interfaces/IPAllActionTypeV3.sol";
import {SwapData} from "pendle-core-v2-public/contracts/router/swap-aggregator/IPSwapAggregator.sol";
import {IPActionMiscV3} from "pendle-core-v2-public/contracts/interfaces/IPActionMiscV3.sol";

contract TestBase is Test {
    error UnhandledFunction(string functionName);
    error UnhandledCallAndReflectFunction(bytes4 selector);

    struct CalldataItem {
        string tokenIn;
        string tokenOut;
        address tokenInAddr;
        address tokenOutAddr;
        string amountInFP;
        string amountOutFP;
        uint256 amountInBN;
        uint256 amountOutBN;
        string action;
        string method;
        string url;
        uint256 blockNumber;
        bytes data;
        address to;
        address from;
    }

    // Eth Mainnet contract addresses
    address public constant PENDLE_ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address public constant PENDLE_SWAP = 0xd4F480965D2347d421F1bEC7F545682E5Ec2151D;
    address public constant PENDLE_REFLECTOR = 0x73d5DBF81A4f3bFa7b335e6a2d4638D6017a4fA8;
    address public constant KYBER_ROUTER_V2 = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;
    address public constant RECEIVER = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28;
    address public constant USDC_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant SUSDE_TOKEN = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant USDE_TOKEN = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address public constant PT_SUSDE_NOV25_TOKEN = 0xe6A934089BBEe34F832060CE98848359883749B3;
    address public constant PENDLE_SUSDE_NOV25_MARKET = 0xb6aC3d5da138918aC4E84441e924a20daA60dBdd;
    address public constant PT_USDE_NOV25_TOKEN = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;

    uint256 internal forkId;
    uint256 internal blockNumber;
    StdChains.Chain internal chain;

    // Fork using .env $<CHAIN_ALIAS>_RPC_URL (or the default RPC URL), and a specified blockNumber.
    function fork(string memory chainAlias, uint256 _blockNumber) internal {
        blockNumber = _blockNumber;
        chain = getChain(chainAlias);
        try vm.createSelectFork(chain.rpcUrl, _blockNumber) returns (uint256 _forkId) {
            // worked ok
            forkId = _forkId;
        } catch {
            // Try one more time - sometimes there's transient network issues depending on connection
            forkId = vm.createSelectFork(chain.rpcUrl, _blockNumber);
        }
    }

    function loadTestItems() internal view returns (CalldataItem[] memory items) {
        string memory path = string.concat(vm.projectRoot(), "/test/calldata.json");
        string memory rawJson = vm.readFile(path);
        bytes memory data = vm.parseJson(rawJson);
        return abi.decode(data, (CalldataItem[]));
    }

    function isUnsupported(bytes4 selector) internal pure returns (bool) {
        return selector == IPActionMiscV3.swapTokensToTokens.selector;
    }

    function needsScaleNotSet(bytes4 selector) internal pure returns (bool) {
        return selector == IPActionMiscV3.mintSyFromToken.selector;
    }

    function add5Pct(uint256 amount) internal pure returns (uint256) {
        return amount * 1.05e18 / 1e18;
    }

    function sub2Pct(uint256 amount) internal pure returns (uint256) {
        return amount * 0.98e18 / 1e18;
    }


    function isEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function underlyingTokenOfPt(address ptToken) internal pure returns (address) {
        if (ptToken == PT_USDE_NOV25_TOKEN) return USDE_TOKEN;
        if (ptToken == PT_SUSDE_NOV25_TOKEN) return SUSDE_TOKEN;
        return address(0);
    }

    function assertMatching(LimitOrderData memory a, LimitOrderData memory b) internal pure {
        assertEq(a.limitRouter, b.limitRouter, "limit.limitRouter");
        assertEq(a.epsSkipMarket, b.epsSkipMarket, "limit.epsSkipMarket");
        assertEq(a.normalFills.length, b.normalFills.length, "limit.normalFills");
        for (uint256 i; i < a.normalFills.length; ++i) {
            assertMatching(a.normalFills[i].order, b.normalFills[i].order);
            assertEq(a.normalFills[i].signature, b.normalFills[i].signature, "limit.normalFills.signature");
            assertEq(a.normalFills[i].makingAmount, b.normalFills[i].makingAmount, "limit.normalFills.makingAmount");
        }
        assertEq(a.flashFills.length, b.flashFills.length, "limit.flashFills");
        for (uint256 i; i < a.flashFills.length; ++i) {
            assertMatching(a.flashFills[i].order, b.flashFills[i].order);
            assertEq(a.flashFills[i].signature, b.flashFills[i].signature, "limit.flashFills.signature");
            assertEq(a.flashFills[i].makingAmount, b.flashFills[i].makingAmount, "limit.flashFills.makingAmount");
        }
        assertEq(a.optData, b.optData, "limit.optData");
    }

    function assertMatching(Order memory a, Order memory b) internal pure {
        assertEq(a.salt, b.salt, "order.salt");
        assertEq(a.expiry, b.expiry, "order.expiry");
        assertEq(a.nonce, b.nonce, "order.nonce");
        assertEq(uint16(a.orderType), uint16(b.orderType), "order.orderType");
        assertEq(a.token, b.token, "order.token");
        assertEq(a.YT, b.YT, "order.YT");
        assertEq(a.maker, b.maker, "order.maker");
        assertEq(a.receiver, b.receiver, "order.receiver");
        assertEq(a.makingAmount, b.makingAmount, "order.makingAmount");
        assertEq(a.lnImpliedRate, b.lnImpliedRate, "order.lnImpliedRate");
        assertEq(a.failSafeRate, b.failSafeRate, "order.failSafeRate");
        assertEq(a.permit, b.permit, "order.permit");
    }

    function assertMatching(SwapData memory a, SwapData memory b) internal pure {
        assertEq(uint16(a.swapType), uint16(b.swapType), "matching swapData.swapType");
        assertEq(a.extRouter, b.extRouter, "matching swapData.extRouter");
        assertEq(a.extCalldata, b.extCalldata, "matching swapData.extCalldata");
        assertEq(a.needScale, b.needScale, "matching swapData.needScale");
    }

    // Note this checks for an extra 5% on the netTokenIn
    function assertMatching(TokenInput memory a, TokenInput memory b) internal pure {
        assertEq(a.tokenIn, b.tokenIn, "matching input.tokenIn");
        assertEq(a.netTokenIn, add5Pct(b.netTokenIn), "matching input.netTokenIn");
        assertEq(a.tokenMintSy, b.tokenMintSy, "matching input.tokenMintSy");
        assertEq(a.pendleSwap, b.pendleSwap, "matching input.pendleSwap");
        assertMatching(a.swapData, b.swapData);
    }

    // Note this checks for an extra 5% on the minTokenOut
    function assertMatching(TokenOutput memory a, TokenOutput memory b) internal pure {
        assertEq(a.tokenOut, b.tokenOut, "matching output.tokenOut");
        assertEq(a.minTokenOut, add5Pct(b.minTokenOut), "matching output.minTokenOut");
        assertEq(a.tokenRedeemSy, b.tokenRedeemSy, "matching output.tokenRedeemSy");
        assertEq(a.pendleSwap, b.pendleSwap, "matching output.pendleSwap");
        assertMatching(a.swapData, b.swapData);
    }

    function assertMatching(ApproxParams memory a, ApproxParams memory b) internal pure {
        assertEq(a.guessMin, b.guessMin, "matching approxParams.guessMin");
        assertEq(a.guessMax, b.guessMax, "matching approxParams.guessMax");
        assertEq(a.guessOffchain, b.guessOffchain, "matching approxParams.guessOffchain");
        assertEq(a.maxIteration, b.maxIteration, "matching approxParams.maxIteration");
        assertEq(a.eps, b.eps, "matching approxParams.eps");
    }
}
