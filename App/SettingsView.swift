import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: ConfigurationStore
    @State private var haptics = HapticFeedback()

    private var settings: Binding<KeyboardSettings> { $store.configuration.settings }

    var body: some View {
        Form {
            Section {
                KeyboardPreview(configuration: store.configuration)
                    .listRowInsets(EdgeInsets())
            }

            Section("Escritura") {
                Toggle("Mayúscula automática", isOn: settings.autoCapitalize)
                Toggle("Mostrar teclas en minúscula", isOn: settings.showLowercase)
            }

            Section {
                Toggle("Vibración", isOn: settings.haptics)
                if store.configuration.settings.haptics {
                    Picker("Tipo", selection: settings.hapticStyle) {
                        ForEach(HapticStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Intensidad: \(Int((store.configuration.settings.hapticIntensity * 100).rounded())) %")
                        Slider(value: settings.hapticIntensity, in: 0.1...1, step: 0.05, onEditingChanged: { editing in
                            if !editing { playHapticPreview() }
                        })
                    }
                    VStack(alignment: .leading) {
                        Text("Duración: \(hapticDurationText)")
                        Slider(value: settings.hapticDuration, in: 0...150, step: 5, onEditingChanged: { editing in
                            if !editing { playHapticPreview() }
                        })
                    }
                    Button {
                        playHapticPreview()
                    } label: {
                        Label("Probar vibración", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }
                Toggle("Sonido de teclas", isOn: settings.keyClicks)
            } header: {
                Text("Respuesta")
            } footer: {
                Text("Con duración «breve» se usa el pulso corto del sistema; con más duración, cada pulsación corta la vibración anterior para no hacer esperar al teclado. La vibración, el sonido y la acción «Pegar» requieren «Permitir acceso completo» en los ajustes del teclado.")
            }
            .onChange(of: store.configuration.settings.hapticStyle) { _ in
                playHapticPreview()
            }

            Section {
                HitAreaPreview(configuration: store.configuration)
                    .listRowInsets(EdgeInsets())
                Picker("Forma", selection: settings.hitShape) {
                    ForEach(KeyHitShape.allCases) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    Text("Anchura: \(Int(store.configuration.settings.hitWidth)) %")
                    Slider(value: settings.hitWidth, in: 20...100, step: 5)
                }
                VStack(alignment: .leading) {
                    Text("Altura: \(Int(store.configuration.settings.hitHeight)) %")
                    Slider(value: settings.hitHeight, in: 20...100, step: 5)
                }
            } header: {
                Text("Área de toque")
            } footer: {
                Text("El área de toque va centrada en cada tecla: tocar fuera de ella no hace nada. Los porcentajes son del tamaño de cada tecla; al 100 % ocupa toda la tecla. La barra espaciadora siempre ocupa toda la anchura: solo le afecta la altura. Con la forma circular, si anchura y altura son distintas, el área es un óvalo.")
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Alto de fila: \(Int(store.configuration.settings.rowHeight)) pt")
                    Slider(value: settings.rowHeight, in: 36...64, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Distancia para deslizar: \(Int(store.configuration.settings.swipeThreshold)) pt")
                    Slider(value: settings.swipeThreshold, in: 8...40, step: 1)
                }
                CursorCurveChart(settings: store.configuration.settings)
                VStack(alignment: .leading) {
                    Text("Aceleración mínima: \(Int(store.configuration.settings.cursorMinAcceleration)) pt/s")
                    Slider(value: settings.cursorMinAcceleration, in: 0...store.configuration.settings.cursorMaxAcceleration, step: 10)
                }
                VStack(alignment: .leading) {
                    Text("Aceleración máxima: \(Int(store.configuration.settings.cursorMaxAcceleration)) pt/s")
                    Slider(value: settings.cursorMaxAcceleration, in: 50...2000, step: 10)
                }
                VStack(alignment: .leading) {
                    Text("Velocidad máxima del cursor: \(Int(store.configuration.settings.cursorMaxSpeed)) car/s")
                    Slider(value: settings.cursorMaxSpeed, in: 5...200, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Curva del cursor: \(String(format: "%.1f", store.configuration.settings.cursorCurveExponent))")
                    Slider(value: settings.cursorCurveExponent, in: 1.0...2.5, step: 0.1) {
                        Text("Curva del cursor")
                    } minimumValueLabel: {
                        Text("Lineal").font(.caption)
                    } maximumValueLabel: {
                        Text("Progresiva").font(.caption)
                    }
                }
            } header: {
                Text("Tamaño y gestos")
            } footer: {
                Text("La distancia para deslizar es cuánto hay que arrastrar una tecla hacia abajo para usar su símbolo secundario. Mantén pulsada la barra espaciadora y arrastra a izquierda o derecha para mover el cursor. La gráfica muestra la velocidad del cursor (vertical) según la aceleración del dedo (horizontal): mientras la aceleración no supere la mínima, el cursor no se mueve; a partir de ella sube con la curva hasta la aceleración máxima y, a partir de ahí, el cursor va a la velocidad máxima. La curva va de lineal a progresiva: cuanto más progresiva, más lento al principio y más rápido al final.")
            }
        }
        .navigationTitle("Ajustes del teclado")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hapticDurationText: String {
        let duration = Int(store.configuration.settings.hapticDuration)
        return duration == 0 ? "breve" : "\(duration) ms"
    }

    private func playHapticPreview() {
        haptics.play(store.configuration.settings)
    }
}

/// Una tecla de ejemplo con su área de toque dibujada encima, a tamaño real: el mismo
/// ancho y alto que tiene en el teclado de este dispositivo con la distribución actual.
private struct HitAreaPreview: View {
    let configuration: KeyboardConfiguration
    @Environment(\.colorScheme) private var colorScheme

    private let key = KeyDefinition(primary: .character("a"), secondary: .character("á"))

    var body: some View {
        let rowHeight = CGFloat(min(max(configuration.settings.rowHeight, 30), 80))
        let area = KeyHitArea(key: key, settings: configuration.settings)
        ZStack {
            KeyCapView(key: key, rowHeight: rowHeight)
            area.fill(KeyboardPalette.active.opacity(0.25))
            area.stroke(KeyboardPalette.active, lineWidth: 2)
        }
        .frame(width: keyWidth, height: rowHeight)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(KeyboardPalette.background(colorScheme))
    }

    /// Ancho de una unidad de tecla: la pantalla menos los márgenes, repartida entre
    /// las unidades de la fila más ancha, igual que en `KeyboardGrid`.
    private var keyWidth: CGFloat {
        let keyboardWidth = UIScreen.main.bounds.width - 2 * KeyboardMetrics.horizontalPadding
        let maxUnits = configuration.layout.rows.map(\.totalUnits).max() ?? 1
        return keyboardWidth / CGFloat(max(1, maxUnits)) * CGFloat(key.width)
    }
}
