import AppKit

/// AppKit text fields dispatch keyboard editing shortcuts through the main
/// menu. A status-bar menu alone does not provide copy/paste/select-all.
@MainActor
enum ApplicationMenu {
    static func install() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let application = NSMenu(title: "Local Flow")
        application.addItem(withTitle: "Über Local Flow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "Einstellungen…", action: Selector(("openSettings")), keyEquivalent: ",")
        application.addItem(.separator())
        application.addItem(withTitle: "Local Flow beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = application
        main.addItem(applicationItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Rückgängig", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einfügen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
