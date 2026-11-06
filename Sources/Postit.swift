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
            .first { !$0.isEmpty } ?? "無題の付箋"
    }
}

final class Notes: ObservableObject {
    @Published private(set) var items: [Note]
    @Published var saveError: String?
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
            saveError = "保存済みの付箋を読み込めませんでした。\n\(error.localizedDescription)"
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

    func update(_ id: UUID, background: NoteBackground) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].background = background
        save()
    }

    func save() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: file, options: .atomic)
            saveError = nil
        } catch {
            saveError = "付箋を保存できませんでした。\n\(error.localizedDescription)"
        }
    }
}

struct PostitView: View {
    @ObservedObject var notes: Notes
    @State private var selection: UUID?
    @State private var pendingDelete: UUID?
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
                            Button("再試行") { notes.save() }
                        }
                    }
                    .padding()
                }
                if let id = selection, let note = notes.items.first(where: { $0.id == id }) {
                    let background = note.background ?? .standard
                    TextEditor(text: Binding(
                        get: { notes.items.first { $0.id == id }?.text ?? "" },
                        set: { notes.update(id, text: $0) }
                    ))
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(background.textColor)
                    .preferredColorScheme(.light)
                    .padding(14)
                    .background(background.color)
                    .focused($editing)
                    .id(id)
                } else {
                    Text(notes.isEditable ? "付箋を選択するか、＋で追加してください" : "付箋を開けません")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 300)
        .onAppear { selection = selection ?? notes.items.first?.id }
        .toolbar {
            ToolbarItemGroup {
                if let id = selection {
                    ColorPicker("背景色", selection: Binding(
                        get: { (notes.items.first { $0.id == id }?.background ?? .standard).color },
                        set: { color in
                            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                            notes.update(id, background: NoteBackground(
                                red: rgb.redComponent,
                                green: rgb.greenComponent,
                                blue: rgb.blueComponent,
                                opacity: rgb.alphaComponent
                            ))
                        }
                    ), supportsOpacity: true)
                    .labelsHidden()
                    .help("背景色と不透明度を変更")
                    .id(id)
                }

                Button {
                    selection = notes.add()
                    editing = true
                } label: {
                    Label("付箋を追加", systemImage: "plus")
                }
                .keyboardShortcut("n")
                .disabled(!notes.isEditable)

                Button {
                    pendingDelete = selection
                } label: {
                    Label("付箋を削除", systemImage: "trash")
                }
                .disabled(selection == nil || !notes.isEditable)
            }
        }
        .alert("この付箋を削除しますか？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("キャンセル", role: .cancel) { pendingDelete = nil }
            Button("削除", role: .destructive) {
                guard let id = pendingDelete else { return }
                notes.remove(id)
                selection = notes.items.first?.id
                pendingDelete = nil
            }
        }
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
        alert.messageText = "付箋のショートカットを登録できませんでした"
        alert.informativeText = "⌃⌥⌘P が別のアプリで使われている場合は、そちらの設定を変更してから付箋を起動し直してください。"
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
        Window("付箋", id: "postit") {
            PostitWindow(notes: notes, delegate: delegate)
        }
        .defaultSize(width: 620, height: 400)
    }
}
