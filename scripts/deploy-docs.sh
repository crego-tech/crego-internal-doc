#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# deploy-docs.sh
# Sync the site/ directory to S3 and invalidate CloudFront cache.
# Reads configuration from scripts/.env (see .env.example).
#
# Usage:
#   ./scripts/deploy-docs.sh                  # deploy all docs
#   ./scripts/deploy-docs.sh --dry-run        # preview changes only
#   ./scripts/deploy-docs.sh --file index.html # deploy a single file
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Load .env ────────────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found."
  echo "Create it from the example:"
  echo "  cp scripts/.env.example scripts/.env"
  echo "Then fill in CLOUDFRONT_DISTRIBUTION_ID."
  exit 1
fi

# Source .env (skip comments and blank lines)
set -a
while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip comments and blank lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue
  eval "$line"
done < "$ENV_FILE"
set +a

# ── Defaults & validation ────────────────────────────────────────────
S3_BUCKET="${S3_BUCKET:?S3_BUCKET is not set in .env}"
S3_PREFIX="${S3_PREFIX:-}"
AWS_REGION="${AWS_REGION:?AWS_REGION is not set in .env}"
CLOUDFRONT_DISTRIBUTION_ID="${CLOUDFRONT_DISTRIBUTION_ID:-}"
SOURCE_DIR="$REPO_ROOT/site"

# Build S3 target (handle empty prefix)
if [[ -n "$S3_PREFIX" ]]; then
  S3_TARGET="s3://${S3_BUCKET}/${S3_PREFIX}/"
else
  S3_TARGET="s3://${S3_BUCKET}/"
