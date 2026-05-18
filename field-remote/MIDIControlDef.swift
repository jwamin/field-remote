import Foundation
import FoundationModels

// MARK: - Generable enums (used by model during parsing)

@Generable
enum MIDIMessageType: String, Codable {
    case cc
    case programChange
}

@Generable
enum MIDIControlStyle: String, Codable {
    case slider    // continuous 0–127
    case toggle    // sends minValue / maxValue (on/off)
    case trigger   // momentary, sends maxValue on press
}

// MARK: - Parsed types (model output only, not stored)

@Generable(description: "A single CC or program change control from a MIDI implementation chart")
struct ParsedMIDIControl {
    @Guide(description: "Short parameter label, e.g. 'Track 1 Volume'")
    var name: String

    @Guide(description: "cc for Control Change, programChange for Program Change")
    var messageType: MIDIMessageType

    @Guide(description: "CC number 0–127, or program number 0–127 for program change", .range(0...127))
    var number: Int

    @Guide(description: "1-based MIDI channel 1–16", .range(1...16))
    var channel: Int

    @Guide(description: "Minimum output value 0–127", .range(0...127))
    var minValue: Int

    @Guide(description: "Maximum output value 0–127", .range(0...127))
    var maxValue: Int

    @Guide(description: "slider for continuous range, toggle for on/off, trigger for momentary")
    var controlStyle: MIDIControlStyle
}

@Generable(description: "All CC and program change controls extracted from the chart section")
struct ParsedMIDIControlList {
    @Guide(description: "One entry per chart row; CC and program change only")
    var controls: [ParsedMIDIControl]
}

// MARK: - Stored type (Codable + Identifiable)

struct MIDIControlDef: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var messageType: MIDIMessageType
    var number: Int      // CC number, or program number for PC
    var channel: Int     // 1-based
    var minValue: Int
    var maxValue: Int
    var controlStyle: MIDIControlStyle

    init(from parsed: ParsedMIDIControl) {
        id           = UUID()
        name         = parsed.name
        messageType  = parsed.messageType
        number       = max(0, min(127, parsed.number))
        channel      = max(1, min(16,  parsed.channel))
        minValue     = max(0, min(127, parsed.minValue))
        maxValue     = max(0, min(127, parsed.maxValue))
        controlStyle = parsed.controlStyle
    }
}
