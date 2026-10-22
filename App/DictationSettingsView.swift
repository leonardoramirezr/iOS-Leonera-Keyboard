import SwiftUI

/// Ajustes del dictado: API key, URL, modelos, idioma y prompt.
struct DictationSettingsView: View {
    @EnvironmentObject private var dictation: DictationService
    @State private var settings = DictationSettingsStorage.load()
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var modelsError: String?
    @State private var showsAPIKey = false
    @State private var microphoneAllowed = DictationRecorder.hasPermission
    @State private var lastKeyboardAccess = ConfigurationStorage.lastKeyboardAccess

    var body: some View {
        Form {
            sharingSection

            Section {
                HStack {
                    Group {
                        if showsAPIKey {
                            TextField("gsk_…", text: $settings.apiKey)
                        } else {
                            SecureField("gsk_…", text: $settings.apiKey)
                        }
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    Button {
                        showsAPIKey.toggle()
                    } label: {
                        Image(systemName: showsAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                TextField(DictationSettings.defaultBaseURL, text: $settings.customBaseURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("API de Groq")
            } footer: {
                Text("Crea una API key en console.groq.com. La URL es opcional: déjala vacía para usar la de Groq o escribe la de otro servicio compatible con la API de OpenAI (termina en /v1). La API key no se incluye al exportar la configuración.")
            }

            Section {
                ModelField(title: "Voz a texto", model: $settings.transcriptionModel,
                           defaultModel: DictationSettings.defaultTranscriptionModel,
                           options: models.filter(Self.isTranscriptionModel))
                ModelField(title: "LLM", model: $settings.languageModel,
                           defaultModel: DictationSettings.defaultLanguageModel,
                           options: models.filter { !Self.isTranscriptionModel($0) })
                Button {
                    loadModels()
                } label: {
                    HStack {
                        Label("Cargar modelos disponibles", systemImage: "arrow.clockwise")
                        if loadingModels {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(loadingModels || settings.trimmedAPIKey.isEmpty)
                if let modelsError {
                    Text(modelsError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            } header: {
                Text("Modelos")
            } footer: {
                Text("Escribe el identificador del modelo o carga la lista de la API para elegirlo.")
            }

            Section {
                TextField("Automático", text: $settings.language)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Idioma del audio")
            } footer: {
                Text("Código ISO 639-1, por ejemplo «es» o «en». Déjalo vacío para detectarlo automáticamente.")
            }

            Section {
                Toggle("Mejorar texto con IA", isOn: $settings.improveText)
                TextEditor(text: $settings.prompt)
                    .font(.callout)
                    .frame(minHeight: 160)
                Button("Restablecer prompt por defecto") {
                    settings.prompt = DictationSettings.defaultPrompt
                }
                .disabled(settings.prompt == DictationSettings.defaultPrompt)
            } header: {
                Text("Mejorar texto")
            } footer: {
                Text("Con el interruptor activado (también está en la pantalla de dictado del teclado), la transcripción se envía al LLM con este prompt antes de escribirla.")
            }

            Section {
                if microphoneAllowed {
                    Label("Permiso de micrófono concedido", systemImage: "checkmark.circle")
                } else {
                    Button {
                        DictationRecorder.requestPermission { granted in
                            microphoneAllowed = granted
                            if !granted, let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } label: {
                        Label("Permitir el micrófono", systemImage: "mic")
                    }
                }
                if dictation.isSessionActive {
                    Label(dictation.isRecording ? "Grabando para el teclado" : "Micrófono activo para el teclado",
                          systemImage: dictation.isRecording ? "record.circle" : "mic.fill")
                    Button("Desactivar micrófono", role: .destructive) {
                        dictation.endSession()
                    }
                } else {
                    Button {
                        dictation.startSession()
                        microphoneAllowed = DictationRecorder.hasPermission
                    } label: {
                        Label("Activar micrófono", systemImage: "mic.badge.plus")
                    }
                }
                Toggle("Cierre automático del micrófono", isOn: $settings.autoCloseMicrophone)
                Stepper(value: $settings.recordingStartDelay, in: 0...5, step: 0.5) {
                    Text("Esperar \(settings.recordingStartDelay.formatted()) s antes de grabar")
                }
                if let error = dictation.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            } header: {
                Text("Micrófono")
            } footer: {
                Text("iOS no suele dejar que un teclado use el micrófono, así que esta app graba por él. La primera vez que dictes, el teclado abrirá esta app para activar el micrófono; vuelve a la app anterior y la grabación empezará tras la espera configurada. Con el cierre automático activado, el micrófono queda activo en segundo plano y se desactiva tras \(Int(DictationService.idleTimeout / 60)) minutos sin dictar; desactivado, se cierra al salir de la pantalla de dictado, cambiar de app o cerrar el teclado. Dictar requiere «Permitir acceso completo».")
            }
        }
        .navigationTitle("Dictado")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            settings = DictationSettingsStorage.load()
            microphoneAllowed = DictationRecorder.hasPermission
            lastKeyboardAccess = ConfigurationStorage.lastKeyboardAccess
        }
        .onChange(of: settings) { newValue in
            DictationSettingsStorage.save(newValue)
        }
        .onChange(of: dictation.isSessionActive) { _ in
            microphoneAllowed = DictationRecorder.hasPermission
        }
    }

    /// Comprueba que la app y el teclado comparten la carpeta donde se guarda la API key.
    @ViewBuilder
    private var sharingSection: some View {
        if !ConfigurationStorage.isAppGroupAvailable {
            Section {
                Label("El teclado no puede leer estos ajustes", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            } header: {
                Text("Conexión con el teclado")
            } footer: {
                Text("La app no tiene acceso al App Group «\(ConfigurationStorage.appGroupIdentifier ?? "sin configurar")», así que la API key se guarda solo en la app. Suele pasar cuando la herramienta con la que se firmó el IPA elimina los App Groups. Prueba con otra herramienta o con tu propio certificado. Los cambios de la distribución tampoco llegan al teclado mientras tanto.")
            }
        } else if let lastKeyboardAccess {
            Section {
                Label("El teclado comparte estos ajustes", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } header: {
                Text("Conexión con el teclado")
            } footer: {
                Text("Último acceso del teclado: \(lastKeyboardAccess.formatted(date: .abbreviated, time: .shortened)).")
            }
        } else {
            Section {
                Label("El teclado aún no ha leído estos ajustes", systemImage: "questionmark.circle")
            } header: {
                Text("Conexión con el teclado")
            } footer: {
                Text("Abre el teclado Leonera con «Permitir acceso completo» activado en cualquier campo de texto y vuelve aquí. Si sigue sin aparecer, la app y el teclado no comparten el App Group (\(ConfigurationStorage.appGroupIdentifier ?? "sin configurar")).")
            }
        }
    }

    private static func isTranscriptionModel(_ id: String) -> Bool {
        id.localizedCaseInsensitiveContains("whisper") || id.localizedCaseInsensitiveContains("transcribe")
    }

    private func loadModels() {
        loadingModels = true
        modelsError = nil
        let client = GroqClient(settings: settings)
        Task { @MainActor in
            do {
                models = try await client.availableModels()
                if models.isEmpty { modelsError = "La API no devolvió modelos." }
            } catch {
                modelsError = error.localizedDescription
            }
            loadingModels = false
        }
    }
}

/// Campo de texto para el identificador de un modelo, con un menú para elegirlo de la lista cargada.
private struct ModelField: View {
    let title: String
    @Binding var model: String
    let defaultModel: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                TextField(defaultModel, text: $model)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button {
                            model = option
                        } label: {
                            if option == model {
                                Label(option, systemImage: "checkmark")
                            } else {
                                Text(option)
                            }
                        }
                    }
                    Divider()
                    Button("Por defecto (\(defaultModel))") {
                        model = defaultModel
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
            }
        }
    }
}
