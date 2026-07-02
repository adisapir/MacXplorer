#!/usr/bin/env bash
#
# build-distribution.sh
#
# Builds a distributable release of MaXplorer and drops the artifacts into
# the repo's ./dist folder:
#
#   dist/MaXplorer.app          - the built application bundle
#   dist/MaXplorer-<version>.dmg - a compressed disk image with an /Applications shortcut
#   dist/MaXplorer-<version>.dmg.sha256 - checksum for the disk image
#   dist/MaXplorer.xcarchive    - the Xcode archive (intermediate, kept for symbolication)
#
# Usage:
#   ./scripts/build-distribution.sh                 # build using the project's signing settings
#   CONFIGURATION=Debug ./scripts/build-distribution.sh
#   SIGN=adhoc ./scripts/build-distribution.sh      # ad-hoc sign (no Developer account needed)
#   SIGN=none  ./scripts/build-distribution.sh      # disable code signing entirely
#   CODE_SIGN_IDENTITY="Developer ID Application: ..." DEVELOPMENT_TEAM=XXXXXXXXXX \
#     ./scripts/build-distribution.sh               # sign with a specific identity
#
set -euo pipefail

# --- Configuration -----------------------------------------------------------
PROJECT_NAME="MaXplorer"
SCHEME="MaXplorer"
CONFIGURATION="${CONFIGURATION:-Release}"
SIGN="${SIGN:-project}"   # project | adhoc | none

# Resolve paths relative to this script so it can be run from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_PATH="${REPO_ROOT}/${PROJECT_NAME}.xcodeproj"
DIST_DIR="${REPO_ROOT}/dist"
ARCHIVE_PATH="${DIST_DIR}/${PROJECT_NAME}.xcarchive"
APP_NAME="${PROJECT_NAME}.app"

# --- Helpers -----------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "${PROJECT_PATH}" ] || die "Project not found at ${PROJECT_PATH}"
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found (install Xcode command line tools)"

# --- Signing options ---------------------------------------------------------
SIGN_ARGS=()
case "${SIGN}" in
  project)
    log "Using the project's configured code signing settings."
    ;;
  adhoc)
    log "Ad-hoc code signing (CODE_SIGN_IDENTITY=-)."
    SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="")
    ;;
  none)
    log "Code signing disabled."
    SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")
    ;;
  *)
    die "Unknown SIGN mode '${SIGN}' (expected: project | adhoc | none)"
    ;;
esac

# Allow explicit overrides regardless of SIGN mode.
[ -n "${CODE_SIGN_IDENTITY:-}" ] && SIGN_ARGS+=("CODE_SIGN_IDENTITY=${CODE_SIGN_IDENTITY}")
[ -n "${DEVELOPMENT_TEAM:-}" ]   && SIGN_ARGS+=("DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}")

# --- Clean & prepare ---------------------------------------------------------
log "Preparing ${DIST_DIR}"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# --- Resolve version ---------------------------------------------------------
log "Reading build settings"
BUILD_SETTINGS="$(xcodebuild -project "${PROJECT_PATH}" -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" -showBuildSettings 2>/dev/null || true)"
get_setting() { printf '%s\n' "${BUILD_SETTINGS}" | awk -F' = ' "/ $1 = /{print \$2; exit}"; }

MARKETING_VERSION="$(get_setting MARKETING_VERSION)"; MARKETING_VERSION="${MARKETING_VERSION:-1.0}"
BUILD_NUMBER="$(get_setting CURRENT_PROJECT_VERSION)"; BUILD_NUMBER="${BUILD_NUMBER:-1}"
VERSION="${MARKETING_VERSION}"
DMG_NAME="${PROJECT_NAME}-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
log "Building ${PROJECT_NAME} ${VERSION} (build ${BUILD_NUMBER}), configuration ${CONFIGURATION}"

# --- Archive -----------------------------------------------------------------
log "Archiving (this can take a minute)…"
xcodebuild archive \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination 'generic/platform=macOS' \
  -archivePath "${ARCHIVE_PATH}" \
  ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
  | grep -E '^(=== |\*\* |CompileSwift|Ld |CodeSign|error:|warning:)' || true

ARCHIVED_APP="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}"
[ -d "${ARCHIVED_APP}" ] || die "Archive did not produce ${APP_NAME}. Check signing settings (try SIGN=adhoc)."

# --- Extract the .app --------------------------------------------------------
log "Copying ${APP_NAME} into dist/"
cp -R "${ARCHIVED_APP}" "${DIST_DIR}/${APP_NAME}"

# --- Build the .dmg ----------------------------------------------------------
log "Creating ${DMG_NAME}"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGING_DIR}"' EXIT
cp -R "${DIST_DIR}/${APP_NAME}" "${STAGING_DIR}/${APP_NAME}"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${PROJECT_NAME} ${VERSION}" \
  -srcfolder "${STAGING_DIR}" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "${DMG_PATH}" >/dev/null

# --- Checksum ----------------------------------------------------------------
log "Writing checksum"
( cd "${DIST_DIR}" && shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256" )

# --- Summary -----------------------------------------------------------------
log "Distribution ready in ${DIST_DIR}:"
ls -1sh "${DIST_DIR}"
printf '\n\033[1;32mDone.\033[0m %s %s built successfully.\n' "${PROJECT_NAME}" "${VERSION}"