fi

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────
info()  { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[done]${RESET}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${RESET}  $*"; }
err()   { echo -e "${RED}[err]${RESET}   $*" >&2; }

usage() {
  cat <<EOF
${BOLD}deploy-docs.sh${RESET} — Deploy site/ to S3 + CloudFront

${BOLD}Usage:${RESET}
  ./scripts/deploy-docs.sh [OPTIONS]

${BOLD}Options:${RESET}
  --dry-run           Show what would change without uploading
  --file <filename>   Deploy a single file (e.g. index.html)
  --skip-invalidation Skip CloudFront cache invalidation
  --help              Show this help

${BOLD}Configuration:${RESET}
  All config is read from ${DIM}scripts/.env${RESET}
  Copy from .env.example:  cp scripts/.env.example scripts/.env

${BOLD}Structure:${RESET}
  site/                           →  s3://${S3_BUCKET}/${S3_PREFIX}/
  ├── index.html                  →  /docs/index.html
  ├── engineering/                →  /docs/engineering/
  │   ├── development-process.html
  │   ├── tech-stack.html
  │   ├── infra-setup-guide.html
  │   ├── remote-environment-access.html
  │   └── platform-modules.html
  ├── infosec/                    →  /docs/infosec/
  │   ├── v1-reports/*.pdf
  │   └── v2-vapt-reports/*.pdf
  └── platform/releases/          →  /docs/platform/releases/

${BOLD}Examples:${RESET}
  ./scripts/deploy-docs.sh
  ./scripts/deploy-docs.sh --dry-run
  ./scripts/deploy-docs.sh --file development-process.html
EOF
  exit 0
}

# ── Parse args ────────────────────────────────────────────────────────
DRY_RUN=false
SINGLE_FILE=""
SKIP_INVALIDATION=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)           DRY_RUN=true; shift ;;
    --file)              SINGLE_FILE="$2"; shift 2 ;;
    --skip-invalidation) SKIP_INVALIDATION=true; shift ;;
    --help|-h)           usage ;;
    *)                   err "Unknown option: $1"; usage ;;
  esac
done

# ── Preflight checks ─────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
  err "AWS CLI is not installed."
  err "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  exit 1
fi

# Apply AWS_PROFILE if set
if [[ -n "${AWS_PROFILE:-}" ]]; then
  export AWS_PROFILE
  info "Using AWS profile: ${DIM}${AWS_PROFILE}${RESET}"
fi

# Verify credentials
if ! aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null; then
  err "AWS credentials not configured or expired. Run: aws configure"
  exit 1
fi

CALLER_IDENTITY=$(aws sts get-caller-identity --region "$AWS_REGION" --output text --query 'Arn')

# Verify source directory
if [[ ! -d "$SOURCE_DIR" ]]; then
  err "Source directory not found: $SOURCE_DIR"
  err "Expected a site/ folder at the repo root."
  exit 1
fi

# Count deployable files
if [[ -n "$SINGLE_FILE" ]]; then
  if [[ ! -f "$SOURCE_DIR/$SINGLE_FILE" ]]; then
    err "File not found: $SOURCE_DIR/$SINGLE_FILE"
    exit 1
  fi
  FILE_COUNT=1
else
  FILE_COUNT=$(find "$SOURCE_DIR" -type f \( -name "*.html" -o -name "*.pdf" -o -name "*.md" -o -name "*.xlsx" -o -name "*.csv" \) | wc -l | tr -d ' ')
fi

# ── Print config ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Crego Docs Deploy${RESET}"
echo -e "─────────────────────────────────────────────────"
info "AWS:     ${DIM}${CALLER_IDENTITY}${RESET}"
info "Source:  ${DIM}${SOURCE_DIR}${RESET}"
info "Target:  ${DIM}${S3_TARGET}${RESET}"
info "Files:   ${FILE_COUNT} file(s)"
if [[ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
  info "CF Dist: ${DIM}${CLOUDFRONT_DISTRIBUTION_ID}${RESET}"
else
  warn "CF Dist: not set (cache invalidation will be skipped)"
fi
echo ""

# ── Deploy ────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN — no changes will be made"
  echo ""
fi

# Helper: detect content-type from file extension
guess_content_type() {
  case "${1##*.}" in
    html) echo "text/html; charset=utf-8" ;;
    pdf)  echo "application/pdf" ;;
    md)   echo "text/markdown; charset=utf-8" ;;
    xlsx) echo "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ;;
    csv)  echo "text/csv; charset=utf-8" ;;
    *)    echo "application/octet-stream" ;;
  esac
}

if [[ -n "$SINGLE_FILE" ]]; then
  # ── Single file upload ──
  info "Uploading: ${SINGLE_FILE}"
  CONTENT_TYPE=$(guess_content_type "$SINGLE_FILE")
  CP_ARGS=(
    --region "$AWS_REGION"
    --content-type "$CONTENT_TYPE"
    --cache-control "public, max-age=300, s-maxage=3600"
    --metadata-directive REPLACE
  )
  [[ "$DRY_RUN" == true ]] && CP_ARGS+=(--dryrun)

  aws s3 cp \
    "$SOURCE_DIR/$SINGLE_FILE" \
    "${S3_TARGET}${SINGLE_FILE}" \
    "${CP_ARGS[@]}"
else
  # ── Full sync ──
  info "Syncing all files..."
  SYNC_ARGS=(
    --region "$AWS_REGION"
    --exclude "*"
    --include "*.html"
    --include "*.pdf"
    --include "*.md"
    --include "*.xlsx"
    --include "*.csv"
    --cache-control "public, max-age=300, s-maxage=3600"
    --delete
  )
  [[ "$DRY_RUN" == true ]] && SYNC_ARGS+=(--dryrun)

  aws s3 sync \
    "$SOURCE_DIR" \
    "${S3_TARGET}" \
    "${SYNC_ARGS[@]}"
fi

echo ""
ok "S3 upload complete"

# ── CloudFront invalidation ──────────────────────────────────────────
if [[ "$SKIP_INVALIDATION" == true ]]; then
  warn "Skipping CloudFront invalidation (--skip-invalidation)"
elif [[ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
  warn "CLOUDFRONT_DISTRIBUTION_ID not set in .env — skipping cache invalidation"
elif [[ "$DRY_RUN" == true ]]; then
  info "Would invalidate CloudFront distribution: ${CLOUDFRONT_DISTRIBUTION_ID}"
  if [[ -n "$SINGLE_FILE" ]]; then
    info "  Path: /${S3_PREFIX}/${SINGLE_FILE}"
  else
    info "  Path: /${S3_PREFIX}/*"
  fi
else
  if [[ -n "$SINGLE_FILE" ]]; then
    INVALIDATION_PATH="/${S3_PREFIX}/${SINGLE_FILE}"
  else
    INVALIDATION_PATH="/${S3_PREFIX}/*"
  fi

  info "Invalidating CloudFront cache..."
  INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
    --paths "$INVALIDATION_PATH" \
    --query 'Invalidation.Id' \
    --output text \
    --region us-east-1)

  ok "CloudFront invalidation created: ${DIM}${INVALIDATION_ID}${RESET}"
  info "  Path:   ${INVALIDATION_PATH}"
  info "  Status: in-progress (~60-90s to complete)"
fi

# ── Summary ───────────────────────────────────────────────────────────
if [[ -n "$S3_PREFIX" ]]; then
  SITE_URL="https://${S3_BUCKET}/${S3_PREFIX}/index.html"
else
  SITE_URL="https://${S3_BUCKET}/index.html"
fi
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
if [[ "$DRY_RUN" == true ]]; then
  echo -e "  ${YELLOW}DRY RUN complete${RESET} — re-run without --dry-run to deploy"
else
  echo -e "  ${GREEN}Deployment complete${RESET}"
  echo -e "  ${DIM}${SITE_URL}${RESET}"
fi
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
