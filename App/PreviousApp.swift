import UIKit

/// Vuelve a la app desde la que se abrió Leonera Keyboard, como el botón «◀︎» de la
/// barra de estado.
///
/// iOS no tiene API pública para esto. Al abrir la app desde otra, el sistema le pasa
/// una `UISystemNavigationAction` (la que muestra «◀︎») y responderle con su destino
/// hace lo mismo que tocar ese botón. La acción se busca en la aplicación y en sus
/// escenas, según la versión de iOS.
enum PreviousApp {
    /// Devuelve `false` si no hay app anterior a la que volver.
    @discardableResult
    static func open() -> Bool {
        guard let action = navigationAction() else { return false }
        let destinationsSelector = NSSelectorFromString("destinations")
        let sendSelector = NSSelectorFromString("sendResponseForDestination:")
        guard action.responds(to: destinationsSelector), action.responds(to: sendSelector),
              let destinations = action.perform(destinationsSelector)?.takeUnretainedValue() as? [NSNumber],
              let destination = destinations.first
        else { return false }
        typealias SendResponse = @convention(c) (NSObject, Selector, UInt) -> Bool
        let send = unsafeBitCast(action.method(for: sendSelector), to: SendResponse.self)
        return send(action, sendSelector, destination.uintValue)
    }

    private static func navigationAction() -> NSObject? {
        let application = UIApplication.shared
        if let ivar = class_getInstanceVariable(UIApplication.self, "_systemNavigationAction"),
           let action = object_getIvar(application, ivar) as? NSObject {
            return action
        }
        let selector = NSSelectorFromString("_systemNavigationAction")
        let candidates: [NSObject] = [application] + application.connectedScenes.map { $0 as NSObject }
        for candidate in candidates where candidate.responds(to: selector) {
            if let action = candidate.perform(selector)?.takeUnretainedValue() as? NSObject {
                return action
            }
        }
        return nil
    }
}
