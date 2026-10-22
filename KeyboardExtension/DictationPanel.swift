import SwiftUI

/// Pantalla de dictado que sustituye al teclado: botón de grabar en el centro,
/// interruptor para mejorar el texto con el LLM y una fila con ABC, espacio,
/// borrar e intro.
struct DictationPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var dictation: DictationController
    let perform: (KeyAction) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                statusText
                recordButton
                Toggle("Mejorar texto con IA", isOn: $dictation.improveText)
                    .toggleStyle(.switch)
                    .tint(KeyboardPalette.active)
                    .fixedSize()
                    .disabled(dictation.isBusy)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            KeyboardGrid(rows: [Self.bottomRow], rowHeight: state.rowHeight) { key in
                KeyCell(key: key, state: state, perform: handle)
            }
        }
    }

    // MARK: - Estado

    private var statusText: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(status(at: context.date))
                .font(.footnote)
                .foregroundColor(colorScheme == .dark ? Color(white: 0.75) : Color(white: 0.35))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
        }
    }

    private func status(at date: Date) -> String {
        switch dictation.phase {
        case .idle:
            return dictation.message ?? "Toca el micrófono para dictar"
        case .starting:
            if let startsAt = dictation.recordingStartsAt, startsAt > date {
                return "Grabando en \(Int(startsAt.timeIntervalSince(date).rounded(.up))) s…"
            }
            return "Activando el micrófono…"
        case .recording(let since):
            let seconds = max(0, Int(date.timeIntervalSince(since)))
            return String(format: "Grabando… %d:%02d · toca para terminar", seconds / 60, seconds % 60)
        case .transcribing:
            return "Transcribiendo…"
        case .improving:
            return "Mejorando el texto…"
        }
    }

    // MARK: - Botón de grabar

    private var buttonSize: CGFloat { min(76, max(44, state.rowHeight * 1.5)) }

    private var recordButton: some View {
        Button {
            dictation.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(dictation.isRecording ? Color.red : KeyboardPalette.active)
                    .shadow(color: KeyboardPalette.shadow(colorScheme), radius: 2, x: 0, y: 1)
                if dictation.isBusy || dictation.phase == .starting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: buttonSize * 0.4, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(dictation.isBusy)
        .accessibilityLabel(dictation.isRecording ? "Terminar grabación" : "Grabar")
    }

    // MARK: - Fila inferior

    private func handle(_ action: KeyAction) {
        if action.type == .none {
            // «ABC»: vuelve al teclado.
            dictation.closePanel()
            state.showingDictation = false
        } else {
            perform(action)
        }
    }

    private static let bottomRow = KeyRow(keys: [
        KeyDefinition(primary: KeyAction(.none), width: 1.5, label: "ABC"),
        KeyDefinition(primary: KeyAction(.space), width: 5),
        KeyDefinition(primary: KeyAction(.backspace), secondary: KeyAction(.deleteWord), width: 1.5),
        KeyDefinition(primary: KeyAction(.returnKey), width: 2),
    ])
}
