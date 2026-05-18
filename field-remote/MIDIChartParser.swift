import Foundation
import FoundationModels
import PDFKit
import UniformTypeIdentifiers

// MARK: - Parser

enum MIDIChartParser {

    // MARK: - File text extraction

    static func extractText(from url: URL) async throws -> String {
        let raw: String
        switch url.pathExtension.lowercased() {
        case "pdf":
            raw = try extractFromPDF(url)
        case "html", "htm":
            raw = try await extractFromHTMLDocument(url)
        default:
            guard let text = (try? String(contentsOf: url, encoding: .utf8))
                          ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            else { throw ParserError.unreadableFile }
            raw = text
        }
        return normalizeText(raw)
    }

    private static func extractFromPDF(_ url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else { throw ParserError.unreadableFile }
        return (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    // Parses HTML via NSAttributedString (WebKit-backed DOM parser).
    // Handles all tag attributes, inline styles, malformed markup, and every
    // named/numeric HTML entity correctly — no regex needed for the happy path.
    // WebKit requires the main thread, so the parse step is dispatched there;
    // disk I/O stays on the calling (background) thread.
    private static func extractFromHTMLDocument(_ url: URL) async throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw ParserError.unreadableFile }

        for encoding in [String.Encoding.utf8, .isoLatin1] {
            let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: encoding.rawValue,
            ]
            // NSAttributedString HTML parsing is WebKit-backed and must run on the main thread.
            // Extract .string on the main actor so only a Sendable String crosses the boundary.
            let result: String? = await MainActor.run {
                (try? NSAttributedString(data: data, options: opts, documentAttributes: nil))?.string
            }
            if let parsed = result {
                return parsed
            }
        }

        // Fallback for documents the WebKit parser cannot handle (e.g. malformed fragments)
        guard let html = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else { throw ParserError.unreadableFile }
        return stripHTMLFallback(html)
    }

    // Regex-based HTML stripping used when:
    //   (a) NSAttributedString fails on a malformed file, or
    //   (b) the user pastes raw HTML markup directly into the editor.
    // It is intentionally conservative and complete: <head>, scripts, styles,
    // block elements, table cells, and all remaining tags (with all their
    // attributes) are removed before entity decoding.
    static func stripHTMLFallback(_ html: String) -> String {
        var text = html

        // Remove <head> entirely — CSS, JS links, meta content, add only noise
        text = text.replacingOccurrences(
            of: "<head[\\s\\S]*?</head>",
            with: "", options: [.regularExpression, .caseInsensitive])

        // Remove out-of-head script/style blocks
        text = text.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</(script|style)>",
            with: "", options: [.regularExpression, .caseInsensitive])

        // Remove HTML comments
        text = text.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "", options: .regularExpression)

        // Block/structural elements → newline (opening and closing tags)
        text = text.replacingOccurrences(
            of: "</?(?:p|div|br|tr|li|h[1-6]|section|article|header|footer|main|blockquote|pre)(?:\\s[^>]*)?>",
            with: "\n", options: [.regularExpression, .caseInsensitive])

        // Table cells/headers → tab (preserves column layout for the normalizer)
        text = text.replacingOccurrences(
            of: "<(?:td|th)(?:\\s[^>]*)?>",
            with: "\t", options: [.regularExpression, .caseInsensitive])

        // Strip all remaining tags — this removes every attribute on every tag,
        // including inline style=, class=, onclick=, data-*, aria-*, etc.
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode named HTML entities
        let namedEntities: KeyValuePairs<String, String> = [
            "&amp;": "&",   "&lt;": "<",    "&gt;": ">",
            "&quot;": "\"", "&apos;": "'",  "&nbsp;": " ",
            "&ndash;": "-", "&mdash;": "-", "&hellip;": "…",
            "&laquo;": "",  "&raquo;": "",
            "&copy;": "",   "&reg;": "",    "&trade;": "",
        ]
        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        // Numeric character references: &#NNN; and &#xHH;
        text = text.replacingOccurrences(of: "&#x?[0-9a-fA-F]+;", with: " ", options: .regularExpression)

        return text
    }

    // MARK: - Text preprocessing (file-extracted + pasted text)

    // Entry point for text that did not go through extractText (e.g. typed or pasted).
    // Detects raw HTML markup and routes through stripHTMLFallback before normalizing,
    // so the model never sees tag soup regardless of how the text arrived.
    static func preprocessText(_ raw: String) -> String {
        let looksLikeHTML = raw.range(
            of: "<(?:!DOCTYPE|html|head|body|table|tr|td|div|p)(?:\\s[^>]*)?>",
            options: [.regularExpression, .caseInsensitive]) != nil
        return normalizeText(looksLikeHTML ? stripHTMLFallback(raw) : raw)
    }

    // MARK: - Text normalization

    // Applied to all text after any format-specific extraction.
    // Removes structural noise that wastes context tokens without carrying MIDI data.
    static func normalizeText(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
        var result: [String] = []
        var blankRun = 0

        for line in lines {
            // Collapse tabs and runs of spaces; trim edges
            let cleaned = line
                .replacingOccurrences(of: "[\\t ]{2,}", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if cleaned.isEmpty {
                // At most one consecutive blank line (section breaks carry meaning)
                if blankRun == 0 { result.append("") }
                blankRun += 1
                continue
            }
            blankRun = 0

            // Drop pure separator lines: -, =, |, _, +, ., *
            if cleaned.range(of: #"^[-=|_+.*·\s]+$"#, options: .regularExpression) != nil { continue }

            // Drop standalone page numbers and "Page N [of M]" lines
            if cleaned.range(of: #"^[-–\s]*[Pp]age\s+\d+(\s+of\s+\d+)?[-–\s]*$"#,
                             options: .regularExpression) != nil { continue }
            if cleaned.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil { continue }

            // Drop bare URLs — no MIDI data, only bloat
            if cleaned.range(of: #"^https?://"#, options: .regularExpression) != nil { continue }

            // Truncate implausibly long lines (data URIs, base64 blobs slipping through)
            let capped = cleaned.count > 300 ? String(cleaned.prefix(300)) : cleaned
            result.append(capped)
        }

        while result.first == "" { result.removeFirst() }
        while result.last  == "" { result.removeLast() }

        return result.joined(separator: "\n")
    }

    // MARK: - Parsing

    static func parse(
        text: String,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [MIDIControlDef] {
        guard case .available = SystemLanguageModel.default.availability else {
            throw ParserError.modelUnavailable
        }

        // Run the same preprocessing pipeline used for file-imported text
        let cleaned = preprocessText(text)
        let chunks = chunk(cleaned)
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
    // Leaves ~3200 tokens for chart text. At ~3 chars/token for dense tables: ~1800 chars/chunk.

    private static func chunk(_ text: String, maxChars: Int = 1800) -> [String] {
        guard text.count > maxChars else { return [text] }
        var chunks: [String] = []
        var current = ""

        for line in text.components(separatedBy: .newlines) {
            let next = current.isEmpty ? line : current + "\n" + line
            guard next.count > maxChars, !current.isEmpty else {
                current = next
                continue
            }
            // Prefer splitting at blank lines to keep related rows together
            if line.isEmpty {
                chunks.append(current)
                current = ""
            } else {
                chunks.append(current)
                current = line
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
