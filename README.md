<p align="center">
  <img src="docs/icon.png" width="120" alt="Asista">
</p>

<h1 align="center">Asista</h1>

<p align="center">Arma y envía reclamos de seguros médicos en minutos. iOS 17+, local-first, sin backend.</p>

---

## Qué hace

Reduce a minutos el proceso de armar y enviar un reclamo de seguro médico:

- **Escanea** los documentos físicos con la cámara (VisionKit) → PDFs livianos y bien nombrados.
- **Un solo correo** a todos los destinatarios (SMTP directo a Gmail), con continuidad de hilo.
- **OCR** de facturas del SRI (RUC, factura, fecha, monto) y de **recetas** → crea **alarmas de medicación**.
- **Seguimiento de montos**: pendiente de cobro, reembolsos parciales, deducible, reportes CSV/ZIP.
- **Historial médico** por paciente (timeline), directorio de médicos, búsqueda global.
- **Local-first**: todo vive en el dispositivo (son datos médicos). Face ID, archivos cifrados.

## Stack

SwiftUI · SwiftData · VisionKit · Vision (OCR) · Core Image · PDFKit · Network.framework (SMTP/TLS) · Keychain · LocalAuthentication · UserNotifications · App Intents.

## Compilar

Requiere **Xcode 26+** y [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd Asista
xcodegen generate
open Asista.xcodeproj
```

> El `.xcodeproj` no se versiona: se genera desde `project.yml`.
> Compila con DerivedData **fuera** de carpetas sincronizadas (OneDrive/iCloud): los xattrs rompen la firma de la extensión.

Para firmar en tu dispositivo, pon tu `DEVELOPMENT_TEAM` en `project.yml`. Las capacidades **App Groups** (Share Extension), **iCloud/CloudKit** y **Critical Alerts** (alarmas que ignoran el silencio) requieren tu cuenta de desarrollador; ver comentarios en `project.yml` y `Asista.entitlements`.

## Instalar (SideStore / AltStore)

Cada tag `vX.Y.Z` publica un **IPA sin firmar** en [Releases](../../releases). Agrega este source en SideStore/AltStore:

```
https://raw.githubusercontent.com/sebastianov92/asista/main/source.json
```

SideStore firma el IPA en tu dispositivo con tu Apple ID.

## Releases

Empuja un tag anotado; CI construye el IPA, crea el Release con el texto del tag como notas, y actualiza `source.json`.

```bash
git tag -a v0.1.1 -m "Cambios de esta versión"
git push origin v0.1.1
```

## Documentación

- [`SPEC.md`](SPEC.md) — especificación funcional completa.
- [`DECISIONS.md`](DECISIONS.md) — decisiones de arquitectura.

## Licencia

Uso personal/familiar. Sin licencia de distribución.
