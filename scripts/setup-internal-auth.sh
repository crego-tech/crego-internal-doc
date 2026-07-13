#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# setup-internal-auth.sh
# One-time (idempotent) setup of HTTP Basic Auth for /internal/* on the
# docs CloudFront distribution.
#
# What it does:
#   1. Renders scripts/cloudfront-basic-auth.js.tmpl with the base64 of
#      DOCS_AUTH_USER:DOCS_AUTH_PASS from scripts/.env
#   2. Creates or updates the CloudFront Function, publishes it LIVE
#   3. Adds (or replaces) a cache behavior for path pattern internal/*
#      on the distribution, with the function attached at viewer-request
#   4. If any CustomErrorResponse points at /index.html, repoints it to
#      /404.html (index.html is the external docs hub, not a 404 page)
#
# IMPORTANT: run this and wait for the distribution to deploy BEFORE the
# first deploy-docs.sh run that uploads objects under internal/ —
# otherwise internal content is world-readable during the gap.
#
# Usage:
#   ./scripts/setup-internal-auth.sh            # apply
#   ./scripts/setup-internal-auth.sh --dry-run  # show what would change
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

FUNCTION_NAME="crego-docs-internal-basic-auth"
PATH_PATTERN="internal/*"
TEMPLATE="$SCRIPT_DIR/cloudfront-basic-auth.js.tmpl"

