#!env /bin/bash
set -euo pipefail

USDC_TOKEN="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
SUSDE_TOKEN="0x9D39A5DE30e57443BfF2A8307A4256c8797A3497"
USDE_TOKEN="0x4c9EDD5852cd905f086C759E8383e09bff1E68B3"
PT_SUSDE_NOV25_TOKEN="0xe6A934089BBEe34F832060CE98848359883749B3"
YT_SUSDE_NOV25_TOKEN="0x28e626b560f1faac01544770425e2de8fd179c79"
SY_SUSDE_NOV25_TOKEN="0xabf8165dd7a90ab75878161db15bf85f6f781d9b"
PT_USDE_NOV25_TOKEN="0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7"
PT_SUSDE_SEP25_TOKEN="0x9f56094c450763769ba0ea9fe2876070c0fd5f77"
RECEIVER="0x8EB8a3b98659Cce290402893d0123abb75E3ab28"

# Set to something quite high. In practice we check slippage
# at the end of a bundle not at each step.
# But we need to check its scaled correctly.
SLIPPAGE="0.2"

# KYBER REQUESTS:
# for 'mintSyFromToken' - it should respect the needScale passed in

# Need to split up by a sleep so we dont get rate limited
declare -a conversions=(
  'sUSDe 10000 PT_sUSDe_Nov' # swap - swapExactTokenForPt
  'PT_sUSDe_Nov 10000 sUSDe' # swap - swapExactPtForToken
  'sUSDe 10000 YT_sUSDe_Nov' # swap - swapExactTokenForYt
  'YT_sUSDe_Nov 10000 sUSDe' # swap - swapExactYtForToken
  'USDC 10000 PT_USDe_Nov' # swap - swapExactTokenForPt
  'PT_USDe_Nov 10000 USDC' # swap - swapExactPtForToken
  'USDC 10000 YT_sUSDe_Nov' # swap - swapExactTokenForYt
  'YT_sUSDe_Nov 10000 USDC' # swap - swapExactYtForToken
  'SY_sUSDe_Nov 10000 PT_sUSDe_Nov' # swap - swapExactSyForPt
  'PT_sUSDe_Nov 10000 SY_sUSDe_Nov' # swap - swapExactPtForSy
  'SY_sUSDe_Nov 10000 YT_sUSDe_Nov' # swap - swapExactSyForYt
  'YT_sUSDe_Nov 10000 SY_sUSDe_Nov' # swap - swapExactYtForSy
  ## 'PT_sUSDe_Nov 10000 YT_sUSDe_Nov' # Pendle aggregator cant route this
  ## 'YT_sUSDe_Nov 10000 PT_sUSDe_Nov' # Pendle aggregator cant route this
  'SY_sUSDe_Nov 10000 USDC' # redeem-sy - redeemSyToToken
  'USDC 10000 SY_sUSDe_Nov' # mint-sy - mintSyFromToken
  'PT_USDe_Nov 10000 PT_sUSDe_Nov' # roll-over-pt - callAndReflect
  'PT_sUSDe_Nov 10000 PT_USDe_Nov' # roll-over-pt - callAndReflect
  'USDC 10000 sUSDe' # pendle-swap - swapTokensToTokens
  'sUSDe 10000 USDC' # pendle-swap - swapTokensToTokens
  # Expired market exit
  'PT_sUSDe_Sep 10000 sUSDe' # (redeem-py - redeemPyToToken)
  'PT_sUSDe_Sep 10000 USDe' #  (redeem-py - redeemPyToToken)
  'PT_sUSDe_Sep 10000 USDC' #  (redeem-py - redeemPyToToken)
  ## sUSDe 10000 PT_sUSDe_Sep'  NOT POSSIBLE BECAUSE ITS EXPIRED
)

tokenAddr() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    usdc) echo $USDC_TOKEN ;;
    susde) echo $SUSDE_TOKEN ;;
    usde) echo $USDE_TOKEN ;;
    "pt_susde_nov") echo $PT_SUSDE_NOV25_TOKEN ;;
    "yt_susde_nov") echo $YT_SUSDE_NOV25_TOKEN ;;
    "sy_susde_nov") echo $SY_SUSDE_NOV25_TOKEN ;;
    "pt_usde_nov") echo $PT_USDE_NOV25_TOKEN ;;
    "pt_susde_sep") echo $PT_SUSDE_SEP25_TOKEN ;;
    *) echo "$1" ;;
  esac
}

# Could get this via cast if needed
decimals() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    usdc) echo "6" ;;
    *) echo "18" ;;
  esac
}

