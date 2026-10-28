import AppKit
import RouterCore
import SwiftUI

/// "Which profile?" for a link no rule covers, when there's no Jev key. A small floating panel by
/// the cursor that doesn't take focus from your app: press 1–N (or click) to pick, Esc for the
/// default profile. "Always for …" saves your answer as a rule, so each site is asked about once.
/// Links that arrive while it's open wait their turn.
@MainActor
final class ProfilePicker {
    static let shared = ProfilePicker()

    struct Question {
        let url: URL
        let profiles: [String]
        let defaultProfile: String
        /// The rules this link could save, broadest first ("all of example.com", …).
        let scopes: [RuleKey]
    }

    struct Answer {
        let profileName: String
        /// The rule to save, if "Always for …" was ticked.
        let remember: RuleKey?
    }

    private var panel: PickerPanel?
    private var queue: [(question: Question, continuation: CheckedContinuation<Answer?, Never>)] = []

    /// The profile to open `question.url` in, or nil for the default profile (Esc).
    func ask(_ question: Question) async -> Answer? {
        await withCheckedContinuation { continuation in
            queue.append((question, continuation))
            if queue.count == 1 { show(question) }
        }
    }

    private func show(_ question: Question) {
        let model = ProfilePickerModel(question: question, waiting: queue.count - 1) { [weak self] answer in
            self?.answer(answer)
        }
        let panel = self.panel ?? PickerPanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: ProfilePickerView(model: model).environmentObject(ProfilesMonitor.shared))
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.place(near: NSEvent.mouseLocation)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func answer(_ answer: Answer?) {
        guard !queue.isEmpty else { return }
        let (_, continuation) = queue.removeFirst()
        continuation.resume(returning: answer)
        if let next = queue.first {
            show(next.question)
        } else {
            panel?.orderOut(nil)
        }
    }
}

/// Floats above other apps and takes key presses without activating Switchyard (like Spotlight),
/// so the app you clicked in stays in front.
private final class PickerPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }

    /// Just below and right of the cursor, kept on the cursor's screen.
    func place(near point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var origin = NSPoint(x: point.x + 12, y: point.y - frame.height - 12)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        setFrameOrigin(origin)
    }
}

@MainActor
final class ProfilePickerModel: ObservableObject {
    let question: ProfilePicker.Question
    let waiting: Int
    @Published var remember = true
    @Published var scope: RuleKey?
    private let done: (ProfilePicker.Answer?) -> Void

    init(question: ProfilePicker.Question, waiting: Int, done: @escaping (ProfilePicker.Answer?) -> Void) {
        self.question = question
        self.waiting = waiting
        self.done = done
        scope = question.scopes.first
    }

    func pick(_ profile: String) {
        done(.init(profileName: profile, remember: remember ? scope : nil))
    }

    func useDefault() {
        done(nil)
    }
}

struct ProfilePickerView: View {
    @ObservedObject var model: ProfilePickerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open in which profile?")
                    .font(.headline)
                Text(model.question.url.displayHost)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(spacing: 4) {
                ForEach(Array(model.question.profiles.prefix(9).enumerated()), id: \.element) { index, name in
                    Button { model.pick(name) } label: {
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            ProfileDot(name: name)
                            Text(name)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    .accessibilityLabel("Open in \(name)")
                }
            }

            if !model.question.scopes.isEmpty {
                HStack(spacing: 6) {
                    Toggle(isOn: $model.remember) { Text("Always for") }
                        .toggleStyle(.checkbox)
                        .fixedSize()
                    Picker("", selection: $model.scope) {
                        ForEach(model.question.scopes, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(!model.remember)
                    .accessibilityLabel("Which links to remember this for")
                }
                .font(.callout)
            }

            HStack {
                Button("Esc: \(model.question.defaultProfile)") { model.useDefault() }
                    .buttonStyle(.link)
                    .keyboardShortcut(.cancelAction)
                    .font(.caption)
                Spacer()
                if model.waiting > 0 {
                    Text("\(model.waiting) more waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 330)
    }
}