# ── Colors / helpers ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'
DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'
info()  { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[done]${RESET}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${RESET}  $*"; }
err()   { echo -e "${RED}[err]${RESET}   $*" >&2; }

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ── Load .env ────────────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  err "$ENV_FILE not found. Copy from .env.example and fill in values."
  exit 1
fi
set -a
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue
  eval "$line"
done < "$ENV_FILE"
set +a

CLOUDFRONT_DISTRIBUTION_ID="${CLOUDFRONT_DISTRIBUTION_ID:?CLOUDFRONT_DISTRIBUTION_ID is not set in .env}"
DOCS_AUTH_USER="${DOCS_AUTH_USER:?DOCS_AUTH_USER is not set in .env}"
DOCS_AUTH_PASS="${DOCS_AUTH_PASS:?DOCS_AUTH_PASS is not set in .env}"

# ── Preflight ────────────────────────────────────────────────────────
for cmd in aws jq openssl; do
  command -v "$cmd" &>/dev/null || { err "$cmd is required but not installed."; exit 1; }
done
[[ -f "$TEMPLATE" ]] || { err "Template not found: $TEMPLATE"; exit 1; }

if [[ -n "${AWS_PROFILE:-}" ]]; then
  export AWS_PROFILE
  info "Using AWS profile: ${DIM}${AWS_PROFILE}${RESET}"
fi
aws sts get-caller-identity &>/dev/null || { err "AWS credentials not configured or expired."; exit 1; }

# ── 1. Render function code ──────────────────────────────────────────
B64=$(printf '%s:%s' "$DOCS_AUTH_USER" "$DOCS_AUTH_PASS" | openssl base64 -A)
TMP_JS=$(mktemp)
TMP_DIST=$(mktemp)
TMP_NEWCFG=$(mktemp)
trap 'rm -f "$TMP_JS" "$TMP_DIST" "$TMP_NEWCFG"' EXIT
sed "s|__B64_CREDENTIALS__|$B64|" "$TEMPLATE" > "$TMP_JS"
info "Rendered function code from template"

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN — no changes will be made"
fi

# ── 2. Create or update + publish the function ───────────────────────
FUNCTION_CONFIG='{"Comment":"Basic auth for /internal/* docs","Runtime":"cloudfront-js-2.0"}'

if ETAG=$(aws cloudfront describe-function --name "$FUNCTION_NAME" --query ETag --output text 2>/dev/null); then
  info "Function ${FUNCTION_NAME} exists — updating"
  if [[ "$DRY_RUN" != true ]]; then
    ETAG=$(aws cloudfront update-function --name "$FUNCTION_NAME" --if-match "$ETAG" \
      --function-config "$FUNCTION_CONFIG" \
      --function-code "fileb://$TMP_JS" --query ETag --output text)
  fi
else
  info "Creating function ${FUNCTION_NAME}"
  if [[ "$DRY_RUN" != true ]]; then
    ETAG=$(aws cloudfront create-function --name "$FUNCTION_NAME" \
      --function-config "$FUNCTION_CONFIG" \
      --function-code "fileb://$TMP_JS" --query ETag --output text)
  fi
fi

if [[ "$DRY_RUN" != true ]]; then
  aws cloudfront publish-function --name "$FUNCTION_NAME" --if-match "$ETAG" > /dev/null
  ok "Function published to LIVE"
  FN_ARN=$(aws cloudfront describe-function --name "$FUNCTION_NAME" --stage LIVE \
    --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)
  info "Function ARN: ${DIM}${FN_ARN}${RESET}"
else
  FN_ARN="arn:aws:cloudfront::000000000000:function/${FUNCTION_NAME}"
  info "Would publish function and fetch LIVE ARN"
fi

# ── 3. Patch the distribution ────────────────────────────────────────
aws cloudfront get-distribution-config --id "$CLOUDFRONT_DISTRIBUTION_ID" > "$TMP_DIST"
DIST_ETAG=$(jq -r '.ETag' "$TMP_DIST")

ORIGIN_DOMAIN=$(jq -r '.DistributionConfig.Origins.Items[0].DomainName' "$TMP_DIST")
DEFAULT_ROOT=$(jq -r '.DistributionConfig.DefaultRootObject // ""' "$TMP_DIST")
info "Origin: ${DIM}${ORIGIN_DOMAIN}${RESET}  DefaultRootObject: ${DIM}${DEFAULT_ROOT:-<none>}${RESET}"

if [[ "$ORIGIN_DOMAIN" == *".s3-website"* ]]; then
  warn "Origin is an S3 WEBSITE endpoint — the error document is configured on"
  warn "the bucket (aws s3api get-bucket-website), not via CustomErrorResponses."
  warn "Repoint the bucket error document to 404.html manually if needed."
fi

# Build the internal/* behavior by cloning DefaultCacheBehavior (keeps a
# valid TargetOriginId + cache settings) and overriding path + function.
# Placed FIRST in Items; replaces any existing internal/* behavior.
# CustomErrorResponses: repoint /index.html → /404.html (index.html is
# the external hub now), and if none exist, map S3 403/404 errors to the
# styled /404.html page instead of raw S3 XML.
jq --arg arn "$FN_ARN" --arg pp "$PATH_PATTERN" '
  .DistributionConfig
  | (.DefaultCacheBehavior
     + {PathPattern: $pp,
        FunctionAssociations: {Quantity: 1,
          Items: [{EventType: "viewer-request", FunctionARN: $arn}]}}) as $beh
  | ((.CacheBehaviors.Items // []) | map(select(.PathPattern != $pp))) as $others
  | .CacheBehaviors = {Quantity: (($others | length) + 1), Items: ([$beh] + $others)}
  | if (.CustomErrorResponses.Items // []) | any(.ResponsePagePath == "/index.html") then
      .CustomErrorResponses.Items |= map(
        if .ResponsePagePath == "/index.html" then .ResponsePagePath = "/404.html" else . end)
    elif (.CustomErrorResponses.Quantity // 0) == 0 then
      .CustomErrorResponses = {Quantity: 2, Items: [
        {ErrorCode: 403, ResponsePagePath: "/404.html", ResponseCode: "404", ErrorCachingMinTTL: 60},
        {ErrorCode: 404, ResponsePagePath: "/404.html", ResponseCode: "404", ErrorCachingMinTTL: 60}
      ]}
    else . end
' "$TMP_DIST" > "$TMP_NEWCFG"

ERROR_REPOINTED=$(jq -r '[.CustomErrorResponses.Items // [] | .[] | select(.ResponsePagePath == "/404.html")] | length' "$TMP_NEWCFG")
if [[ "$ERROR_REPOINTED" != "0" ]]; then
  info "CustomErrorResponses now point at /404.html (deploy 404.html via deploy-docs.sh)"
fi

if [[ "$DRY_RUN" == true ]]; then
  info "Would update distribution ${CLOUDFRONT_DISTRIBUTION_ID} with cache behaviors:"
  jq '.CacheBehaviors' "$TMP_NEWCFG"
  jq '.CustomErrorResponses // empty' "$TMP_NEWCFG"
  exit 0
fi

aws cloudfront update-distribution --id "$CLOUDFRONT_DISTRIBUTION_ID" \
  --if-match "$DIST_ETAG" --distribution-config "file://$TMP_NEWCFG" > /dev/null
ok "Distribution updated — behavior '${PATH_PATTERN}' with viewer-request auth"

info "Waiting for distribution to deploy (5–15 min)..."
aws cloudfront wait distribution-deployed --id "$CLOUDFRONT_DISTRIBUTION_ID"
ok "Distribution deployed"

# ── 4. Verification hints ────────────────────────────────────────────
DOMAIN=$(jq -r '.DistributionConfig.Aliases.Items[0] // empty' "$TMP_DIST")
[[ -z "$DOMAIN" ]] && DOMAIN=$(aws cloudfront get-distribution --id "$CLOUDFRONT_DISTRIBUTION_ID" --query 'Distribution.DomainName' --output text)
echo ""
echo -e "${BOLD}Verify:${RESET}"
echo "  curl -s -o /dev/null -w '%{http_code}\n' https://${DOMAIN}/internal/          # expect 401"
echo "  curl -s -o /dev/null -w '%{http_code}\n' -u '${DOCS_AUTH_USER}:***' https://${DOMAIN}/internal/   # expect 200 (after first deploy)"
