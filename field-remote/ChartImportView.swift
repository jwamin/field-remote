import SwiftUI
import FoundationModels
import UniformTypeIdentifiers

struct ChartImportView: View {
    let deviceName: String
    let onSave: ([MIDIControlDef]) -> Void

    @State private var chartText = ""
    @State private var parseState: ParseState = .idle
    @State private var showFilePicker = false
    @Environment(\.dismiss) private var dismiss

    enum ParseState {
        case idle, extracting, parsing(Int, Int), done([MIDIControlDef]), failed(String)

        var isWorking: Bool {
            switch self { case .extracting, .parsing: return true; default: return false }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                availabilityBanner
                textArea
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
                    Text("save \(controls.count) control\(controls.count == 1 ? "" : "s") for \(deviceName)")
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
                    chartText = try MIDIChartParser.extractText(from: url)
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
