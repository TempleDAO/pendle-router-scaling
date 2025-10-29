# <h1 align="center"> Pendle Router Scaling Helper </h1>

**For modifying the effective amount in on-chain**

![Github Actions](https://github.com/TempleDAO/pendle-router-scaling/workflows/CI/badge.svg)

## The Pendle Router Contract

The [PendleRouterV4](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/router/PendleRouterV4.sol#L8C10-L8C24) manages conversions to and from tokens. It can handle both Pendle PT/YT tokens as well as external swaps via DEX Aggregators (eg KyberSwap/OKX/ODOS/Paraswap)

The available functions on the router are registered via their governance, but are typically found in these places:

* [IPActionSwapPTV3.sol - PT Actions](https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/interfaces/IPActionSwapPTV3.sol)
* [IPActionSwapYTV3.sol - YT Actions](https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/interfaces/IPActionSwapYTV3.sol)
* [IPActionMiscV3.sol - Other Misc Actions](https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/interfaces/IPActionMiscV3.sol)

The normal flow for integrations is:

1. Generate calldata via [/convert](https://api-v2.pendle.finance/core/docs#/SDK/SdkController_convert) on the Pendle API v2
2. Perform a low level call on the Pendle Router with that generated calldata

Internally within the Pendle router, some of the multi-step actions can 'scale' to the full balance received. Eg if you swap from USDC->USDe then mint PT with the USDe, it can use the entire balance of the USDe.

However it cannot natively scale the initial calldata. Integrations may only know the amount of the first sell token onchain as a result of other actions.

This requires 'scaling' the input calldata to a target amount first. Kyber has an equivalent contract and explains the [same issue here](https://docs.kyberswap.com/kyberswap-solutions/kyberswap-aggregator/developer-guides/scaling-swap-calldata-with-scalehelper)

## PendleRouterScalingLib

This library provides a `scaleCalldata()` function to perform this scaling on known functions which can be mapped.

The scaling updates two parameters within the function arguments:

* Token Amount In: Will be updated to the new required value
* Min Token Amount Out: Will be scaled by the proportional `ΔToken Amount In`

Only the following Pendle Router functions are supported:

* [IPActionMiscV3.redeemSyToToken](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionMiscV3.sol#L29)
* [IPActionMiscV3.mintSyFromToken](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionMiscV3.sol#L22)
* [IPActionMiscV3.redeemPyToToken](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionMiscV3.sol#L43)
* [IPActionSwapPTV3.swapExactTokenForPt](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionSwapPTV3.sol#L10)
* [IPActionSwapPTV3.swapExactPtForToken](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionSwapPTV3.sol#L28)
* [IPActionSwapPTV3.swapExactSyForPt](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionSwapPTV3.sol#L19)
* [IPActionSwapPTV3.swapExactPtForSy](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionSwapPTV3.sol#L36)
* [IPActionSwapYTV3.swapExactTokenForYt](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionSwapYTV3.sol#L10)
* [IPActionSwapYTV3.swapExactYtForToken](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionSwapYTV3.sol#L28)
* [IPActionSwapYTV3.swapExactSyForYt](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionSwapYTV3.sol#L19)
* [IPActionSwapYTV3.swapExactYtForSy](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionSwapYTV3.sol#L36)

As well as [IPActionMiscV3.callAndReflect](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/contracts/interfaces/IPActionMiscV3.sol#L129) which is a composite call - it performs 2 chained router steps:

1. First calls a router function
2. Calls the next router function but using the scaled output after the first is done.

If called for any other function selector, it will revert with:

```solidity
error UnsupportedSelector(bytes4 selector);
```

The implementation is gas efficient - there are no unnecessary memory copies or abi encoding/decoding. It utilizes the known offsets of the required parameters to be updated. Careful inspection has been done to ensure its not relying on any dynamic offset positions.

## Known Issues

The current implementation doesn't work with these functions:

1. `mintSyFromToken`: The Pendle API v2 `/convert` does not respect the `needScale` argument when passed in. It leaves it in the calldata as false, meaning internal swaps dont get scaled correctly. Pendle need to correct this in their API, or we make the contract less efficient. 
   1. Right now it doesn't do a full abi.encode/decode as that's quite gas intensive. However the `input.swap.needsScale` is _after_ dynamic sized bytes -- so it's more complicated to update the bytes in place (deriving the offset is harder, or we do a full decode then encode)
   2. It is unlikely we'll need this function though - so elected to skip fixing it
2. `swapTokensToTokens`: Pendle provide an 'aggregator of aggregators' much like [https://swap.defillama.com/](https://swap.defillama.com/). So you can swap from one token to any others and they scale the input. However when called via the `/convert` API, the `swapTokensToTokens` hardcodes `needsScale=false`
   1. If required, the caller would need to implement this themselves from first principles - Pendle confirmed they wont update this.

## Tests

The tests run over multiple combinations of responses from the Pendle API v2 `/convert` endpoint.

You can see the current test cases in [test/calldata.json](./test/calldata.json)

This this test case file is parsed by Foundry tests - which is why the fields are numbers as Foundry needs them to be in a set alphabetic order mapping to the [CalldataItem struct](https://github.com/TempleDAO/pendle-router-scaling/blob/main/test/PendleRouterScalingLib.t.sol#L44)

The calldata input is:

1. deserialized into the expected function parameters
2. The 'as is values' are validated with some rough heuristics to make sure it deserialized ok
3. The `Token Amount In` is then scaled by 5% via the library
4. The output is deserialized and checked vs (1).
   1. Only the `Token Amount In` and `Min Token Amount Out` should change.

If test cases need to be added or re-run (in case the API changes expected routing) then run via:

```bash
./test/queryApi.sh
```

## Pendle Deployments

Can be [found here](https://github.com/pendle-finance/pendle-core-v2-public/blob/8240517c021c5a14e309691bd01fb326e93dea64/deployments) for the required chain.
