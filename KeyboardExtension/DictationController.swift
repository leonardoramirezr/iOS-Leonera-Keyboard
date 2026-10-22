import Foundation
import SwiftUI

/// Lógica del panel de dictado: graba, envía el audio a Groq y entrega el texto.
///
/// Primero intenta grabar desde el propio teclado. iOS normalmente no lo permite en
/// las extensiones de teclado; en ese caso graba la app contenedora (ver
/// `DictationBridge`), que el teclado abre la primera vez para activar el micrófono.
///
/// Usar desde el hilo principal.
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Esperando a que la app empiece a grabar.
        case starting
        case recording(since: Date)
        case transcribing
        case improving
    }

    private enum Mode {
        /// Graba el propio teclado.
        case local
        /// Graba la app contenedora.
        case app
    }

    @Published private(set) var phase: Phase = .idle
    /// Error o indicación que se muestra sobre el botón.
    @Published private(set) var message: String?
    /// En `.starting`: cuándo empezará a grabar la app (tras la espera configurada).
    @Published private(set) var recordingStartsAt: Date?
    /// Interruptor «Mejorar texto»: envía la transcripción al LLM con el prompt.
    @Published var improveText: Bool {
        didSet { DictationSettingsStorage.setImproveText(improveText) }
    }

    /// Inserta el texto final en el campo de texto.
    var insertText: (String) -> Void = { _ in }
    /// Abre la app contenedora; devuelve false si no se pudo.
    var openURL: (URL) -> Bool = { _ in false }
    var hasFullAccess: () -> Bool = { false }
    /// La app está grabando para el teclado (p. ej. al volver de abrirla): hay que mostrar el panel.
    var onAppRecording: () -> Void = {}

    private var mode: Mode?
    private let recorder = DictationRecorder()
    /// El teclado no pudo usar el micrófono; desde entonces graba la app.
    private var localRecordingUnavailable = false
    /// La app respondió que tiene el micrófono activo.
    private var appSessionActive = false
    /// Se abrió la app para grabar: al volver al teclado se muestra la pantalla de grabación.
    private var awaitingAppRecording = false
    /// El teclado acaba de abrir la app: al ocultarse no hay que cerrar el micrófono.
    private var openingApp = false
    /// Última grabación de la app ya procesada (o descartada).
    private var handledCaptureID: UUID?
    private var timeout: DispatchWorkItem?
    private var task: Task<Void, Never>?
    private var statusObserver: DarwinNotificationObserver?

    private static var localAudioURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dictation.m4a")
    }

    init() {
        improveText = DictationSettingsStorage.load().improveText
        handledCaptureID = DictationBridge.readStatus().captureID
        statusObserver = DarwinNotificationObserver(name: DictationBridge.statusNotification) { [weak self] in
            self?.appStatusDidChange()
        }
    }

    var isBusy: Bool { phase == .transcribing || phase == .improving }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    // MARK: - Ciclo de vida

    /// Al mostrar el panel o volver al teclado: recarga los ajustes y pregunta a la app
    /// si sigue escuchando (o grabando).
    func refresh() {
        openingApp = false
        let saved = DictationSettingsStorage.load().improveText
        if saved != improveText { improveText = saved }
        if awaitingAppRecording, phase == .idle { showAppPending(startsAt: nil) }
        DarwinNotification.post(DictationBridge.pingNotification)
    }

    /// El teclado se oculta: el teclado no puede seguir grabando por su cuenta.
    func keyboardWillDisappear() {
        if mode == .local, isRecording { cancel() }
        releaseMicrophoneIfNeeded()
    }

    /// La app anfitriona pasa a segundo plano (se cambió de app).
    func hostDidEnterBackground() {
        releaseMicrophoneIfNeeded()
    }

    /// Se cierra la pantalla de dictado.
    func closePanel() {
        cancel()
        releaseMicrophoneIfNeeded()
    }

    /// Sin el cierre automático activado, descarta el dictado en curso y pide a la app
    /// que libere el micrófono. No lo hace mientras se abre la app para grabar.
    private func releaseMicrophoneIfNeeded() {
        guard !openingApp, !DictationSettingsStorage.load().autoCloseMicrophone else { return }
        if mode != nil || phase != .idle { cancel() }
        appSessionActive = false
        DarwinNotification.post(DictationBridge.endSessionNotification)
    }

    // MARK: - Acciones

    func toggleRecording() {
        switch phase {
        case .idle: startRecording()
        case .recording: stopRecording()
        case .starting: cancel()
        case .transcribing, .improving: break
        }
    }

    /// Descarta la grabación o el procesamiento en curso.
    func cancel() {
        timeout?.cancel()
        awaitingAppRecording = false
        recordingStartsAt = nil
        task?.cancel()
        task = nil
        switch mode {
        case .local: recorder.stop()
        case .app: DarwinNotification.post(DictationBridge.cancelNotification)
        case nil: break
        }
        mode = nil
        phase = .idle
    }

    private func startRecording() {
        message = nil
        guard hasFullAccess() else {
            message = "Activa «Permitir acceso completo» en Ajustes › General › Teclado › Teclados › Leonera para dictar."
            return
        }
        guard ConfigurationStorage.isAppGroupAvailable else {
            message = "El teclado no puede leer los ajustes de la app porque el App Group (\(ConfigurationStorage.appGroupIdentifier ?? "sin configurar")) no está disponible. Revisa que la herramienta con la que firmaste el IPA conserve los App Groups."
            return
        }
        guard !DictationSettingsStorage.load().trimmedAPIKey.isEmpty else {
            message = GroqError.missingAPIKey.errorDescription
            return
        }
        if !localRecordingUnavailable, startLocalRecording() { return }
        startAppRecording()
    }

    private func stopRecording() {
        switch mode {
        case .local:
            let capture = recorder.finishCapture()
            recorder.stop()
            mode = nil
            guard let capture, capture.frames > 0 else {
                // El teclado no recibió audio del micrófono: la próxima vez graba la app.
                localRecordingUnavailable = true
                phase = .idle
                message = "El teclado no recibió audio del micrófono. Vuelve a tocar el botón para grabar a través de la app."
                return
            }
            process(audioAt: capture.url)
        case .app:
            phase = .transcribing
            DarwinNotification.post(DictationBridge.stopNotification)
            scheduleTimeout(seconds: 5) { [weak self] in
                self?.fail("La app dejó de responder y la grabación se perdió. Vuelve a intentarlo.")
            }
        case nil:
            phase = .idle
        }
    }

    // MARK: - Grabación en el teclado

    private func startLocalRecording() -> Bool {
        do {
            try recorder.start()
            try recorder.beginCapture(to: Self.localAudioURL)
            mode = .local
            phase = .recording(since: Date())
            return true
        } catch {
            recorder.stop()
            localRecordingUnavailable = true
            return false
        }
    }

    // MARK: - Grabación en la app

    private func startAppRecording() {
        mode = .app
        guard appSessionActive else {
            openApp()
            return
        }
        phase = .starting
        DarwinNotification.post(DictationBridge.startNotification)
        // Si la app ya no está en segundo plano no responde: se abre para reactivar el micrófono.
        scheduleTimeout(seconds: 1.5) { [weak self] in
            guard let self, self.phase == .starting else { return }
            self.appSessionActive = false
            self.openApp()
        }
    }

    private func openApp() {
        phase = .idle
        openingApp = true
        if openURL(DictationBridge.recordURL) {
            awaitingAppRecording = true
            message = "Se abrió Leonera Keyboard para activar el micrófono. Vuelve a esta app: la grabación empezará al volver."
        } else {
            openingApp = false
            mode = nil
            message = "No se pudo abrir Leonera Keyboard. Ábrela y toca «Activar micrófono» en Dictado."
        }
    }

    private func appStatusDidChange() {
        let status = DictationBridge.readStatus()
        appSessionActive = status.isSessionActive
        if status.phase != .pending {
            awaitingAppRecording = false
            recordingStartsAt = nil
        }

        switch status.phase {
        case .pending:
            guard mode != .local, phase == .idle || phase == .starting else { return }
            showAppPending(startsAt: status.startedAt)
        case .recording:
            guard mode != .local else { return }
            switch phase {
            case .idle, .starting:
                timeout?.cancel()
                mode = .app
                message = nil
                phase = .recording(since: status.startedAt ?? Date())
                onAppRecording()
            default:
                break
            }
        case .finished:
            guard let id = status.captureID, id != handledCaptureID else { return }
            handledCaptureID = id
            guard mode == .app, phase == .transcribing, let url = DictationBridge.audioURL else { return }
            timeout?.cancel()
            mode = nil
            process(audioAt: url)
        case .failed:
            guard mode == .app else { return }
            switch phase {
            case .starting, .recording, .transcribing: fail(status.message ?? "La app no pudo grabar.")
            default: break
            }
        case .ready, .idle:
            // La app ya no graba (se canceló o se cerró el micrófono).
            if mode == .app, isRecording || phase == .starting {
                timeout?.cancel()
                mode = nil
                phase = .idle
            }
        }
    }

    /// La app empezará a grabar en cuanto termine la espera: se muestra ya la pantalla de grabación.
    private func showAppPending(startsAt: Date?) {
        mode = .app
        message = nil
        phase = .starting
        recordingStartsAt = startsAt
        onAppRecording()
        let delay = startsAt.map { max(0, $0.timeIntervalSinceNow) }
            ?? DictationSettingsStorage.load().recordingStartDelay
        scheduleTimeout(seconds: delay + 3) { [weak self] in
            guard let self, self.phase == .starting else { return }
            self.awaitingAppRecording = false
            self.fail("La app no empezó a grabar. Vuelve a tocar el botón.")
        }
    }

    // MARK: - Groq

    private func process(audioAt url: URL) {
        let settings = DictationSettingsStorage.load()
        let client = GroqClient(settings: settings)
        let improve = improveText
        phase = .transcribing
        task = Task { @MainActor [weak self] in
            do {
                var text = try await client.transcribe(audioAt: url)
                if improve, !text.isEmpty, !Task.isCancelled {
                    self?.phase = .improving
                    text = try await client.improve(text)
                }
                guard !Task.isCancelled, let self else { return }
                self.task = nil
                self.phase = .idle
                if text.isEmpty {
                    self.message = "No se detectó voz en la grabación."
                } else {
                    self.insertText(text)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ text: String) {
        timeout?.cancel()
        recordingStartsAt = nil
        task = nil
        if mode == .local { recorder.stop() }
        mode = nil
        phase = .idle
        message = text
    }

    private func scheduleTimeout(seconds: Double, _ action: @escaping () -> Void) {
        timeout?.cancel()
        let item = DispatchWorkItem(block: action)
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}
