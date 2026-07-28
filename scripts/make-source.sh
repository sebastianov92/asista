#!/bin/bash
# Genera source.json (source de SideStore/AltStore) para una versión dada.
# Uso: ./scripts/make-source.sh v0.1.1 <tamaño_ipa_bytes> "descripción de la versión"
set -euo pipefail

TAG="${1:?tag (ej. v0.1.1)}"
SIZE="${2:?tamaño del IPA en bytes}"
DESC="${3:-Mejoras y correcciones.}"
VERSION="${TAG#v}"
DATE="$(date -u +%Y-%m-%d)"
REPO="sebastianov92/asista"
DOWNLOAD="https://github.com/$REPO/releases/download/$TAG/Asista.ipa"
ICON="https://raw.githubusercontent.com/$REPO/main/docs/icon.png"

cat > "$(dirname "$0")/../source.json" <<EOF
{
  "name": "Asista",
  "identifier": "com.sebastian.asista.source",
  "subtitle": "Reclamos de seguros médicos",
  "iconURL": "$ICON",
  "website": "https://github.com/$REPO",
  "tintColor": "#2E7ACD",
  "apps": [
    {
      "name": "Asista",
      "bundleIdentifier": "com.sebastian.Asista",
      "developerName": "Sebastián Ordóñez",
      "subtitle": "Reclamos de seguros médicos",
      "localizedDescription": "Arma y envía reclamos de seguros médicos en minutos: escanea los documentos con la cámara, genera PDFs livianos y bien nombrados, y los envía en un solo correo a los destinatarios correctos. Local-first (todo vive en tu dispositivo). Incluye OCR de facturas y recetas, alarmas de medicación, seguimiento de montos, historial médico y reportes.",
      "iconURL": "$ICON",
      "tintColor": "#2E7ACD",
      "category": "utilities",
      "screenshots": [],
      "versions": [
        {
          "version": "$VERSION",
          "date": "$DATE",
          "size": $SIZE,
          "downloadURL": "$DOWNLOAD",
          "localizedDescription": "$DESC",
          "minOSVersion": "17.0"
        }
      ],
      "appPermissions": {
        "entitlements": ["com.apple.security.application-groups"],
        "privacy": {
          "NSCameraUsageDescription": "Escanear documentos médicos.",
          "NSFaceIDUsageDescription": "Proteger tus datos médicos al abrir la app."
        }
      }
    }
  ],
  "news": []
}
EOF
echo "source.json → $VERSION ($SIZE bytes)"
