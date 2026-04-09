#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# deploy-docs.sh
# Deploy the hosted Crego engineering docs to S3 + invalidate CloudFront.
# Reads configuration from scripts/.env (see .env.example).
#
# This script uploads a fixed allow-list of files — nothing else in the
# repo is deployed. To host a new page, add it to HOSTED_FILES below.
#
# Usage:
#   ./scripts/deploy-docs.sh                                # deploy all hosted files
#   ./scripts/deploy-docs.sh --dry-run                      # preview only
#   ./scripts/deploy-docs.sh --file index.html              # deploy a single file
#   ./scripts/deploy-docs.sh --file engineering/tech-stack.html
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Hosted file allow-list ───────────────────────────────────────────
# Paths are relative to REPO_ROOT and are uploaded to S3 under the same
# key. Only these files are ever deployed.
HOSTED_FILES=(
  "index.html"                                    # public 404 shown to external visitors
  "internal.html"                                 # internal engineering hub (unlisted)
  "engineering/development-process.html"
  "engineering/platform-modules.html"
  "engineering/tech-stack.html"
  "engineering/remote-environment-access.html"
  "engineering/infra-setup-guide.html"
)

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

# Normalise S3 prefix (strip leading/trailing slashes)
S3_PREFIX="${S3_PREFIX#/}"
S3_PREFIX="${S3_PREFIX%/}"

# Build S3 target base (handle empty prefix)
if [[ -n "$S3_PREFIX" ]]; then
  S3_TARGET_BASE="s3://${S3_BUCKET}/${S3_PREFIX}"
else
  S3_TARGET_BASE="s3://${S3_BUCKET}"
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
${BOLD}deploy-docs.sh${RESET} — Deploy Crego engineering docs to S3 + CloudFront

${BOLD}Usage:${RESET}
  ./scripts/deploy-docs.sh [OPTIONS]

${BOLD}Options:${RESET}
  --dry-run           Show what would change without uploading
  --file <path>       Deploy a single file (must be in the allow-list;
                      path is relative to repo root, e.g.
                      engineering/tech-stack.html)
  --skip-invalidation Skip CloudFront cache invalidation
  --help              Show this help

${BOLD}Configuration:${RESET}
  All config is read from ${DIM}scripts/.env${RESET}
  Copy from .env.example:  cp scripts/.env.example scripts/.env

${BOLD}Hosted files (allow-list):${RESET}
EOF
  for f in "${HOSTED_FILES[@]}"; do
    echo "  - $f"
  done
  cat <<EOF

${BOLD}Examples:${RESET}
  ./scripts/deploy-docs.sh
  ./scripts/deploy-docs.sh --dry-run
  ./scripts/deploy-docs.sh --file index.html
  ./scripts/deploy-docs.sh --file engineering/infra-setup-guide.html
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

if [[ -n "${AWS_PROFILE:-}" ]]; then
  export AWS_PROFILE
  info "Using AWS profile: ${DIM}${AWS_PROFILE}${RESET}"
fi

if ! aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null; then
  err "AWS credentials not configured or expired. Run: aws configure"
  exit 1
fi

CALLER_IDENTITY=$(aws sts get-caller-identity --region "$AWS_REGION" --output text --query 'Arn')

# ── Resolve target files ─────────────────────────────────────────────
TARGET_FILES=()

if [[ -n "$SINGLE_FILE" ]]; then
  # Normalise leading ./
  SINGLE_FILE="${SINGLE_FILE#./}"

  # Verify it's in the allow-list
  allowed=false
  for f in "${HOSTED_FILES[@]}"; do
    if [[ "$f" == "$SINGLE_FILE" ]]; then
      allowed=true
      break
    fi
  done

  if [[ "$allowed" != true ]]; then
    err "File not in hosted allow-list: $SINGLE_FILE"
    err "Allowed files:"
    for f in "${HOSTED_FILES[@]}"; do
      err "  - $f"
    done
    exit 1
  fi

  if [[ ! -f "$REPO_ROOT/$SINGLE_FILE" ]]; then
    err "File not found on disk: $REPO_ROOT/$SINGLE_FILE"
    exit 1
  fi

  TARGET_FILES=("$SINGLE_FILE")
else
  # Verify every hosted file exists before doing anything
  missing=()
  for f in "${HOSTED_FILES[@]}"; do
    if [[ ! -f "$REPO_ROOT/$f" ]]; then
      missing+=("$f")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing hosted files:"
    for f in "${missing[@]}"; do
      err "  - $f"
    done
    exit 1
  fi
  TARGET_FILES=("${HOSTED_FILES[@]}")
fi

# ── Print config ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Crego Docs Deploy${RESET}"
echo -e "─────────────────────────────────────────────────"
info "AWS:     ${DIM}${CALLER_IDENTITY}${RESET}"
info "Source:  ${DIM}${REPO_ROOT}${RESET}"
info "Target:  ${DIM}${S3_TARGET_BASE}/${RESET}"
info "Files:   ${#TARGET_FILES[@]} file(s)"
if [[ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
  info "CF Dist: ${DIM}${CLOUDFRONT_DISTRIBUTION_ID}${RESET}"
else
  warn "CF Dist: not set (cache invalidation will be skipped)"
fi
echo ""

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN — no changes will be made"
  echo ""
fi

# ── Content-type detection ───────────────────────────────────────────
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

# ── Upload ────────────────────────────────────────────────────────────
for rel in "${TARGET_FILES[@]}"; do
  src="$REPO_ROOT/$rel"
  if [[ -n "$S3_PREFIX" ]]; then
    dst="${S3_TARGET_BASE}/${rel}"
  else
    dst="${S3_TARGET_BASE}/${rel}"
  fi
  ct=$(guess_content_type "$rel")

  info "Uploading ${rel} → ${DIM}${dst}${RESET}"

  CP_ARGS=(
    --region "$AWS_REGION"
    --content-type "$ct"
    --cache-control "public, max-age=300, s-maxage=3600"
    --metadata-directive REPLACE
  )
  [[ "$DRY_RUN" == true ]] && CP_ARGS+=(--dryrun)

  aws s3 cp "$src" "$dst" "${CP_ARGS[@]}"
done

echo ""
ok "S3 upload complete"

# ── CloudFront invalidation ──────────────────────────────────────────
if [[ "$SKIP_INVALIDATION" == true ]]; then
  warn "Skipping CloudFront invalidation (--skip-invalidation)"
elif [[ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
  warn "CLOUDFRONT_DISTRIBUTION_ID not set in .env — skipping cache invalidation"
else
  # Build invalidation paths
  INVALIDATION_PATHS=()
  for rel in "${TARGET_FILES[@]}"; do
    if [[ -n "$S3_PREFIX" ]]; then
      INVALIDATION_PATHS+=("/${S3_PREFIX}/${rel}")
    else
      INVALIDATION_PATHS+=("/${rel}")
    fi
  done

  if [[ "$DRY_RUN" == true ]]; then
    info "Would invalidate CloudFront distribution: ${CLOUDFRONT_DISTRIBUTION_ID}"
    for p in "${INVALIDATION_PATHS[@]}"; do
      info "  ${p}"
    done
  else
    info "Invalidating CloudFront cache..."
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
      --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
      --paths "${INVALIDATION_PATHS[@]}" \
      --query 'Invalidation.Id' \
      --output text \
      --region us-east-1)

    ok "CloudFront invalidation created: ${DIM}${INVALIDATION_ID}${RESET}"
    for p in "${INVALIDATION_PATHS[@]}"; do
      info "  ${p}"
    done
    info "Status: in-progress (~60-90s to complete)"
  fi
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
