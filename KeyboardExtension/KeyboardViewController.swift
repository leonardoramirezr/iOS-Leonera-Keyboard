import AudioToolbox
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let state = KeyboardState()
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private var lastShiftTap = Date.distantPast
    private let haptics = HapticFeedback()
    private var configurationObserver: DarwinNotificationObserver?
    private let dictation = DictationController()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Los ajustes solo se leían en `viewWillAppear`, que no se llama al volver a primer
        // plano con el teclado ya abierto, así que un cambio hecho en la app (p. ej. desactivar
        // la vibración) no se aplicaba. Se recargan también al reactivarse la app anfitriona
        // y en cuanto la app avisa de que guardó.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hostDidBecomeActive),
            name: .NSExtensionHostDidBecomeActive,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hostDidEnterBackground),
            name: .NSExtensionHostDidEnterBackground,
            object: nil
        )
        configurationObserver = DarwinNotificationObserver(name: ConfigurationStorage.didChangeNotification) { [weak self] in
            self?.reloadConfiguration()
        }
        setUpDictation()
        state.playKeyFeedback = { [weak self] in
            self?.playFeedback()
        }

        let root = KeyboardRootView(state: state, dictation: dictation) { [weak self] action in
            self?.perform(action)
        }
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.4, *) {
            host.safeAreaRegions = []
        }

        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let height = view.heightAnchor.constraint(equalToConstant: state.keyboardHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true

        hostingController = host
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        state.showingEmoji = false
        state.showingDictation = false
        state.needsInputModeSwitchKey = needsInputModeSwitchKey
        reloadConfiguration()
        updateAutoCapitalization()
        if hasFullAccess { ConfigurationStorage.markKeyboardAccess() }
        // Si la app está grabando para el teclado, responde y se vuelve a mostrar el panel.
        dictation.refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dictation.keyboardWillDisappear()
    }

    @objc private func hostDidBecomeActive() {
        reloadConfiguration()
        dictation.refresh()
    }

    @objc private func hostDidEnterBackground() {
        dictation.hostDidEnterBackground()
    }

    @objc private func reloadConfiguration() {
        state.reload()
        heightConstraint?.constant = state.keyboardHeight
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if state.needsInputModeSwitchKey != needsInputModeSwitchKey {
            state.needsInputModeSwitchKey = needsInputModeSwitchKey
            heightConstraint?.constant = state.keyboardHeight
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAutoCapitalization()
    }

    // MARK: - Acciones

    /// La vibración no se reproduce aquí sino al tocar la tecla (`KeyboardState.playKeyFeedback`).
    func perform(_ action: KeyAction) {
        let proxy = textDocumentProxy

        switch action.type {
        case .character:
            guard !action.text.isEmpty else { break }
            let text = state.shift == .off ? action.text : action.text.uppercased()
            proxy.insertText(text)
            if state.shift == .on { state.shift = .off }
        case .space:
            proxy.insertText(" ")
        case .backspace:
            proxy.deleteBackward()
        case .deleteWord:
            deleteWordBackward()
        case .shift:
            toggleShift()
            return
        case .capsLock:
            state.shift = state.shift == .locked ? .off : .locked
            return
        case .returnKey:
            proxy.insertText("\n")
        case .tab:
            proxy.insertText("\t")
        case .dismissKeyboard:
            dismissKeyboard()
            return
        case .nextKeyboard:
            advanceToNextInputMode()
            return
        case .emoji:
            state.showingEmoji = true
            return
        case .dictation:
            state.showingEmoji = false
            state.showingDictation = true
            dictation.refresh()
            return
        case .paste:
            if hasFullAccess, let text = UIPasteboard.general.string, !text.isEmpty {
                proxy.insertText(text)
            }
        case .copy:
            if hasFullAccess, let text = proxy.selectedText, !text.isEmpty {
                UIPasteboard.general.string = text
            }
            return
        case .cut:
            if hasFullAccess, let text = proxy.selectedText, !text.isEmpty {
                UIPasteboard.general.string = text
                proxy.deleteBackward()
            }
        case .cursorLeft:
            proxy.adjustTextPosition(byCharacterOffset: -1)
        case .cursorRight:
            proxy.adjustTextPosition(byCharacterOffset: 1)
        case .none:
            return
        }

        updateAutoCapitalization()
    }

    // MARK: - Dictado

    private func setUpDictation() {
        dictation.insertText = { [weak self] text in
            self?.insertDictatedText(text)
        }
        dictation.openURL = { [weak self] url in
            self?.openContainingApp(url) ?? false
        }
        dictation.hasFullAccess = { [weak self] in
            self?.hasFullAccess ?? false
        }
        dictation.onAppRecording = { [weak self] in
            self?.state.showingEmoji = false
            self?.state.showingDictation = true
        }
    }

    /// Inserta el texto dictado separándolo con un espacio de la palabra anterior.
    private func insertDictatedText(_ text: String) {
        let proxy = textDocumentProxy
        var text = text
        if let last = proxy.documentContextBeforeInput?.last, !last.isWhitespace,
           let first = text.first, !first.isPunctuation {
            text = " " + text
        }
        proxy.insertText(text)
        updateAutoCapitalization()
    }

    /// Las extensiones no pueden usar `UIApplication.shared`, así que se busca la
    /// aplicación en la cadena de respondedores y se llama a
    /// `openURL:options:completionHandler:` directamente.
    private func openContainingApp(_ url: URL) -> Bool {
        let selector = sel_registerName("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                typealias OpenURL = @convention(c) (NSObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(current.method(for: selector), to: OpenURL.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func toggleShift() {
        let now = Date()
        defer { lastShiftTap = now }

        if state.shift == .locked {
            state.shift = .off
        } else if now.timeIntervalSince(lastShiftTap) < 0.35 {
            state.shift = .locked
        } else {
            state.shift = state.shift == .off ? .on : .off
        }
    }

    private func deleteWordBackward() {
        let proxy = textDocumentProxy
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else {
            proxy.deleteBackward()
            return
        }

        var characters = Array(before)
        var count = 0
        while let last = characters.last, last.isWhitespace {
            characters.removeLast()
            count += 1
        }
        while let last = characters.last, !last.isWhitespace, !last.isPunctuation {
            characters.removeLast()
            count += 1
        }
        for _ in 0..<max(count, 1) {
            proxy.deleteBackward()
        }
    }

    private func updateAutoCapitalization() {
        guard state.settings.autoCapitalize, state.shift != .locked else { return }

        let proxy = textDocumentProxy
        let type = proxy.autocapitalizationType ?? .sentences
        let before = proxy.documentContextBeforeInput ?? ""
        let shouldCapitalize: Bool

        switch type {
        case .none:
            return
        case .allCharacters:
            shouldCapitalize = true
        case .words:
            shouldCapitalize = before.last.map { $0.isWhitespace } ?? true
        default:
            shouldCapitalize = Self.isStartOfSentence(before)
        }

        state.shift = shouldCapitalize ? .on : .off
    }

    private static func isStartOfSentence(_ text: String) -> Bool {
        guard let last = text.last else { return true }
        if last.isNewline { return true }
        guard last.isWhitespace else { return false }

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let lastNonSpace = trimmed.last else { return true }
        return lastNonSpace.isNewline || ".!?".contains(lastNonSpace)
    }

    /// No espera a la vibración ni al sonido: ambos se reproducen en segundo plano.
    private func playFeedback() {
        let settings = state.settings
        guard settings.haptics || settings.keyClicks, hasFullAccess else { return }
        if settings.haptics {
            haptics.play(settings)
        }
        if settings.keyClicks {
            AudioServicesPlaySystemSound(1104)
        }
    }
}
