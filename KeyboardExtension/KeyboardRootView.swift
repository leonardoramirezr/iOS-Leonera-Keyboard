import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var state: KeyboardState
    let dictation: DictationController
    let perform: (KeyAction) -> Void

    var body: some View {
        Group {
            if state.showingDictation {
                DictationPanel(state: state, dictation: dictation, perform: perform)
            } else if state.showingEmoji {
                EmojiPanel(state: state, perform: perform)
            } else {
                KeyboardGrid(rows: state.rows, rowHeight: state.rowHeight) { key in
                    KeyCell(key: key, state: state, perform: perform)
                }
            }
        }
        .padding(.horizontal, KeyboardMetrics.horizontalPadding)
        .padding(.vertical, KeyboardMetrics.verticalPadding)
        .frame(height: state.keyboardHeight)
        .frame(maxWidth: .infinity)
    }
}

/// Una tecla interactiva: tocar ejecuta la acción principal y deslizar hacia
/// abajo ejecuta la secundaria. Vibra al tocarla, antes de saber cuál de las dos
/// se ejecutará. Las teclas de borrar o mover el cursor se repiten mientras se
/// mantienen pulsadas. Mantener pulsada la barra espaciadora activa el modo
/// trackpad: el teclado se queda vacío y arrastrar a izquierda o derecha mueve
/// el cursor.
struct KeyCell: View {
    let key: KeyDefinition
    @ObservedObject var state: KeyboardState
    let perform: (KeyAction) -> Void

    @State private var isPressed = false
    @State private var isSwiping = false
    @State private var didRepeat = false
    @State private var repeatTimer: Timer?
    @State private var trackpadTimer: Timer?
    @State private var isTrackpad = false
    /// Desplazamiento horizontal del dedo en el último evento del gesto.
    @State private var dragX: CGFloat = 0
    /// Momento del último evento del gesto, para calcular la velocidad del dedo.
    @State private var dragTime = Date()
    /// Posición y momento del último evento procesado por el trackpad.
    @State private var trackpadLastX: CGFloat = 0
    @State private var trackpadLastTime = Date()
    /// Recorrido acumulado (ya acelerado) que aún no llega a un carácter completo.
    @State private var trackpadAccumulated: CGFloat = 0

    /// Tiempo que hay que mantener pulsada la barra espaciadora para activar el trackpad.
    private static let trackpadDelay: TimeInterval = 0.4

    init(key: KeyDefinition, state: KeyboardState, perform: @escaping (KeyAction) -> Void) {
        self.key = key
        _state = ObservedObject(wrappedValue: state)
        self.perform = perform
    }

    var body: some View {
        KeyCapView(
            key: key,
            shift: state.shift,
            showLowercase: state.settings.showLowercase,
            isPressed: isPressed,
            isSwiping: isSwiping,
            isBlank: state.isTrackpadActive,
            rowHeight: state.rowHeight
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    dragX = value.translation.width
                    dragTime = value.time
                    if !isPressed {
                        isPressed = true
                        state.playKeyFeedback()
                        startRepeatingIfNeeded()
                        startTrackpadTimerIfNeeded()
                    }
                    if isTrackpad {
                        moveCursor()
                        return
                    }
                    let swiping = isSwipe(value.translation)
                    if swiping != isSwiping {
                        isSwiping = swiping
                        if swiping {
                            stopRepeating()
                            stopTrackpadTimer()
                        }
                    }
                }
                .onEnded { value in
                    stopRepeating()
                    stopTrackpadTimer()
                    if isTrackpad {
                        endTrackpad()
                    } else if isSwipe(value.translation), let secondary = key.secondary {
                        perform(secondary)
                    } else if !didRepeat {
                        perform(key.primary)
                    }
                    isPressed = false
                    isSwiping = false
                    didRepeat = false
                }
        )
        .onDisappear {
            stopRepeating()
            stopTrackpadTimer()
            if isTrackpad { endTrackpad() }
        }
    }

    private func isSwipe(_ translation: CGSize) -> Bool {
        guard let secondary = key.secondary, secondary.type != .none else { return false }
        return translation.height > CGFloat(state.settings.swipeThreshold)
    }

    private func startRepeatingIfNeeded() {
        guard key.primary.type.repeatsWhileHeld else { return }
        stopRepeating()
        let action = key.primary
        let timer = Timer(fire: Date().addingTimeInterval(0.45), interval: 0.08, repeats: true) { _ in
            didRepeat = true
            state.playKeyFeedback()
            perform(action)
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    // MARK: - Trackpad

    private func startTrackpadTimerIfNeeded() {
        guard key.primary.type == .space else { return }
        stopTrackpadTimer()
        let timer = Timer(timeInterval: Self.trackpadDelay, repeats: false) { _ in
            trackpadTimer = nil
            guard isPressed, !isSwiping else { return }
            isTrackpad = true
            trackpadLastX = dragX
            trackpadLastTime = Date()
            trackpadAccumulated = 0
            state.isTrackpadActive = true
            state.playKeyFeedback()
        }
        RunLoop.main.add(timer, forMode: .common)
        trackpadTimer = timer
    }

    private func stopTrackpadTimer() {
        trackpadTimer?.invalidate()
        trackpadTimer = nil
    }

    /// Mueve el cursor un carácter por cada tramo que recorre el dedo. El recorrido se
    /// acelera según la velocidad: despacio el cursor avanza con precisión y deprisa
    /// recorre muchos caracteres. El tamaño del tramo depende de la sensibilidad.
    private func moveCursor() {
        let delta = dragX - trackpadLastX
        let elapsed = max(dragTime.timeIntervalSince(trackpadLastTime), 0.001)
        trackpadLastX = dragX
        trackpadLastTime = dragTime
        guard delta != 0 else { return }

        let speed = abs(delta) / CGFloat(elapsed)
        trackpadAccumulated += delta * Self.cursorAcceleration(forSpeed: speed)

        let step = CGFloat(state.settings.cursorPointsPerCharacter)
        let steps = Int(trackpadAccumulated / step)
        guard steps != 0 else { return }
        trackpadAccumulated -= CGFloat(steps) * step
        let action = KeyAction(steps < 0 ? .cursorLeft : .cursorRight)
        for _ in 0..<abs(steps) {
            perform(action)
        }
    }

    /// Factor de aceleración según la velocidad del dedo en puntos por segundo:
    /// 0,5 por debajo de 100 pt/s, 1 hacia 200 pt/s y hasta 5 a partir de 1000 pt/s.
    private static func cursorAcceleration(forSpeed speed: CGFloat) -> CGFloat {
        min(max(speed / 200, 0.5), 5)
    }

    private func endTrackpad() {
        isTrackpad = false
        state.isTrackpadActive = false
    }
}
