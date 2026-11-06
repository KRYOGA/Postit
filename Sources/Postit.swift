import Carbon.HIToolbox
import SwiftUI

struct NoteBackground: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    static let standard = Self(red: 1, green: 0.94, blue: 0.68, opacity: 1)

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    var textColor: Color {
        let luminance = [red, green, blue].map { component in
            let blended = component * opacity + 0.93 * (1 - opacity)
            return blended <= 0.04045
                ? blended / 12.92
                : pow((blended + 0.055) / 1.055, 2.4)
        }
        let contrast = 0.2126 * luminance[0] + 0.7152 * luminance[1] + 0.0722 * luminance[2]
        return contrast > 0.179 ? .black : .white
    }
}

struct Note: Identifiable, Codable {
    var id = UUID()
    var text = ""
    var background: NoteBackground?

    var title: String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Empty Note"
    }
}

final class Notes: ObservableObject {
    @Published private(set) var items: [Note]
    @Published var saveError: String?
    @Published private(set) var background: NoteBackground = .standard
    private let file: URL
    private var canSave = true

    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Postit", isDirectory: true)
            .appendingPathComponent("notes.json")
        items = []
        do {
            items = try JSONDecoder().decode([Note].self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            items = [Note()]
        } catch {
            canSave = false
            saveError = "Failed to read saved notes.\n\(error.localizedDescription)"
        }
        if let data = UserDefaults.standard.data(forKey: "sharedNoteBackground"),
           let saved = try? JSONDecoder().decode(NoteBackground.self, from: data) {
            background = saved
        } else {
            // Keep the first existing custom background until a shared setting is saved.
            background = items.compactMap(\.background).first ?? .standard
        }
    }

    var isEditable: Bool { canSave }

    func add() -> UUID {
        let note = Note()
        items.insert(note, at: 0)
        save()
        return note.id
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func update(_ id: UUID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = text
        save()
    }

    func updateBackground(_ value: NoteBackground) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: "sharedNoteBackground")
        background = value
    }

    func save() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: file, options: .atomic)
            saveError = nil
        } catch {
            saveError = "Failed to save notes.\n\(error.localizedDescription)"
        }
    }
}

// Configure only the containing window; keep text and controls fully opaque.
struct WindowBackground: NSViewRepresentable {
    var transparent: Bool

    final class WindowView: NSView {
        var transparent = false

        func apply() {
            guard let window else { return }
            window.isOpaque = !transparent
            window.backgroundColor = transparent ? .clear : .windowBackgroundColor
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }
    }

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.transparent = transparent
        return view
    }

    func updateNSView(_ view: WindowView, context: Context) {
        view.transparent = transparent
        view.apply()
    }
}

struct PostitView: View {
    @AppStorage("transparentBackground") private var transparentBackground = false
    @ObservedObject var notes: Notes
    @State private var selection: UUID?
    @State private var pendingDelete: UUID?
    @State private var showingBackground = false
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(notes.items) { note in
                    Text(note.title)
                        .lineLimit(1)
                        .tag(note.id)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 170)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                if let error = notes.saveError {
                    HStack {
                        Text(error).font(.callout)
                        if notes.isEditable {
                            Button("Retry") { notes.save() }
                        }
                    }
                    .padding()
                }
                if let id = selection, notes.items.contains(where: { $0.id == id }) {
                    let background = notes.background
                    TextEditor(text: Binding(
                        get: { notes.items.first { $0.id == id }?.text ?? "" },
                        set: { notes.update(id, text: $0) }
                    ))
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(background.textColor)
                    .preferredColorScheme(.light)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
                    .background(Color(.sRGB, red: background.red, green: background.green,
                                      blue: background.blue, opacity: transparentBackground ? background.opacity : 1))
                    .focused($editing)
                    .id(id)
                } else {
                    Text(notes.isEditable ? "Select a note or press + to add one" : "Cannot open note")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 300)
        .background(WindowBackground(transparent: transparentBackground))
        .onAppear { selection = selection ?? notes.items.first?.id }
        .toolbar {
            ToolbarItemGroup {
                Group {
                    Button { showingBackground.toggle() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "paintpalette")
                            Text("Background")
                        }
                    }
                    .help("Change background color and transparency")
                    .popover(isPresented: $showingBackground) {
                        backgroundSettings()
                    }
                    .disabled(!notes.isEditable)
                }

