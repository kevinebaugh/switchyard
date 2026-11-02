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
        /// When Jev was asked but unsure: its guess (also the Esc choice) and confidence.
        var jevGuess: (profile: String, confidence: Double)? = nil
        /// The scope to preselect (Jev's, when it gave one).
        var preferredScope: RuleKey? = nil
        /// With several browsers: each label's browser (a section header) and short name
        /// ("Firefox", "Personal"). Nil with one browser.
        var sections: [String: (browser: String, name: String)]? = nil
    }

    struct Answer {
        let profileName: String
        /// The rule to save, if "Always for …" was ticked.
        let remember: RuleKey?
    }

    /// Jev's guess, when it arrives after the picker is already open.
    struct Guess: Sendable {
        let profile: String
        let confidence: Double
        let scope: RuleKey?
    }

    private var panel: PickerPanel?
    private var queue: [(question: Question, guess: Task<Guess?, Never>?, continuation: CheckedContinuation<Answer?, Never>)] = []
    private var shownModel: ProfilePickerModel?

    /// The profile to open `question.url` in, or nil for the default profile (Esc). `laterGuess`
    /// fills in Jev's guess while the picker is open (it's asked in parallel, so the picker never
    /// waits for it).
    func ask(_ question: Question, laterGuess: Task<Guess?, Never>? = nil) async -> Answer? {
        await withCheckedContinuation { continuation in
            queue.append((question, laterGuess, continuation))
            if queue.count == 1 { show(question, laterGuess: laterGuess) }
        }
    }

    private func show(_ question: Question, laterGuess: Task<Guess?, Never>?) {
        let model = ProfilePickerModel(question: question, waiting: queue.count - 1) { [weak self] answer in
            self?.answer(answer)
        }
        shownModel = model
        if let laterGuess {
            Task { [weak self] in
                guard let guess = await laterGuess.value, self?.shownModel === model else { return }
                model.apply(guess)
                self?.panel?.setContentSize(self?.panel?.contentView?.fittingSize ?? .zero)
            }
        }
        let panel = self.panel ?? PickerPanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: ProfilePickerView(model: model).environmentObject(ProfilesMonitor.shared))
        // The title bar is hidden but still reserves its height; let the content use it.
        hosting.safeAreaRegions = []
        panel.contentView = hosting
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.place(near: NSEvent.mouseLocation)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func answer(_ answer: Answer?) {
        guard !queue.isEmpty else { return }
        let (_, _, continuation) = queue.removeFirst()
        continuation.resume(returning: answer)
        if let next = queue.first {
            show(next.question, laterGuess: next.guess)
        } else {
            shownModel = nil
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
    @Published var scope: RuleKey? {
        didSet { if !applyingGuess { scopeChosen = true } }
    }
    /// Jev's guess: from the question, or arriving while the picker is open.
    @Published private(set) var jevGuess: (profile: String, confidence: Double)?
    private var scopeChosen = false
    private var applyingGuess = false
    private let done: (ProfilePicker.Answer?) -> Void

    init(question: ProfilePicker.Question, waiting: Int, done: @escaping (ProfilePicker.Answer?) -> Void) {
        self.question = question
        self.waiting = waiting
        self.done = done
        jevGuess = question.jevGuess
        applyingGuess = true
        scope = question.preferredScope.flatMap { question.scopes.contains($0) ? $0 : nil } ?? question.scopes.first
        applyingGuess = false
    }

    /// What Esc opens: Jev's guess once there is one, otherwise the default profile.
    var escapeProfile: String { jevGuess?.profile ?? question.defaultProfile }

    /// Jev answered while the picker was open: mark its guess, and take its scope unless you've
    /// already chosen one.
    func apply(_ guess: ProfilePicker.Guess) {
        guard question.profiles.contains(where: { $0.caseInsensitiveCompare(guess.profile) == .orderedSame }) else { return }
        jevGuess = (guess.profile, guess.confidence)
        if !scopeChosen, let key = guess.scope, question.scopes.contains(key) {
            applyingGuess = true
            scope = key
            applyingGuess = false
        }
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

    /// A browser without profiles (Safari) after another browser's group: set apart by a divider.
    private func startsProfilelessBrowser(at index: Int) -> Bool {
        guard index > 0, let sections = model.question.sections,
              let section = sections[model.question.profiles[index]] else { return false }
        return section.name == section.browser
            && sections[model.question.profiles[index - 1]]?.browser != section.browser
    }

    /// The browser's name above the first of its destinations, with several browsers.
    private func sectionHeader(at index: Int) -> String? {
        guard let sections = model.question.sections else { return nil }
        let profiles = model.question.profiles
        guard let section = sections[profiles[index]] else { return nil }
        // A browser without profiles (Safari) is a row of its own, not a header over one row.
        guard section.name != section.browser else { return nil }
        guard index == 0 || sections[profiles[index - 1]]?.browser != section.browser else { return nil }
        return section.browser
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.question.sections == nil ? "Open in which profile?" : "Where should this open?")
                    .font(.headline)
                Text(model.question.url.displayHost)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(spacing: 4) {
                ForEach(Array(model.question.profiles.prefix(9).enumerated()), id: \.element) { index, name in
                    if startsProfilelessBrowser(at: index) {
                        Divider().padding(.vertical, 4)
                    } else if let header = sectionHeader(at: index) {
                        Text(header)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, index == 0 ? 0 : 6)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Button { model.pick(name) } label: {
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            ProfileDot(name: name)
                            Text(model.question.sections?[name]?.name ?? name)
                            Spacer()
                            if let guess = model.jevGuess, guess.profile.caseInsensitiveCompare(name) == .orderedSame {
                                Text("Jev's guess · \(guess.confidence.confidenceLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                Button(model.jevGuess == nil ? "Esc: \(model.escapeProfile)" : "Esc: \(model.escapeProfile) (Jev's guess)") { model.useDefault() }
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