curl_with_retry() {
  local url="$1"
  local max_retries="${2:-6}"   # default: 6 attempts
  local base_sleep="${3:-1}"    # seconds, base for backoff

  local attempt=0 code hdr_file body_file retry_after sleep_s jitter response

  while (( attempt < max_retries )); do
    hdr_file="$(mktemp)"
    body_file="$(mktemp)"

    # -sS = silent but show errors
    # -D = write headers to file
    # -o = write body to file
    # -w = print HTTP status to stdout
    # --connect-timeout 5 = max 5 seconds to establish connection
    # --max-time 15 = total request timeout (connect + response)
    code="$(
      curl -sS -D "$hdr_file" -o "$body_file" -w '%{http_code}' \
        --connect-timeout 5 \
        --max-time 15 \
        "$url" || echo 000
    )"

    response="$(cat "$body_file")"

    # Success
    if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
      echo "$response"
      rm -f "$hdr_file" "$body_file"
      return 0
    fi

    # Retry on transient codes: 429, 5xx, or curl error (000)
    if [[ "$code" == 429 || "$code" == 400 || "$code" =~ ^5[0-9][0-9]$ || "$code" == 000 ]]; then
      ((attempt++))

      # Check for Retry-After header
      retry_after="$(awk -F': ' 'BEGIN{IGNORECASE=1} /^Retry-After:/ {print $2; exit}' "$hdr_file" | tr -d '\r')"
      if [[ "$retry_after" =~ ^[0-9]+$ ]]; then
        sleep_s="$retry_after"
      else
        sleep_s=$(( base_sleep * (2 ** (attempt - 1)) ))
      fi

      # Add jitter (0–1s)
      jitter_ms=$(( RANDOM % 1000 ))
      sleep_time=$(awk -v s="$sleep_s" -v j="$jitter_ms" 'BEGIN { printf "%.3f", s + (j/1000.0) }')

      echo "⏳ Retry $attempt/$max_retries after ${sleep_time}s (status $code) (body $response)" >&2
      sleep "$sleep_time"

      rm -f "$hdr_file" "$body_file"
      continue
    fi

    # Non-retryable code (4xx other than 429)
    rm -f "$hdr_file" "$body_file"
    return 1
  done

  echo "❌ Failed after $max_retries attempts" >&2
  return 1
}


# Function to call Pendle convert API
convertUrl() {
  local tokensIn="$1"
  local amountInBN="$2"
  local tokensOut="$3"

  echo "https://api-v2.pendle.finance/core/v2/sdk/1/convert?\
tokensIn=${tokensIn}&\
amountsIn=${amountInBN}&\
tokensOut=${tokensOut}&\
receiver=${RECEIVER}&\
slippage=${SLIPPAGE}&\
enableAggregator=true&\
aggregators=kyberswap&\
needScale=true"
}

convert() {
  local tokensIn="$1"
  local amountInFP="$2"
  local tokensOut="$3"

  local amountInBigNum=$(cast from-fixed-point $(decimals $tokensIn) "$amountInFP")
  local tokenInAddr=$(tokenAddr "$tokensIn")
  local tokenOutAddr=$(tokenAddr "$tokensOut")
  local url=$(convertUrl $tokenInAddr "$amountInBigNum" $tokenOutAddr)

  # Retry 5 times, start with a 15 second gap (it's not very forgiving)
  local response=$(curl_with_retry "$url" 5 15) || {
    echo '❌ Request failed for "$url"' >&2
    exit 1
  }

  local amountOutBigNum=$(echo $response | jq -r ".routes[0].outputs[].amount")
  local method=$(echo $response | jq -r ".routes[0].contractParamInfo.method")
  local action=$(echo $response | jq -r ".action")
  local amountOutFP=$(cast to-fixed-point $(decimals $tokensOut) $amountOutBigNum)
  local blockNumber=$(cast block-number --rpc-url $MAINNET_RPC_URL)
  local data=$(echo $response | jq -r ".routes[0].tx.data")
  local to=$(echo $response | jq -r ".routes[0].tx.to")
  local from=$(echo $response | jq -r ".routes[0].tx.from")

  # Note: Foundry requires it to be in alphabetical order for how we read it back in
  # https://getfoundry.sh/reference/cheatcodes/parse-json/#decoding-json-objects-into-solidity-structs
  # So we prefix with numbers
  # `--argjson` means it's unquoted. Required for bigints when parsed by foundry
  echo $response | jq \
    --arg tokenIn "$tokensIn" \
    --arg tokenOut "$tokensOut" \
    --arg tokenInAddr "$tokenInAddr" \
    --arg tokenOutAddr "$tokenOutAddr" \
    --arg amountInFP "$amountInFP" \
    --arg amountOutFP "$amountOutFP" \
    --argjson amountInBigNum "$amountInBigNum" \
    --argjson amountOutBigNum "$amountOutBigNum" \
    --arg action "$action" \
    --arg method "$method" \
    --arg url "$url" \
    --argjson blockNumber "$blockNumber" \
    --arg data "$data" \
    --arg to "$to" \
    --arg from "$from" \
    -r '
      {
        "00_tokenIn": $tokenIn,
        "01_tokenOut": $tokenOut,
        "02_tokenInAddr": $tokenInAddr,
        "03_tokenOutAddr": $tokenOutAddr,
        "04_amountInFP": $amountInFP,
        "05_amountOutFP": $amountOutFP,
        "06_amountInBN": $amountInBigNum,
        "07_amountOutBN": $amountOutBigNum,
        "08_action": $action,
        "09_method": $method,
        "10_url": $url,
        "11_blockNumber": $blockNumber,
        "12_data": $data,
        "13_to": $to,
        "14_from": $from
      }'
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_file="$SCRIPT_DIR/calldata.json"

combined='[]'

# Comment out to append only
echo "$combined" > "$output_file"

for c in "${conversions[@]}"; do
  echo "querying $c"
  item=$(convert $c)
  combined=$(jq --argjson item "$item" '. + [$item]' <<<"$combined")
  echo "$combined" | jq . > "$output_file"
  echo "✅ Updated $output_file with new item ($(jq length <<<"$combined") total)"
done
