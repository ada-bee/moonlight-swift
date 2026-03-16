#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.1}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
TEAM_ID="${TEAM_ID:-TH6BF55QH3}"
NOTARY_PROFILE="${NOTARY_PROFILE:-moonlight-notary}"
APP_NAME="GameStream"
PRODUCT_NAME="moonlight-swift"
TAG="v${VERSION}"

DIST_ROOT="${ROOT}/.dist"
DIST_DIR="${DIST_ROOT}/${VERSION}"
STAGE_DIR="${DIST_ROOT}/stage/${VERSION}"
APP_DIR="${STAGE_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
DMG_STAGE_DIR="${STAGE_DIR}/dmg"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
SHA_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.sha256"

SWIFT_BIN="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDKROOT="${SDKROOT:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk}"
OPENSSL_INCLUDE_DIR="${OPENSSL_INCLUDE_DIR:-$(nix eval --raw nixpkgs#openssl.dev.outPath)/include}"
OPENSSL_LIB_DIR="${OPENSSL_LIB_DIR:-$(nix eval --raw nixpkgs#openssl.out.outPath)/lib}"

discover_identity() {
  local line
  while IFS= read -r line; do
    case "$line" in
      *"Developer ID Application:"*"(${TEAM_ID})"*)
        line="${line#*\"}"
        line="${line%\"*}"
        printf '%s\n' "$line"
        return 0
        ;;
    esac
  done < <(security find-identity -v -p codesigning)

  return 1
}

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-$(discover_identity)}"

if [[ -z "${CODESIGN_IDENTITY}" ]]; then
  echo "Unable to find a Developer ID Application identity for team ${TEAM_ID}." >&2
  exit 1
fi

mkdir -p "${DIST_DIR}" "${STAGE_DIR}"
rm -rf "${APP_DIR}" "${DMG_STAGE_DIR}" "${ZIP_PATH}" "${DMG_PATH}" "${SHA_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}" "${DMG_STAGE_DIR}"

echo "==> Building release binary"
OPENSSL_INCLUDE_DIR="${OPENSSL_INCLUDE_DIR}" OPENSSL_LIB_DIR="${OPENSSL_LIB_DIR}" DEVELOPER_DIR="${DEVELOPER_DIR}" SDKROOT="${SDKROOT}" "${SWIFT_BIN}" build -c release

BIN_DIR="${ROOT}/.build/arm64-apple-macosx/release"

echo "==> Assembling app bundle"
cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT}/app/Sources/AppShell/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${ROOT}/app/Sources/AppShell/Resources/GameStream.icns" "${RESOURCES_DIR}/GameStream.icns"
cp -R "${BIN_DIR}/${PRODUCT_NAME}_Moonlight.bundle" "${RESOURCES_DIR}/${PRODUCT_NAME}_Moonlight.bundle"
cp -R "${BIN_DIR}/${PRODUCT_NAME}_MoonlightCore.bundle" "${RESOURCES_DIR}/${PRODUCT_NAME}_MoonlightCore.bundle"
cp "${OPENSSL_LIB_DIR}/libssl.3.dylib" "${FRAMEWORKS_DIR}/libssl.3.dylib"
cp "${OPENSSL_LIB_DIR}/libcrypto.3.dylib" "${FRAMEWORKS_DIR}/libcrypto.3.dylib"

echo "==> Updating bundle metadata"
/usr/libexec/PlistBuddy -c "Delete :CFBundleShortVersionString" "${CONTENTS_DIR}/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Delete :CFBundleVersion" "${CONTENTS_DIR}/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"

echo "==> Rewriting embedded library paths"
chmod 755 "${MACOS_DIR}/${APP_NAME}" "${FRAMEWORKS_DIR}/libssl.3.dylib" "${FRAMEWORKS_DIR}/libcrypto.3.dylib"
install_name_tool -id "@rpath/libcrypto.3.dylib" "${FRAMEWORKS_DIR}/libcrypto.3.dylib"
install_name_tool -id "@rpath/libssl.3.dylib" "${FRAMEWORKS_DIR}/libssl.3.dylib"
install_name_tool -change "${OPENSSL_LIB_DIR}/libcrypto.3.dylib" "@rpath/libcrypto.3.dylib" "${FRAMEWORKS_DIR}/libssl.3.dylib"
install_name_tool -change "${OPENSSL_LIB_DIR}/libssl.3.dylib" "@rpath/libssl.3.dylib" "${MACOS_DIR}/${APP_NAME}"
install_name_tool -change "${OPENSSL_LIB_DIR}/libcrypto.3.dylib" "@rpath/libcrypto.3.dylib" "${MACOS_DIR}/${APP_NAME}"
install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true

echo "==> Signing app bundle"
codesign --force --sign "${CODESIGN_IDENTITY}" --timestamp "${FRAMEWORKS_DIR}/libcrypto.3.dylib"
codesign --force --sign "${CODESIGN_IDENTITY}" --timestamp "${FRAMEWORKS_DIR}/libssl.3.dylib"
codesign --force --sign "${CODESIGN_IDENTITY}" --timestamp --options runtime "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "==> Notarizing app bundle archive"
ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"
xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple -v "${APP_DIR}"

echo "==> Creating signed disk image"
ln -s /Applications "${DMG_STAGE_DIR}/Applications"
cp -R "${APP_DIR}" "${DMG_STAGE_DIR}/${APP_NAME}.app"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGE_DIR}" -ov -format UDZO "${DMG_PATH}"
codesign --force --sign "${CODESIGN_IDENTITY}" --timestamp "${DMG_PATH}"

echo "==> Notarizing disk image"
xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple -v "${DMG_PATH}"
xcrun stapler validate -v "${DMG_PATH}"
spctl -a -t open --context context:primary-signature -vv "${DMG_PATH}"

echo "==> Writing checksum"
shasum -a 256 "${DMG_PATH}" > "${SHA_PATH}"

echo "Created release artifacts in ${DIST_DIR}"
echo "DMG: ${DMG_PATH}"
echo "SHA256: ${SHA_PATH}"

echo "==> Cleaning temporary build artifacts"
rm -rf "${STAGE_DIR}" "${ROOT}/.build"
