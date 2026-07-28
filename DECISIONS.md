# Decisiones de arquitectura

- **Local-first, sin backend.** Son datos médicos: todo vive en el dispositivo con `FileProtectionType.complete`. Nada sensible en `UserDefaults`; credenciales SMTP en Keychain.
- **SwiftData con esquema cerrado desde el inicio.** Migrar es costoso; los modelos nuevos (Contacto, Medicamento, TomaMedicamento) se agregaron como migraciones aditivas.
- **MVVM ligero, servicios detrás de protocolos** (`MailSender`, OCR, escaneo) para poder testear sin dispositivo y cambiar implementación (p. ej. SMTP → OAuth) sin tocar el resto.
- **Un `Reclamo` apunta a una `Cobertura`** (paciente + póliza resueltos), nunca directo a paciente/póliza. Snapshot del paciente/póliza en el reclamo para que "diga con qué póliza se hizo" aunque cambies de seguro.
- **Correo por SMTP directo (Gmail 465/TLS) con App Password**, no OAuth ni Google Cloud. Respaldo con `MFMailComposeViewController`. Todo detrás de `MailSender` por si Google retira las App Passwords.
- **Un solo correo a todos los destinatarios** (To/Cc/Bcc en un mensaje), nunca uno por destinatario. Continuidad de hilo por `Message-ID`/`In-Reply-To` + asunto idéntico como garantía mínima.
- **OCR nunca decide solo.** Facturas y recetas muestran una pantalla de confirmación editable; monto vacío ante baja confianza.
- **Alarmas de medicación.** Notificaciones time-sensitive + sonido de alarma propio; en primer plano `AVAudioSession .playback` ignora el silencio. La alarma real con la app cerrada ignorando el silencio requiere el entitlement **Critical Alerts** (aprobado por Apple), opcional detrás de un toggle.
- **Distribución por SideStore/AltStore**: IPA sin firmar generado por CI, `source.json` como catálogo. Sin App Store.
- **XcodeGen**: `project.yml` es la fuente; el `.xcodeproj` no se versiona.
