#if SingleByte
// Single-byte reverse (encode) maps: code point → byte (0x80…0xFF). Lowest byte
// wins on the rare duplicate, matching WHATWG "index pointer for code point".
let _singleByteReverse: [[UInt32: UInt8]] = _singleByteTables.map { table in
    var m = [UInt32: UInt8](minimumCapacity: 128)
    for i in 0..<128 {
        let cp = table[i]
        if cp != 0xFFFF {
            let key = UInt32(cp)
            if m[key] == nil { m[key] = UInt8(0x80 + i) }
        }
    }
    return m
}
#endif
