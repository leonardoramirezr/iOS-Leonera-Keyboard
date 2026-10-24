import SwiftUI

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
