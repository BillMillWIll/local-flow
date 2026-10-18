import AppKit
import LocalFlowCore

/// Native, searchable word list. Each observed error gets its own entry;
/// preferred spellings can also be saved without an error variant.
@MainActor
final class DictionaryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var dictionary: PersonalDictionary
    private let onChange: (PersonalDictionary) -> Void
    private let table = NSTableView()
    private let search = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let engineHint = NSTextField(wrappingLabelWithString: "")
    private let editButton = NSButton(title: "Bearbeiten…", target: nil, action: nil)
    private let removeButton = NSButton(title: "Entfernen", target: nil, action: nil)
    private let undoButton = NSButton(title: "Rückgängig", target: nil, action: nil)
    private let testField = NSTextField()
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private var filteredIndices: [Int] = []
    private var previousDictionary: PersonalDictionary?

    init(dictionary: PersonalDictionary, engine: RecognitionEngine, onChange: @escaping (PersonalDictionary) -> Void) {
        self.dictionary = dictionary
        self.onChange = onChange
        super.init(frame: .zero)
        configure()
        setEngine(engine)
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setEngine(_ engine: RecognitionEngine) {
        engineHint.stringValue = engine.supportsCustomWordPrompt
            ? "Whisper erhält deine Wörter als Erkennungshilfe. Gespeicherte Fehlvarianten werden zusätzlich korrigiert."
            : "\(engine.shortTitle): Fehlvarianten werden nach dem Erkennen korrigiert. Ein Wort allein legt die Schreibweise fest, trainiert die Erkennung aber nicht."
    }

    private func configure() {
        let title = NSTextField(labelWithString: "Dein Wörterbuch")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        engineHint.font = .systemFont(ofSize: 12)
        engineHint.textColor = .secondaryLabelColor
        search.placeholderString = "Wort oder Fehlvariante suchen"
        search.setAccessibilityLabel("Wörterbuch durchsuchen")
        search.delegate = self
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        for (identifier, title, width) in [("word", "Gewünschte Schreibweise", 240.0), ("heard", "Wird falsch erkannt als", 280.0)] {
            let column = NSTableColumn(identifier: .init(identifier))
            column.title = title
            column.width = width
            column.minWidth = 140
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 32
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(editEntry)
        table.setAccessibilityLabel("Gespeicherte Wörter und Fehlvarianten")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let add = NSButton(title: "Wort hinzufügen…", target: self, action: #selector(addEntry))
        add.bezelStyle = .rounded
        for (button, action) in [(editButton, #selector(editEntry)), (removeButton, #selector(removeEntry)), (undoButton, #selector(undoChange))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
        }
        let examples = NSPopUpButton(frame: .zero, pullsDown: true)
        examples.addItem(withTitle: "Beispiele")
        for (index, title) in ["Grok Bot → grokbot", "Chat GPT → ChatGPT", "Art Motion → ArtMotion"].enumerated() {
            examples.addItem(withTitle: title)
            examples.lastItem?.target = self
            examples.lastItem?.action = #selector(useExample(_:))
            examples.lastItem?.tag = index
        }
        let actions = row([add, editButton, removeButton, undoButton])
        let importButton = NSButton(title: "Mehrere Wörter einfügen…", target: self, action: #selector(importWords))
        importButton.bezelStyle = .rounded
        let helpers = row([examples, importButton])
        let testTitle = NSTextField(labelWithString: "Korrektur ausprobieren")
        testTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        testField.placeholderString = "Erkannten Text hier eingeben oder einfügen"
        testField.setAccessibilityLabel("Testtext für Wörterbuch")
        testField.delegate = self
        resultLabel.font = .systemFont(ofSize: 13)
        resultLabel.isSelectable = true
        resultLabel.maximumNumberOfLines = 3
        let note = NSTextField(wrappingLabelWithString: "Die Vorschau prüft gespeicherte Wörter und Ersetzungen. Für einen Sprachtest: Sprechen → Aufnahme testen.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [title, engineHint, search, countLabel, scroll, actions, helpers, separator, testTitle, testField, resultLabel, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 170),
            resultLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
        for view in [engineHint, search, scroll, separator, testField, resultLabel, note] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private var selectedIndex: Int? {
        guard filteredIndices.indices.contains(table.selectedRow) else { return nil }
        return filteredIndices[table.selectedRow]
    }

    private func reload() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredIndices = dictionary.entries.indices.filter {
            query.isEmpty || dictionary.entries[$0].word.localizedStandardContains(query) || dictionary.entries[$0].heard.localizedStandardContains(query)
        }
        table.reloadData()
        countLabel.stringValue = dictionary.entries.isEmpty
            ? "Noch keine Wörter. Füge einen Namen oder ein Fachwort hinzu."
            : filteredIndices.isEmpty ? "Keine passenden Wörter gefunden." : "\(filteredIndices.count) von \(dictionary.entries.count) Einträgen · Änderungen werden sofort gespeichert"
        updateButtons()
        updatePreview()
    }

    private func updateButtons() {
        editButton.isEnabled = selectedIndex != nil
        removeButton.isEnabled = selectedIndex != nil
        undoButton.isEnabled = previousDictionary != nil
    }

    // Text rules from the Text tab are included in the same preview.
    var replacementRules: [ReplacementRule] = [] { didSet { updatePreview() } }

    private func updatePreview() {
        let text = testField.stringValue
        guard !text.isEmpty else {
            resultLabel.stringValue = "Das Ergebnis erscheint hier."
            resultLabel.textColor = .secondaryLabelColor
            return
        }
        let result = ReplacementRules.apply(replacementRules, to: dictionary.apply(to: text))
        resultLabel.stringValue = result == text ? "Keine Änderung: \(result)" : result
        resultLabel.textColor = .labelColor
    }

    private func commit(_ next: PersonalDictionary) {
        previousDictionary = dictionary
        dictionary = next
        onChange(next)
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filteredIndices.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = dictionary.entries[filteredIndices[row]]
        let isWord = tableColumn?.identifier.rawValue == "word"
        let label = NSTextField(labelWithString: isWord ? entry.word : entry.heard.isEmpty ? "Nur Schreibweise" : entry.heard)
        label.font = .systemFont(ofSize: 13, weight: isWord ? .medium : .regular)
        label.textColor = !isWord && entry.heard.isEmpty ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = label.stringValue
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSSearchField === search { reload() }
        else { updatePreview() }
    }

    @objc private func addEntry() { showEditor(entry: .init(word: ""), index: nil) }

    @objc private func editEntry() {
        guard let index = selectedIndex else { return }
        showEditor(entry: dictionary.entries[index], index: index)
    }

    @objc private func removeEntry() {
        guard let index = selectedIndex else { return }
        var next = dictionary
        next.entries.remove(at: index)
        commit(next)
    }

    @objc private func undoChange() {
        guard let previous = previousDictionary else { return }
        dictionary = previous
        previousDictionary = nil
        onChange(dictionary)
        reload()
    }

    @objc private func useExample(_ item: NSMenuItem) {
        let examples = [DictionaryEntry(word: "grokbot", heard: "Grok Bot"), .init(word: "ChatGPT", heard: "Chat GPT"), .init(word: "ArtMotion", heard: "Art Motion")]
        guard examples.indices.contains(item.tag) else { return }
        showEditor(entry: examples[item.tag], index: nil)
    }

    @objc private func importWords() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Mehrere Wörter einfügen"
        alert.informativeText = "Ein Wort oder eine Wortgruppe pro Zeile. Bereits gespeicherte Wörter werden übersprungen. Fehlvarianten ergänzt du anschließend beim jeweiligen Wort."
        alert.addButton(withTitle: "Übernehmen")
        alert.addButton(withTitle: "Abbrechen")
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        editor.font = .systemFont(ofSize: 13)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.setAccessibilityLabel("Wörter, eines pro Zeile")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = editor
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let next = self.dictionary.addingWords(from: editor.string)
            let added = next.entries.count - self.dictionary.entries.count
            self.search.stringValue = ""
            if added > 0 { self.commit(next) }
            else { self.reload() }
            self.countLabel.stringValue = added > 0 ? "\(added) Wörter hinzugefügt · gespeichert" : "Keine neuen Wörter: Liste leer, bereits vorhanden oder durch eine Fehlvariante belegt."
        }
    }

    private func showEditor(entry: DictionaryEntry, index: Int?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = index == nil ? "Wort hinzufügen" : "Wort bearbeiten"
        alert.informativeText = "Trage eine tatsächlich erkannte Fehlvariante ein. Weitere Varianten kannst du als eigenen Eintrag mit derselben Schreibweise ergänzen."
        alert.addButton(withTitle: "Speichern")
        alert.addButton(withTitle: "Abbrechen")
        let word = NSTextField(string: entry.word)
        word.placeholderString = "z. B. grokbot"
        word.setAccessibilityLabel("Gewünschte Schreibweise")
        let heard = NSTextField(string: entry.heard)
        heard.placeholderString = "z. B. Grok Bot (optional)"
        heard.setAccessibilityLabel("Wird falsch erkannt als")
        let hint = NSTextField(wrappingLabelWithString: "Ohne Fehlvariante wird nur die Schreibweise festgelegt. Whisper erhält das Wort zusätzlich als Erkennungshilfe.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let form = NSStackView(views: [NSTextField(labelWithString: "Gewünschte Schreibweise"), word, NSTextField(labelWithString: "Wird falsch erkannt als · optional"), heard, hint])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.frame = NSRect(x: 0, y: 0, width: 420, height: 154)
        for view in [word, heard, hint] { view.widthAnchor.constraint(equalToConstant: 420).isActive = true }
        alert.accessoryView = form
        alert.window.initialFirstResponder = word
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let candidate = DictionaryEntry(word: word.stringValue, heard: heard.stringValue)
            if let message = self.dictionary.validationMessage(word: candidate.word, heard: candidate.heard, ignoring: index) {
                let warning = NSAlert()
                warning.messageText = "Eintrag prüfen"
                warning.informativeText = message
                warning.beginSheetModal(for: window) { _ in self.showEditor(entry: candidate, index: index) }
                return
            }
            var next = self.dictionary
            if let index { next.entries[index] = candidate }
            else { next.entries.append(candidate) }
            self.search.stringValue = ""
            self.commit(next)
        }
    }
}
