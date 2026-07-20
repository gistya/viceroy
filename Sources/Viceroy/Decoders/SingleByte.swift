#if SingleByte
//===----------------------------------------------------------------------===//
// Viceroy — Generic single-byte  (WHATWG §"single-byte decoder/encoder")
//
// One decoder + one encoder cover every single-byte legacy encoding; they only
// differ by their 128-entry table (`_singleByteTables[index]`, mapping bytes
// 0x80…0xFF to a code point, with 0xFFFF meaning "no mapping → error").
//===----------------------------------------------------------------------===//

@usableFromInline
struct SingleByteDecoder: ByteHandler {
    /// The 128-entry decode table for bytes 0x80…0xFF (0xFFFF = unmapped).
    @usableFromInline let table: [UInt16]

    @usableFromInline init(tableIndex: UInt8) { self.table = _singleByteTables[Int(tableIndex)] }

    @inlinable
    mutating func handle(_ byte: UInt8) -> ByteResult {
        if byte < 0x80 { return .scalar(Unicode.Scalar(byte)) }
        let cp = table[Int(byte) - 0x80]
        if cp == 0xFFFF { return .error }
        return .scalar(Unicode.Scalar(cp)!)
    }

    @inlinable
    mutating func handleEOF() -> ByteResult { .again }
}

@usableFromInline
struct SingleByteEncoder: ScalarHandler {
    /// Reverse map: code point → byte (0x80…0xFF). Built once per table.
    @usableFromInline let reverse: [UInt32: UInt8]

    @usableFromInline init(tableIndex: UInt8) { self.reverse = _singleByteReverse[Int(tableIndex)] }

    @inlinable
    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        let v = scalar.value
        if v <= 0x7F { out.append(UInt8(v)); return .ok }
        if let b = reverse[v] { out.append(b); return .ok }
        return .unmappable
    }
}
#endif
