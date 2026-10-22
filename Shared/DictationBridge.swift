import Foundation

/// Comunicación entre el teclado y la app para dictar.
///
/// iOS no suele dejar que una extensión de teclado use el micrófono, así que la app
/// contenedora graba por ella: el teclado abre la app una vez para activar el
/// micrófono y, mientras la sesión siga abierta en segundo plano, le pide empezar
/// o terminar cada grabación con notificaciones Darwin. La app responde
/// escribiendo su estado en el App Group y avisando con `statusNotification`; el
/// audio queda en `audioURL` y el teclado lo envía a Groq.
enum DictationBridge {
    static let startNotification = "com.leonera.keyboard.dictation.start"
    static let stopNotification = "com.leonera.keyboard.dictation.stop"
    static let cancelNotification = "com.leonera.keyboard.dictation.cancel"
    /// El teclado pide liberar el micrófono (con el cierre automático desactivado).
    static let endSessionNotification = "com.leonera.keyboard.dictation.endSession"
    /// El teclado pregunta si la app sigue escuchando; la app responde con su estado.
    static let pingNotification = "com.leonera.keyboard.dictation.ping"
    static let statusNotification = "com.leonera.keyboard.dictation.status"

    static let urlScheme = "leonerakeyboard"
    static let urlHost = "dictation"

    /// Abre la app, activa el micrófono y empieza a grabar.
    static var recordURL: URL { URL(string: "\(urlScheme)://\(urlHost)?record=1")! }

    struct Status: Codable, Equatable {
        enum Phase: String, Codable {
            /// La app no tiene el micrófono activo.
            case idle
            /// Micrófono activo, esperando a que el teclado pida grabar.
            case ready
            /// El teclado abrió la app para grabar: la grabación empieza al volver al
            /// teclado, en `startedAt` (si ya se sabe).
            case pending
            case recording
            /// Grabación terminada: el audio está en `audioURL`.
            case finished
            /// No se pudo grabar; ver `message`.
            case failed
        }

        var phase: Phase = .idle
        /// Identificador de la última grabación terminada.
        var captureID: UUID?
        var startedAt: Date?
        var message: String?

        /// Indica si la app tiene el micrófono activo y puede grabar sin abrirse.
        var isSessionActive: Bool {
            switch phase {
            case .ready, .pending, .recording, .finished: return true
            case .idle, .failed: return false
            }
        }
    }

    private static var statusURL: URL? {
        ConfigurationStorage.containerURL?.appendingPathComponent("dictationStatus.json")
    }

    /// Archivo de la grabación hecha por la app.
    static var audioURL: URL? {
        ConfigurationStorage.containerURL?.appendingPathComponent("dictation.m4a")
    }

    static func readStatus() -> Status {
        guard let url = statusURL, let data = try? Data(contentsOf: url),
              let status = try? JSONDecoder().decode(Status.self, from: data)
        else { return Status() }
        return status
    }

    /// Lo usa la app: guarda su estado y avisa al teclado.
    static func publish(_ status: Status) {
        if let url = statusURL, let data = try? JSONEncoder().encode(status) {
            try? data.write(to: url, options: .atomic)
        }
        DarwinNotification.post(statusNotification)
    }
}
