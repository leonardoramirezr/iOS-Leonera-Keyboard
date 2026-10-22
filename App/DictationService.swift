import AVFoundation
import SwiftUI

/// Graba para el teclado (ver `DictationBridge`).
///
/// Al abrirse con `leonerakeyboard://dictation` activa el micrófono y lo mantiene
/// abierto en segundo plano (modo de fondo «audio») para poder grabar cada vez que
/// el teclado lo pida. Si pasan `idleTimeout` segundos sin grabar, lo libera; sin el
/// cierre automático activado, también cuando el teclado lo pide.
final class DictationService: ObservableObject {
    static let idleTimeout: TimeInterval = 5 * 60

    @Published private(set) var isSessionActive = false
    @Published private(set) var isRecording = false
    @Published private(set) var lastError: String?
    /// Muestra la pantalla «Vuelve a la app anterior» tras abrirse desde el teclado.
    @Published var showsSessionScreen = false

    private let recorder = DictationRecorder()
    private var status = DictationBridge.Status()
    private var observers: [DarwinNotificationObserver] = []
    private var idleTimer: Timer?
    private var audioObservers: [NSObjectProtocol] = []
    /// Abierta desde el teclado: empieza a grabar cuando el usuario vuelva al teclado.
    private var recordsOnReturn = false
    private var pendingCapture: DispatchWorkItem?

    init() {
        observers = [
            DarwinNotificationObserver(name: DictationBridge.startNotification) { [weak self] in self?.beginCapture() },
            DarwinNotificationObserver(name: DictationBridge.stopNotification) { [weak self] in self?.finishCapture() },
            DarwinNotificationObserver(name: DictationBridge.cancelNotification) { [weak self] in self?.cancelCapture() },
            DarwinNotificationObserver(name: DictationBridge.pingNotification) { [weak self] in self?.publish() },
            DarwinNotificationObserver(name: DictationBridge.endSessionNotification) { [weak self] in self?.keyboardDidRelease() },
        ]
        let names: [Notification.Name] = [AVAudioSession.interruptionNotification, .AVAudioEngineConfigurationChange]
        audioObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.audioWasInterrupted()
            }
        }
        audioObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleCaptureAfterReturn()
        })
        // La app acaba de arrancar: el micrófono no está activo.
        update(DictationBridge.Status())
    }

    /// Abierta desde el teclado: activa el micrófono y, si se pide, empieza a grabar.
    func handle(_ url: URL) {
        guard url.scheme == DictationBridge.urlScheme, url.host == DictationBridge.urlHost else { return }
        let record = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains { $0.name == "record" && $0.value == "1" } ?? false
        showsSessionScreen = true
        startSession(thenRecord: record)
    }

    /// Pide permiso si hace falta y activa el micrófono.
    func startSession(thenRecord record: Bool = false) {
        DictationRecorder.requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.fail("Leonera Keyboard no tiene permiso para usar el micrófono. Actívalo en Ajustes › Leonera Keyboard.")
                return
            }
            do {
                try self.recorder.start()
                self.isSessionActive = true
                self.lastError = nil
                if record {
                    // Se graba al volver al teclado, no mientras se ve esta pantalla. Al abrirse
                    // desde una URL la app aún está «inactive», así que no se puede comprobar
                    // si está visible: se espera siempre a que pase a segundo plano.
                    self.recordsOnReturn = true
                    self.update(DictationBridge.Status(phase: .pending))
                    if UIApplication.shared.applicationState == .background {
                        self.scheduleCaptureAfterReturn()
                    }
                } else {
                    self.update(DictationBridge.Status(phase: .ready))
                    self.restartIdleTimer()
                }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    /// Libera el micrófono.
    func endSession() {
        cancelPendingCapture()
        idleTimer?.invalidate()
        recorder.stop()
        isSessionActive = false
        isRecording = false
        update(DictationBridge.Status())
    }

    func cancelCapture() {
        if status.phase == .pending {
            cancelPendingCapture()
            update(DictationBridge.Status(phase: .ready))
            restartIdleTimer()
            return
        }
        guard isRecording else { return publish() }
        _ = recorder.finishCapture()
        isRecording = false
        update(DictationBridge.Status(phase: .ready))
        restartIdleTimer()
    }

    // MARK: - Grabación

    /// La app pasó a segundo plano: si el teclado pidió grabar, empieza tras el retardo configurado.
    private func scheduleCaptureAfterReturn() {
        guard recordsOnReturn else { return }
        recordsOnReturn = false
        let delay = max(0, DictationSettingsStorage.load().recordingStartDelay)
        let work = DispatchWorkItem { [weak self] in
            self?.pendingCapture = nil
            self?.beginCapture()
        }
        pendingCapture = work
        // El teclado muestra la pantalla de grabación en cuanto vuelve y cuenta la espera.
        update(DictationBridge.Status(phase: .pending, startedAt: Date().addingTimeInterval(delay)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingCapture() {
        recordsOnReturn = false
        pendingCapture?.cancel()
        pendingCapture = nil
    }

    private func beginCapture() {
        cancelPendingCapture()
        guard recorder.isRunning else {
            // iOS no deja activar el micrófono desde segundo plano: solo se reintenta
            // con la app visible. Si no, el teclado abrirá la app.
            if UIApplication.shared.applicationState == .active {
                startSession(thenRecord: true)
            } else {
                fail("El micrófono se desactivó. Vuelve a tocar el botón de grabar para abrir la app.")
            }
            return
        }
        guard !isRecording else { return publish() }
        guard let url = DictationBridge.audioURL else {
            fail("No se encontró el App Group compartido: la app no puede pasar el audio al teclado.")
            return
        }
        do {
            try recorder.beginCapture(to: url)
            idleTimer?.invalidate()
            isRecording = true
            update(DictationBridge.Status(phase: .recording, startedAt: Date()))
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func finishCapture() {
        guard isRecording else { return publish() }
        let capture = recorder.finishCapture()
        isRecording = false
        restartIdleTimer()
        guard let capture, capture.frames > 0 else {
            fail("No se grabó audio.")
            return
        }
        update(DictationBridge.Status(phase: .finished, captureID: UUID()))
    }

    // MARK: - Estado

    private func update(_ newStatus: DictationBridge.Status) {
        status = newStatus
        publish()
    }

    /// Envía el estado actual al teclado (también responde a su `ping`).
    private func publish() {
        DictationBridge.publish(status)
    }

    private func fail(_ message: String) {
        lastError = message
        isRecording = false
        if !recorder.isRunning {
            isSessionActive = false
        }
        update(DictationBridge.Status(phase: .failed, message: message))
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleTimeout, repeats: false) { [weak self] _ in
            self?.endSession()
        }
    }

    /// El teclado pide cerrar el micrófono. Se ignora con la app visible: el aviso puede
    /// llegar justo cuando el teclado la abre para grabar, o venir del teclado usado
    /// dentro de la propia app.
    private func keyboardDidRelease() {
        guard isSessionActive, !recordsOnReturn, UIApplication.shared.applicationState != .active else { return }
        endSession()
    }

    /// Una llamada, Siri u otro cambio de audio detiene el micrófono.
    private func audioWasInterrupted() {
        guard isSessionActive, !recorder.isRunning else { return }
        endSession()
    }
}
