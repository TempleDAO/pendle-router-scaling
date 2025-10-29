// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {stdError} from "forge-std/StdError.sol";

import {PendleRouterScalingLib} from "src/PendleRouterScalingLib.sol";
import {TestBase} from "test/TestBase.sol";

// Contract to perform the swaps - electing to scale to the current balance of the src token or not.
contract PendleRouterSwapBalance {
    using SafeERC20 for IERC20;

    error UnknownRouter(address router);

    address public immutable PENDLE_ROUTER_V4;

    constructor(address _pendleRouter) {
        PENDLE_ROUTER_V4 = _pendleRouter;
    }

    /// @notice Do the swap as is - no scaling
    function swap(address to, address srcToken, bytes memory callData) external {
        _callRouter(to, IERC20(srcToken), callData);
    }

    /// @notice First scale the calldata by the srcToken balance in this contract
    function swapBalance(address to, address srcToken, bytes memory callData) external {
        IERC20 _srcToken = IERC20(srcToken);

        // Scale the calldata by the current balance of srcToken
        uint256 newSrcAmount = _srcToken.balanceOf(address(this));

        // Nothing to do - it is left to the remainder of the bundle steps to check for min amounts
        if (newSrcAmount == 0) return;

        PendleRouterScalingLib.scaleCalldata(newSrcAmount, callData);

        _callRouter(to, _srcToken, callData);
    }

    /// @notice View to scale callData
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

    function _callRouter(address to, IERC20 srcToken, bytes memory callData) internal {
        if (to != PENDLE_ROUTER_V4) revert UnknownRouter(to);

        // Max approve the token -- the router is trusted, so doesnt need to be reset
        if (srcToken.allowance(address(this), PENDLE_ROUTER_V4) < type(uint256).max) {
            srcToken.forceApprove(PENDLE_ROUTER_V4, type(uint256).max);
        }

        (bool success, bytes memory returnData) = PENDLE_ROUTER_V4.call(callData);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(0x20, returnData), mload(returnData))
            }
        }
    }
}

