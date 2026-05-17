import Foundation
import FoundationModels
import PDFKit
import UniformTypeIdentifiers

// MARK: - Parser

enum MIDIChartParser {

    // MARK: - File text extraction

    static func extractText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try extractFromPDF(url)
        case "html", "htm":
            return try extractFromHTML(url)
        default:
            guard let text = (try? String(contentsOf: url, encoding: .utf8))
                          ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            else { throw ParserError.unreadableFile }
            return text
        }
    }

    private static func extractFromPDF(_ url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else { throw ParserError.unreadableFile }
        return (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    private static func extractFromHTML(_ url: URL) throws -> String {
        guard let html = (try? String(contentsOf: url, encoding: .utf8))
                      ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        else { throw ParserError.unreadableFile }
        // Strip script/style blocks, then all tags, then decode entities
        let text = html
            .replacingOccurrences(
                of: "<(script|style)[^>]*>[\\s\\S]*?</(script|style)>",
                with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#[0-9]+;", with: " ", options: .regularExpression)
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Parsing

    static func parse(
        text: String,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [MIDIControlDef] {
        guard case .available = SystemLanguageModel.default.availability else {
            throw ParserError.modelUnavailable
        }

        let chunks = chunk(text)
        var results: [MIDIControlDef] = []

        for (index, chunkText) in chunks.enumerated() {
            onProgress?(index + 1, chunks.count)

            let session = LanguageModelSession(instructions: """
                You parse MIDI implementation charts. Extract only CC (Control Change) \
                and Program Change entries. For each, produce: a short parameter name, \
                message type (cc or programChange), number (CC number 0-127 or program \
                number 0-127), MIDI channel 1-16 (use 1 if "all"), min value, max value, \
                and control style (slider=continuous, toggle=on/off boolean, \
                trigger=momentary or program change). Ignore note on/off, pitch bend, \
                aftertouch, SysEx, clock, and all other message types.
                """)

            let response = try await session.respond(
                to: "Parse MIDI controls from this chart section:\n\n\(chunkText)",
                generating: ParsedMIDIControlList.self
            )

            results += response.content.controls.map { MIDIControlDef(from: $0) }
        }

        // Deduplicate by (type, number, channel)
        var seen = Set<String>()
        return results.filter { def in
            let key = "\(def.messageType.rawValue)-\(def.number)-\(def.channel)"
            return seen.insert(key).inserted
        }
    }

    // MARK: - Chunking
    // Context budget: 4096 tokens.
    // ~400 tokens: instructions + schema. ~500 tokens: response.
    // Leaves ~3200 for chart text. At ~3 chars/token for dense tables: ~1800 chars/chunk.

    private static func chunk(_ text: String, maxChars: Int = 1800) -> [String] {
        guard text.count > maxChars else { return [text] }
        var chunks: [String] = []
        var current = ""
        for line in text.components(separatedBy: .newlines) {
            if !current.isEmpty, current.count + line.count + 1 > maxChars {
                chunks.append(current)
                current = line
            } else {
                current += (current.isEmpty ? "" : "\n") + line
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Errors

    enum ParserError: LocalizedError {
        case modelUnavailable
        case unreadableFile

        var errorDescription: String? {
            switch self {
            case .modelUnavailable:
                return "Apple Intelligence is not available on this device or is not enabled."
            case .unreadableFile:
                return "Could not read the selected file."
            }
        }
    }
}
