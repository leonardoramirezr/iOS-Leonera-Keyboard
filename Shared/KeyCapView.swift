import SwiftUI

enum ShiftState {
    case off, on, locked
}

/// Márgenes del teclado dentro de la pantalla.
enum KeyboardMetrics {
    static let verticalPadding: CGFloat = 4
    static let horizontalPadding: CGFloat = 3
}

/// Colores aproximados a los del teclado del sistema.
enum KeyboardPalette {
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.17) : Color(red: 0.82, green: 0.83, blue: 0.86)
    }

    static func characterKey(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.42) : .white
    }

    static func functionKey(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.27) : Color(red: 0.67, green: 0.69, blue: 0.73)
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.6) : Color.black.opacity(0.3)
    }

    static let active = Color(red: 0.2, green: 0.48, blue: 0.98)

    /// Tecla vacía y sin sombra del modo trackpad (barra espaciadora mantenida).
    static func trackpadKey(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.24) : Color(red: 0.9, green: 0.9, blue: 0.91)
    }
}

/// Área de toque centrada en la tecla. Fuera de ella la tecla no responde a los gestos.
struct KeyHitArea: Shape {
    var shape: KeyHitShape
    /// Anchura y altura en porcentaje del tamaño de la tecla.
    var widthPercent: Double
    var heightPercent: Double

    func path(in rect: CGRect) -> Path {
        let width = rect.width * Self.fraction(widthPercent)
        let height = rect.height * Self.fraction(heightPercent)
        let area = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        switch shape {
        case .square: return Path(area)
        case .circle: return Path(ellipseIn: area)
        }
    }

    private static func fraction(_ percent: Double) -> CGFloat {
        CGFloat(min(max(percent, 1), 100) / 100)
    }
}

extension KeyHitArea {
    /// Área de toque de una tecla con los ajustes dados. La barra espaciadora siempre ocupa
    /// toda la anchura: el ajuste horizontal solo afecta a las demás teclas.
    init(key: KeyDefinition, settings: KeyboardSettings) {
        self.init(
            shape: settings.hitShape,
            widthPercent: key.primary.type == .space ? 100 : settings.hitWidth,
            heightPercent: settings.hitHeight
        )
    }
}

/// Dibuja una tecla: acción principal grande y acción secundaria pequeña arriba.
struct KeyCapView: View {
    let key: KeyDefinition
    var shift: ShiftState = .off
    var showLowercase = true
    var isPressed = false
    var isSwiping = false
    var isSelected = false
    /// Modo trackpad: la tecla se dibuja vacía, sin etiquetas ni sombra.
    var isBlank = false
    var rowHeight: CGFloat = 48

    @Environment(\.colorScheme) private var colorScheme

    private var primarySize: CGFloat { rowHeight * 0.46 }
    private var secondarySize: CGFloat { rowHeight * 0.27 }
    private var symbolSize: CGFloat { rowHeight * 0.4 }

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isBlank ? KeyboardPalette.trackpadKey(colorScheme) : background)
            .shadow(color: isBlank ? .clear : KeyboardPalette.shadow(colorScheme), radius: 0, x: 0, y: 1)
            .overlay(content.padding(.horizontal, 2).opacity(isBlank ? 0 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(KeyboardPalette.active, lineWidth: isSelected ? 3 : 0)
            )
            .padding(.horizontal, 3)
            .padding(.vertical, 4)
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        if isSwiping, let secondary = key.secondary {
            label(for: secondary, textSize: primarySize, symbolSize: symbolSize)
                .foregroundColor(primaryForeground)
        } else if key.secondary != nil || key.primary.type == .character {
            VStack(spacing: 0) {
                Group {
                    if let secondary = key.secondary {
                        label(for: secondary, textSize: secondarySize, symbolSize: secondarySize)
                    } else {
                        Text(" ").font(.system(size: secondarySize))
                    }
                }
                .foregroundColor(secondaryForeground)
                .frame(height: secondarySize * 1.15)

                primaryLabel
                    .foregroundColor(primaryForeground)
            }
        } else {
            primaryLabel
                .foregroundColor(primaryForeground)
        }
    }

    @ViewBuilder
    private var primaryLabel: some View {
        if let custom = key.label, !custom.isEmpty {
            Text(custom)
                .font(.system(size: key.primary.type == .character ? primarySize : symbolSize * 0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
        } else {
            label(for: key.primary, textSize: primarySize, symbolSize: symbolSize)
        }
    }

    @ViewBuilder
    private func label(for action: KeyAction, textSize: CGFloat, symbolSize: CGFloat) -> some View {
        switch action.type {
        case .character:
            Text(displayText(action.text))
                .font(.system(size: textSize))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
        case .space, .none:
            Text(" ").font(.system(size: textSize))
        default:
            Image(systemName: symbolName(for: action.type))
                .font(.system(size: symbolSize, weight: .regular))
        }
    }

    private func displayText(_ text: String) -> String {
        let uppercase = shift != .off || !showLowercase
        return uppercase ? text.uppercased() : text
    }

    private func symbolName(for type: KeyActionType) -> String {
        switch type {
        case .shift:
            switch shift {
            case .off: return "shift"
            case .on: return "shift.fill"
            case .locked: return "capslock.fill"
            }
        case .capsLock:
            return shift == .locked ? "capslock.fill" : "capslock"
        default:
            return type.systemImage ?? "questionmark"
        }
    }

    // MARK: - Colores

    private var isActive: Bool {
        switch key.primary.type {
        case .shift: return shift != .off
        case .capsLock: return shift == .locked
        default: return false
        }
    }

    private var background: Color {
        if isActive && !isPressed { return KeyboardPalette.active }
        let isFunction = key.primary.type.isFunctionKey
        let highlighted = isPressed || isSwiping
        if isFunction != highlighted {
            return KeyboardPalette.functionKey(colorScheme)
        }
        return KeyboardPalette.characterKey(colorScheme)
    }

    private var primaryForeground: Color {
        if isActive && !isPressed { return .white }
        return colorScheme == .dark ? .white : .black
    }

    private var secondaryForeground: Color {
        if isActive && !isPressed { return .white.opacity(0.8) }
        return colorScheme == .dark ? Color(white: 0.75) : Color(white: 0.45)
    }
}

/// Distribuye las filas de teclas según el ancho relativo de cada tecla.
struct KeyboardGrid<Cell: View>: View {
    let rows: [KeyRow]
    let rowHeight: CGFloat
    @ViewBuilder let cell: (KeyDefinition) -> Cell

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / CGFloat(maxUnits)
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        ForEach(row.keys) { key in
                            cell(key)
                                .frame(width: unit * CGFloat(key.width), height: rowHeight)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: rowHeight * CGFloat(rows.count))
    }

    private var maxUnits: Double {
        max(1, rows.map(\.totalUnits).max() ?? 1)
    }
}
