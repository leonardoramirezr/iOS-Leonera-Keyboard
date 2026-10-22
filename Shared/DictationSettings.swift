import Foundation

/// Ajustes del dictado por voz con Groq (o cualquier API compatible con OpenAI).
///
/// Se guardan aparte de `KeyboardConfiguration` para que la API key no se incluya
/// al exportar o compartir la distribución.
struct DictationSettings: Codable, Equatable {
    static let defaultBaseURL = "https://api.groq.com/openai/v1"
    static let defaultTranscriptionModel = "whisper-large-v3-turbo"
    static let defaultLanguageModel = "openai/gpt-oss-120b"
    static let defaultLanguage = "es"
    static let defaultRecordingStartDelay: TimeInterval = 1
    static let defaultPrompt = """
    Eres un corrector de textos dictados por voz. Recibirás la transcripción literal de un audio. \
    Corrige la puntuación, los signos (incluidos los de apertura ¿ y ¡), los acentos, las mayúsculas \
    y la ortografía, y ajusta lo mínimo necesario para que el texto tenga sentido y se lea con \
    naturalidad. Conserva el idioma, el significado, el tono y las palabras de quien habla: no \
    añadas información, no resumas y no respondas a lo que dice el texto. Devuelve únicamente el \
    texto corregido, sin comillas ni comentarios.
    """

    var apiKey = ""
    /// URL base personalizada; vacía para usar la de Groq.
    var customBaseURL = ""
    /// Modelo de voz a texto.
    var transcriptionModel = DictationSettings.defaultTranscriptionModel
    /// LLM que mejora la transcripción cuando `improveText` está activo.
    var languageModel = DictationSettings.defaultLanguageModel
    /// Código ISO 639-1 del idioma del audio; vacío para detectarlo automáticamente.
    var language = DictationSettings.defaultLanguage
    /// Instrucciones que recibe el LLM junto con la transcripción.
    var prompt = DictationSettings.defaultPrompt
    /// Estado del interruptor del panel de dictado.
    var improveText = false
    /// Segundos que espera la app, tras volver al teclado, antes de empezar a grabar
    /// cuando el teclado la abrió para activar el micrófono.
    var recordingStartDelay = DictationSettings.defaultRecordingStartDelay
    /// Mantiene el micrófono de la app activo en segundo plano entre dictados y lo
    /// cierra solo tras `DictationService.idleTimeout`. Desactivado, se cierra al salir
    /// de la pantalla de dictado, cambiar de app o cerrar el teclado.
    var autoCloseMicrophone = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case apiKey, customBaseURL, transcriptionModel, languageModel, language, prompt, improveText, recordingStartDelay, autoCloseMicrophone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DictationSettings()
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? defaults.apiKey
        customBaseURL = try container.decodeIfPresent(String.self, forKey: .customBaseURL) ?? defaults.customBaseURL
        transcriptionModel = try container.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? defaults.transcriptionModel
        languageModel = try container.decodeIfPresent(String.self, forKey: .languageModel) ?? defaults.languageModel
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? defaults.prompt
        improveText = try container.decodeIfPresent(Bool.self, forKey: .improveText) ?? defaults.improveText
        recordingStartDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .recordingStartDelay) ?? defaults.recordingStartDelay
        autoCloseMicrophone = try container.decodeIfPresent(Bool.self, forKey: .autoCloseMicrophone) ?? defaults.autoCloseMicrophone
    }

    /// URL base que se usa en las peticiones, sin la barra final.
    var baseURL: String {
        var url = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { url = Self.defaultBaseURL }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    var trimmedAPIKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Modelo de voz a texto, o el de por defecto si el campo está vacío.
    var effectiveTranscriptionModel: String {
        let model = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? Self.defaultTranscriptionModel : model
    }

    /// LLM, o el de por defecto si el campo está vacío.
    var effectiveLanguageModel: String {
        let model = languageModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? Self.defaultLanguageModel : model
    }
}

/// Guarda los ajustes de dictado como JSON en el App Group, igual que
/// `ConfigurationStorage`, para que la extensión los lea directamente del disco.
enum DictationSettingsStorage {
    private static let key = "dictationSettings"
    private static let fileName = "dictationSettings.json"

    private static var fileURL: URL? {
        ConfigurationStorage.containerURL?.appendingPathComponent(fileName)
    }

    static func load() -> DictationSettings {
        if let url = fileURL, let data = try? Data(contentsOf: url),
           let settings = try? JSONDecoder().decode(DictationSettings.self, from: data) {
            return settings
        }
        if let data = ConfigurationStorage.defaults.data(forKey: key),
           let settings = try? JSONDecoder().decode(DictationSettings.self, from: data) {
            return settings
        }
        return DictationSettings()
    }

    static func save(_ settings: DictationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        if let url = fileURL {
            try? data.write(to: url, options: .atomic)
        }
        ConfigurationStorage.defaults.set(data, forKey: key)
    }

    /// Cambia solo el interruptor de «Mejorar texto» sin pisar otros ajustes que la
    /// app haya guardado mientras tanto.
    static func setImproveText(_ enabled: Bool) {
        var settings = load()
        guard settings.improveText != enabled else { return }
        settings.improveText = enabled
        save(settings)
    }
}