                Button {
                    selection = notes.add()
                    editing = true
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
                .keyboardShortcut("n")
                .disabled(!notes.isEditable)

                Button {
                    pendingDelete = selection
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
                .disabled(selection == nil || !notes.isEditable)
            }
        }
        .alert("Delete this note?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                guard let id = pendingDelete else { return }
                notes.remove(id)
                selection = notes.items.first?.id
                pendingDelete = nil
            }
        }
    }

    private func backgroundSettings() -> some View {
        let background = notes.background
        return VStack(alignment: .leading, spacing: 16) {
            Text("Background Settings").font(.headline)
            ColorPicker("Background Color", selection: Binding(
                get: {
                    let value = notes.background
                    return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: 1)
                },
                set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    var value = notes.background
                    value.red = rgb.redComponent
                    value.green = rgb.greenComponent
                    value.blue = rgb.blueComponent
                    notes.updateBackground(value)
                }
            ), supportsOpacity: false)
            Divider()
            Toggle("Transparent Background", isOn: $transparentBackground)
                .toggleStyle(.switch)
            Text("Show windows behind the note while keeping text clear. This switch applies to all notes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                HStack {
                    Text("Transparency")
                    Spacer()
                    Text("\(Int(((1 - background.opacity) * 100).rounded()))%")
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { 1 - (notes.background).opacity },
                    set: { transparency in
                        var value = notes.background
                        value.opacity = 1 - transparency
                        notes.updateBackground(value)
                    }
                ), in: 0...1)
                .accessibilityLabel("Transparency")
                HStack {
                    Text("Opaque")
                    Spacer()
                    Text("Transparent")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .disabled(!transparentBackground)
            Text(transparentBackground ? "Background settings are saved and apply to all existing and new notes." : "Enable Transparent Background to adjust transparency.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 300)
    }

}

final class PostitDelegate: NSObject, NSApplicationDelegate {
    var showWindow: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        let target = GetApplicationEventTarget()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x50535454, id.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let delegate = Unmanaged<PostitDelegate>.fromOpaque(context).takeUnretainedValue()
            delegate.showWindow?()
            return noErr
        }, 1, &event, context, &handler)

        if handlerStatus == noErr {
            let id = EventHotKeyID(signature: 0x50535454, id: 1)
            let modifiers = UInt32(controlKey | optionKey | cmdKey)
            if RegisterEventHotKey(UInt32(kVK_ANSI_P), modifiers, id, target, 0, &hotKey) == noErr {
                return
            }
        }

        let alert = NSAlert()
        alert.messageText = "Failed to register note shortcut"
        alert.informativeText = "If ⌃⌥⌘P is being used by another application, please change its setting and restart the app."
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct PostitWindow: View {
    @Environment(\.openWindow) private var openWindow
    let notes: Notes
    let delegate: PostitDelegate

    var body: some View {
        PostitView(notes: notes)
            .onAppear {
                let open = openWindow
                delegate.showWindow = {
                    NSApp.activate(ignoringOtherApps: true)
                    open(id: "postit")
                }
            }
    }
}

@main
struct PostitApp: App {
    @StateObject private var notes = Notes()
    @NSApplicationDelegateAdaptor(PostitDelegate.self) private var delegate

    var body: some Scene {
        Window("Postit", id: "postit") {
            PostitWindow(notes: notes, delegate: delegate)
        }
        .defaultSize(width: 620, height: 400)
    }
}