contract PendleRouterScalingLibForkTest is TestBase {
    PendleRouterSwapBalance public balanceRouter;

    address receiver;

    // Got more than expected
    uint256 public constant TOLERANCE_MORE = 0.05e18; // 5%
    
    // Got less than expected
    uint256 public constant TOLERANCE_LESS = 0.025e18; // 2.5%
    
    function setUp() public {
        CalldataItem[] memory testItems = loadTestItems();
        
        // Use the min blockNumber as the fork
        CalldataItem memory item;
        uint256 forkBlockNumber = type(uint256).max;
        for (uint256 i; i < testItems.length; ++i) {
            item = testItems[i];
            if (item.blockNumber < forkBlockNumber) {
                forkBlockNumber = item.blockNumber;
            }

            if (receiver == address(0)) {
                receiver = item.from;
            } else if (receiver != item.from) {
                revert("All test cases need the same 'from'");
            }
        }
    }

    function etchRouter() internal {
        // Etch the router onto the receiver address that was used when generating the test cases
        PendleRouterSwapBalance br = new PendleRouterSwapBalance(PENDLE_ROUTER_V4);
        vm.etch(receiver, address(br).code);
        balanceRouter = PendleRouterSwapBalance(receiver);
    }

    // No change to calldata, deal existing amounts
    function test_swap_as_is() public {
        CalldataItem[] memory testItems = loadTestItems();

        for (uint256 i; i < testItems.length; ++i) {
            CalldataItem memory item = testItems[i];
            fork("mainnet", item.blockNumber);
            etchRouter();

            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal exact tokens and call swap. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = item.amountInBN;
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(balanceRouter), 0);


            balanceRouter.swap(item.to, item.tokenInAddr, item.data);

            assertEq(IERC20(item.tokenInAddr).balanceOf(address(balanceRouter)), dealtAmount-item.amountInBN);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(balanceRouter));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_LESS, itemKey);
            }
        }
    }

    // No change to calldata, deal an extra 5% which is just left over in the contract and not
    // used by the pendle router
    function test_swap_with_extra() public {
        CalldataItem[] memory testItems = loadTestItems();

        for (uint256 i; i < testItems.length; ++i) {
            CalldataItem memory item = testItems[i];
            fork("mainnet", item.blockNumber);
            etchRouter();
            
            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal an extra 5% of tokens and call swap. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = add5Pct(item.amountInBN);
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(balanceRouter), 0);

            balanceRouter.swap(item.to, item.tokenInAddr, item.data);

            assertEq(IERC20(item.tokenInAddr).balanceOf(address(balanceRouter)), dealtAmount-item.amountInBN);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(balanceRouter));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_LESS, itemKey);
            }
        }
    }

    // No change to calldata, deal an extra 5% which is just left over in the contract and not
    // used by the pendle router
    function test_swapBalance_as_is() public {
        CalldataItem[] memory testItems = loadTestItems();

        for (uint256 i; i < testItems.length; ++i) {
            CalldataItem memory item = testItems[i];
            fork("mainnet", item.blockNumber);
            etchRouter();

            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal exact tokens and call swap. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = item.amountInBN;
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(balanceRouter), 0);

            if (isUnsupported(bytes4(item.data))) {
                vm.expectRevert(
                    abi.encodeWithSelector(PendleRouterScalingLib.UnsupportedSelector.selector, bytes4(item.data))
                );
                balanceRouter.swapBalance(item.to, item.tokenInAddr, item.data);
                continue;
            }

            balanceRouter.swapBalance(item.to, item.tokenInAddr, item.data);
            assertEq(IERC20(item.tokenInAddr).balanceOf(address(balanceRouter)), dealtAmount-item.amountInBN);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(balanceRouter));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_LESS, itemKey);
            }
        }
    }

    // With scaled calldata, deal an extra 5% which is all used and we get more output tokens
    function test_swapBalance_with_extra() public {
        CalldataItem[] memory testItems = loadTestItems();

        // We get an extra amount of output tokens when we deal extra
        uint256 _TOLERANCE_MORE = 0.08e18;

        for (uint256 i; i < testItems.length; ++i) {
            CalldataItem memory item = testItems[i];
            fork("mainnet", item.blockNumber);
            etchRouter();

            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal an extra 5% of tokens and call swap. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = add5Pct(item.amountInBN);
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(balanceRouter), 0);

            if (isUnsupported(bytes4(item.data))) {
                vm.expectRevert(
                    abi.encodeWithSelector(PendleRouterScalingLib.UnsupportedSelector.selector, bytes4(item.data))
                );
                balanceRouter.swapBalance(item.to, item.tokenInAddr, item.data);
                continue;
            }

            balanceRouter.swapBalance(item.to, item.tokenInAddr, item.data);
            assertEq(IERC20(item.tokenInAddr).balanceOf(address(balanceRouter)), 0);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(balanceRouter));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, _TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_LESS, itemKey);
            }
        }
    }

    // With scaled calldata, deal an extra 5% which is all used and we get more output tokens
    function test_swapBalance_with_less() public {
        CalldataItem[] memory testItems = loadTestItems();

        // We get LESS amount of output tokens when we dont deal as much
        uint256 _TOLERANCE_LESS = 0.04e18;

        for (uint256 i; i < testItems.length; ++i) {
            CalldataItem memory item = testItems[i];
            fork("mainnet", item.blockNumber);
            etchRouter();

            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal an extra 5% of tokens and call swap. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = sub2Pct(item.amountInBN);
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(balanceRouter), 0);

            if (isUnsupported(bytes4(item.data))) {
                vm.expectRevert(
                    abi.encodeWithSelector(PendleRouterScalingLib.UnsupportedSelector.selector, bytes4(item.data))
                );
                balanceRouter.swapBalance(item.to, item.tokenInAddr, item.data);
                continue;
            } else if (needsScaleNotSet(bytes4(item.data))) {
                vm.expectRevert("TransferHelper: TRANSFER_FROM_FAILED");
                balanceRouter.swapBalance(item.to, item.tokenInAddr, item.data);
                continue;
            }

            balanceRouter.swapBalance(item.to, item.tokenInAddr, item.data);
            assertEq(IERC20(item.tokenInAddr).balanceOf(address(balanceRouter)), 0);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(balanceRouter));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, _TOLERANCE_LESS, itemKey);
            }
        }
    }
}