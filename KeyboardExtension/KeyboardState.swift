import SwiftUI

/// Estado observable del teclado que comparten el controlador y las vistas SwiftUI.
final class KeyboardState: ObservableObject {
    @Published var configuration: KeyboardConfiguration
    @Published var rows: [KeyRow]
    @Published var shift: ShiftState = .off
    @Published var showingEmoji = false
    @Published var showingDictation = false
    /// Al mantener pulsada la barra espaciadora el teclado funciona como un trackpad:
    /// las teclas se muestran vacías y arrastrar el dedo mueve el cursor.
    @Published var isTrackpadActive = false

    /// Vibración y sonido de tecla; lo asigna el controlador. Las teclas lo llaman en
    /// cuanto se tocan, sin esperar a saber si es un toque o un deslizamiento.
    var playKeyFeedback: () -> Void = {}

    /// Vibración de cada carácter que desplaza el cursor en el modo trackpad. Solo vibra,
    /// sin sonido, porque el cursor puede avanzar muchos caracteres seguidos.
    var playCursorStepFeedback: () -> Void = {}

    /// Indica si el sistema pide que el teclado muestre su propia tecla de cambio de teclado.
    var needsInputModeSwitchKey = false {
        didSet { rebuildRows() }
    }

    init() {
        let configuration = ConfigurationStorage.load()
        self.configuration = configuration
        self.rows = configuration.layout.rows
    }

    var settings: KeyboardSettings { configuration.settings }

    var rowHeight: CGFloat { CGFloat(min(max(settings.rowHeight, 30), 80)) }

    /// Alto total del teclado (filas + márgenes).
    var keyboardHeight: CGFloat {
        rowHeight * CGFloat(max(rows.count, 1)) + KeyboardMetrics.verticalPadding * 2
    }

    func reload() {
        let loaded = ConfigurationStorage.load()
        guard loaded != configuration else { return }
        configuration = loaded
        rebuildRows()
    }

    /// Si el dispositivo no tiene el botón del globo del sistema y la distribución no
    /// incluye una tecla "Siguiente teclado", se añade una a la última fila.
    private func rebuildRows() {
        var rows = configuration.layout.rows
        let hasNextKeyboardKey = rows.contains { row in
            row.keys.contains { $0.primary.type == .nextKeyboard || $0.secondary?.type == .nextKeyboard }
        }
        if needsInputModeSwitchKey, !hasNextKeyboardKey, !rows.isEmpty {
            let last = rows.count - 1
            if let widest = rows[last].keys.indices.max(by: { rows[last].keys[$0].width < rows[last].keys[$1].width }),
               rows[last].keys[widest].width >= 2 {
                rows[last].keys[widest].width -= 1
            }
            rows[last].keys.insert(KeyDefinition(primary: KeyAction(.nextKeyboard)), at: 0)
        }
        self.rows = rows
    }
}

enum KeyboardMetrics {
    static let verticalPadding: CGFloat = 4
    static let horizontalPadding: CGFloat = 3
}
