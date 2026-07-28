#!/bin/bash
# Construye el artefacto distribuible de Asista:
#   dist/Asista.ipa  — app iOS SIN firmar (instalar con SideStore/AltStore + Apple ID propio).
# SideStore/AltStore firman en el dispositivo; por eso el IPA sale sin firmar.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"   # en CI viene del tag (vX.Y.Z)
DIST="$ROOT/dist"
DD="$(mktemp -d)/dd"

command -v xcodegen >/dev/null || { echo "falta xcodegen (brew install xcodegen)"; exit 1; }

rm -rf "$DIST" && mkdir -p "$DIST"
cd "$ROOT"
xcodegen generate >/dev/null

echo "── iOS (Release, sin firmar) ──"
xcodebuild -project Asista.xcodeproj -scheme Asista -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  MARKETING_VERSION="$VERSION" CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD" || true

IOS_APP="$DD/Build/Products/Release-iphoneos/Asista.app"
[ -d "$IOS_APP" ] || { echo "build iOS falló"; exit 1; }

PAYLOAD="$(mktemp -d)/Payload"
mkdir -p "$PAYLOAD"
cp -R "$IOS_APP" "$PAYLOAD/"
(cd "$(dirname "$PAYLOAD")" && zip -qry "$DIST/Asista.ipa" Payload)
echo "→ $DIST/Asista.ipa"

echo "── listo ──"
ls -lh "$DIST"
