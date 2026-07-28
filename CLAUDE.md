# Asista — notas para Claude

App iOS 17+ de reclamos de seguros médicos. SwiftUI + SwiftData, local-first, sin backend.

## Build
- Fuente del proyecto: `project.yml` (XcodeGen). El `.xcodeproj` NO se versiona: `xcodegen generate`.
- **DerivedData fuera de OneDrive/iCloud.** Adentro, CloudStorage inyecta xattrs y la firma de la extensión falla con "resource fork ... detritus not allowed". Xcode ya usa `~/Library/Developer/Xcode/DerivedData` (fuera). En CLI: `-derivedDataPath` en `/tmp`.
- Verificación rápida: `xcodebuild -project Asista.xcodeproj -scheme Asista -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`.

## Capacidades que requieren cuenta dev (comentadas en project.yml)
- **App Groups** (`group.com.sebastian.Asista`): Share Extension ↔ app. Sin firma ad-hoc en simulador falla; por eso `CODE_SIGN_ENTITLEMENTS` está comentado. El código cae a local sin romper.
- **iCloud/CloudKit**: toggle en Ajustes (`iCloudActivo`); `SharedModel` intenta CloudKit y cae a local si falta el entitlement.
- **Critical Alerts**: toggle `alarmasCriticas`; requiere aprobación de Apple. Sin eso, la alarma fuerte solo es fiable en primer plano.

## Estructura
- `Sources/Models` — SwiftData (esquema cerrado, migraciones aditivas).
- `Sources/Services` — Mail (SMTP/MIME), OCR, Scanning, PDF, Notifications, Security, etc.
- `Sources/Features` — UI por área (Reclamos, Pacientes, Medicacion, Seguros, Ajustes, Reportes…).
- `ShareExtension/` — target `AsistaShare`.

## Releases
Tag `vX.Y.Z` anotado → CI (`.github/workflows/release.yml`) construye IPA sin firmar, crea Release con el cuerpo del tag como notas, y actualiza `source.json` (SideStore/AltStore).
