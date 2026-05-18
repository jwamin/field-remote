import SwiftUI
import FoundationModels
import UniformTypeIdentifiers

struct ChartImportView: View {
    let deviceName: String?
    let onSave: ([MIDIControlDef]) -> Void

    @State private var chartText = ""
    @State private var parseState: ParseState = .idle
    @State private var showFilePicker = false
    @FocusState private var editorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    enum ParseState {
        case idle, extracting, parsing(Int, Int), done([MIDIControlDef]), failed(String)

        var isWorking: Bool {
            switch self { case .extracting, .parsing: return true; default: return false }
        }
    }

    // MARK: - Context budget helpers

    // The model sees the preprocessed version of whatever is in the editor:
    // raw HTML is stripped, then the same normalization pipeline runs as for file imports.
    private var normalizedInput: String {
        MIDIChartParser.preprocessText(chartText)
    }

    // Estimated number of model passes (chunks) for the normalized text.
    // Matches the 1800-char chunk size used in MIDIChartParser.chunk().
    private var estimatedChunks: Int {
        let n = normalizedInput.count
        guard n > 0 else { return 0 }
        return max(1, Int((Double(n) / 1800.0).rounded(.up)))
    }

    private func budgetColor(chunks: Int) -> Color {
        switch chunks {
        case 1:    return .green
        case 2...3: return .yellow
        default:   return .orange
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                availabilityBanner
                textArea
                contextGuide
                statusArea
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
            .navigationTitle("import chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showFilePicker = true } label: {
                        Label("open file", systemImage: "folder")
                    }
                    .disabled(parseState.isWorking)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    parseButton
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .html, .plainText]
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var availabilityBanner: some View {
        let model = SystemLanguageModel.default
        if case .unavailable(let reason) = model.availability {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text(unavailableMessage(for: reason))
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
        }
    }

    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $chartText)
                .font(.system(.caption, design: .monospaced))
                .padding(4)
                .focused($editorFocused)
            if chartText.isEmpty {
                Text("paste or import a MIDI implementation chart…")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding()
    }

    // Shows how much of the model's context window the normalized text consumes,
    // and offers to replace the editor content with the normalized version for manual trimming.
    @ViewBuilder
    private var contextGuide: some View {
        if !chartText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contextGuideContent
                .padding(.horizontal)
                .padding(.bottom, 10)
            Divider()
        }
    }

    private var contextGuideContent: some View {
        let normalized  = normalizedInput
        let charCount   = normalized.count
        let chunks      = estimatedChunks
        // Normalization meaningfully changed the text (not just trimming)
        let canNormalize = normalized != chartText.trimmingCharacters(in: .whitespacesAndNewlines)
        let overBudget   = chunks > 1

        return VStack(alignment: .leading, spacing: 6) {

            // Fill bar — full width = 5 passes (9000 chars); colour tracks severity
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(budgetColor(chunks: chunks))
                            .frame(width: geo.size.width * min(1, Double(charCount) / 9000))
                    }
                }
                .frame(height: 4)

                Text("~\(charCount)c · \(chunks) \(chunks == 1 ? "pass" : "passes")")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(budgetColor(chunks: chunks))
                    .fixedSize()
            }

            if overBudget && canNormalize {
                // Prominent prompt when input spans multiple model calls
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("spans \(chunks) model passes — normalize to trim noise and reduce size")
                        .font(.system(.caption2, design: .monospaced))
                    Spacer()
                }
                .foregroundStyle(.orange)

                Button {
                    chartText = normalized
                    editorFocused = false
                } label: {
                    Text("use normalized text for editing")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Color.orange.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

            } else if canNormalize {
                // Subtle hint when within budget but normalization still helps
                HStack {
                    Text("normalization removes noise · \(chartText.count) → \(charCount) chars")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("normalize") {
                        chartText = normalized
                        editorFocused = false
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch parseState {
        case .idle:
            EmptyView()
        case .extracting:
            Label("reading file…", systemImage: "doc.text.magnifyingglass")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        case .parsing(let cur, let total):
            Label("parsing section \(cur) of \(total)…", systemImage: "cpu")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        case .done(let controls):
            VStack(alignment: .leading, spacing: 8) {
                Label("found \(controls.count) control\(controls.count == 1 ? "" : "s")",
                      systemImage: "checkmark.circle")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)
                Button {
                    onSave(controls)
                    dismiss()
                } label: {
                    Text("save \(controls.count) control\(controls.count == 1 ? "" : "s")\(deviceName.map { " for \($0)" } ?? "")")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        case .failed(let message):
            Label(message, systemImage: "xmark.circle")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.red)
        }
    }

    private var parseButton: some View {
        Button(action: runParse) {
            if parseState.isWorking {
                ProgressView().controlSize(.small)
            } else {
                Text("parse")
                    .font(.system(.body, design: .monospaced))
            }
        }
        .disabled(chartText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || parseState.isWorking)
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            parseState = .extracting
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    chartText = try await MIDIChartParser.extractText(from: url)
                    parseState = .idle
                } catch {
                    parseState = .failed(error.localizedDescription)
                }
            }
        case .failure(let error):
            parseState = .failed(error.localizedDescription)
        }
    }

    private func runParse() {
        parseState = .parsing(1, 1)
        let text = chartText
        Task {
            do {
                let controls = try await MIDIChartParser.parse(text: text) { cur, total in
                    Task { @MainActor in parseState = .parsing(cur, total) }
                }
                parseState = .done(controls)
            } catch {
                parseState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func unavailableMessage(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "apple intelligence not supported on this device"
        case .appleIntelligenceNotEnabled:
            return "enable apple intelligence in settings to parse charts"
        case .modelNotReady:
            return "apple intelligence model is downloading — try again soon"
        default:
            return "apple intelligence is unavailable"
        }
    }
}
