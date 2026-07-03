//===----------------------------------------------------------------------===//
// Viceroy — ISO-2022-JP  (WHATWG §12.2) — the stateful one.
//
// The decoder is a seven-state machine driven by ESC sequences; all state lives
// in the struct, so chunked input behaves identically to a single buffer. The
// encoder tracks the active charset and re-encodes a scalar after emitting an
// escape (via the driver's `.retry`).
//===----------------------------------------------------------------------===//

@usableFromInline
enum ISO2022JPState {
    case ascii, roman, katakana, leadingByte, trailingByte, escapeStart, escape
}

struct ISO2022JPDecoder: ByteHandler {
    var state: ISO2022JPState = .ascii
    var outputState: ISO2022JPState = .ascii
    var lead: UInt8 = 0
    var output = false

    mutating func handle(_ byte: UInt8) -> ByteResult {
        switch state {
        case .ascii:
            switch byte {
            case 0x1B: state = .escapeStart; return .again
            case 0x0E, 0x0F: output = false; return .error
            case 0x00...0x7F: output = false; return .scalar(Unicode.Scalar(byte))
            default: output = false; return .error
            }
        case .roman:
            switch byte {
            case 0x1B: state = .escapeStart; return .again
            case 0x5C: output = false; return .scalar("\u{00A5}")     // ¥
            case 0x7E: output = false; return .scalar("\u{203E}")     // ‾
            case 0x0E, 0x0F: output = false; return .error
            case 0x00...0x7F: output = false; return .scalar(Unicode.Scalar(byte))
            default: output = false; return .error
            }
        case .katakana:
            switch byte {
            case 0x1B: state = .escapeStart; return .again
            case 0x21...0x5F: output = false; return .scalar(Unicode.Scalar(0xFF61 - 0x21 + UInt32(byte))!)
            default: output = false; return .error
            }
        case .leadingByte:
            switch byte {
            case 0x1B: state = .escapeStart; return .again
            case 0x21...0x7E: output = false; lead = byte; state = .trailingByte; return .again
            default: output = false; return .error
            }
        case .trailingByte:
            switch byte {
            case 0x1B: state = .escapeStart; return .error
            case 0x21...0x7E:
                state = .leadingByte
                let pointer = (Int(lead) - 0x21) * 94 + Int(byte) - 0x21
                if pointer >= 0 && pointer < jis0208.count, jis0208[pointer] != 0xFFFF {
                    return .scalar(Unicode.Scalar(UInt32(jis0208[pointer]))!)
                }
                return .error
            default: state = .leadingByte; return .error
            }
        case .escapeStart:
            if byte == 0x24 || byte == 0x28 {
                lead = byte; state = .escape; return .again
            }
            output = false; state = outputState
            return .errorPrepend([byte])
        case .escape:
            let leading = lead; lead = 0
            var newState: ISO2022JPState? = nil
            if leading == 0x28 && byte == 0x42 { newState = .ascii }
            if leading == 0x28 && byte == 0x4A { newState = .roman }
            if leading == 0x28 && byte == 0x49 { newState = .katakana }
            if leading == 0x24 && (byte == 0x40 || byte == 0x42) { newState = .leadingByte }
            if let ns = newState {
                state = ns; outputState = ns
                let wasOutput = output
                output = true
                return wasOutput ? .error : .again
            }
            output = false; state = outputState
            return .errorPrepend([leading, byte])
        }
    }

    mutating func handleEOF() -> ByteResult {
        switch state {
        case .ascii, .roman, .katakana, .leadingByte:
            return .again
        case .trailingByte:
            state = .leadingByte; return .error
        case .escapeStart:
            state = outputState; output = false; return .error
        case .escape:
            let leading = lead; lead = 0
            state = outputState; output = false
            return .errorPrepend([leading])   // restore the truncated escape's lead
        }
    }
}

@usableFromInline
enum ISO2022JPEncState { case ascii, roman, jis0208 }

struct ISO2022JPEncoder: ScalarHandler {
    var state: ISO2022JPEncState = .ascii

    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        var v = scalar.value
        // Security: ESC/SO/SI are never emittable from ASCII/Roman state.
        if (state == .ascii || state == .roman) && (v == 0x000E || v == 0x000F || v == 0x001B) {
            return .unmappable
        }
        if state == .ascii && v <= 0x7F { out.append(UInt8(v)); return .ok }
        if state == .roman && v <= 0x7F && v != 0x5C && v != 0x7E { out.append(UInt8(v)); return .ok }
        if state == .roman && v == 0xA5 { out.append(0x5C); return .ok }
        if state == .roman && v == 0x203E { out.append(0x7E); return .ok }
        if v <= 0x7F && state != .ascii {
            out.append(0x1B); out.append(0x28); out.append(0x42)  // ESC ( B
            state = .ascii; return .retry
        }
        if (v == 0xA5 || v == 0x203E) && state != .roman {
            out.append(0x1B); out.append(0x28); out.append(0x4A)  // ESC ( J
            state = .roman; return .retry
        }
        if v == 0x2212 { v = 0xFF0D }
        if v >= 0xFF61 && v <= 0xFF9F {
            v = UInt32(_iso2022jpKatakana[Int(v - 0xFF61)])
        }
        guard let p = jis0208Reverse[v] else {
            if state == .jis0208 {
                out.append(0x1B); out.append(0x28); out.append(0x42)  // ESC ( B
                state = .ascii; return .retry
            }
            return .unmappable
        }
        if state != .jis0208 {
            out.append(0x1B); out.append(0x24); out.append(0x42)  // ESC $ B
            state = .jis0208; return .retry
        }
        out.append(UInt8(p / 94 + 0x21))
        out.append(UInt8(p % 94 + 0x21))
        return .ok
    }

    mutating func finish(into out: inout [UInt8]) {
        if state != .ascii {
            out.append(0x1B); out.append(0x28); out.append(0x42)  // ESC ( B
            state = .ascii
        }
    }
}
