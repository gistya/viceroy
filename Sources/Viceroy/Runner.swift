//===----------------------------------------------------------------------===//
// Viceroy — Generic runners.
//
// These live apart from `Dispatch.swift` on purpose. Dispatch holds the dynamic
// `switch` that names *every* decoder, so anything sharing its object file drags
// all encodings into the link. Keeping the runners here lets a per-encoding
// static entry point (`Encoding.ShiftJIS.decode`) reach only its own decoder.
//===----------------------------------------------------------------------===//

@usableFromInline
func runDecode<H: ByteHandler>(
    _ handler: H, _ bytes: [UInt8], _ mode: DecodingErrorMode, stripBOM: Bool
) throws(ViceroyError) -> String {
    var driver = DecodeDriver(handler, mode: mode)
    var out = [UInt8]()
    out.reserveCapacity(bytes.count + bytes.count / 4)
    try driver.feed(bytes, into: &out)
    try driver.finish(into: &out)
    // A leading BOM decodes to U+FEFF → EF BB BF in the UTF-8 output; drop it.
    if stripBOM, out.count >= 3, out[0] == 0xEF, out[1] == 0xBB, out[2] == 0xBF {
        return String(decoding: out[3...], as: Swift.UTF8.self)
    }
    return String(decoding: out, as: Swift.UTF8.self)
}

@usableFromInline
func runEncode<H: ScalarHandler>(
    _ handler: H, _ scalars: some Sequence<Unicode.Scalar>, _ mode: EncodingErrorMode
) throws(ViceroyError) -> [UInt8] {
    var driver = EncodeDriver(handler, mode: mode)
    var out: [UInt8] = []
    out.reserveCapacity(scalars.underestimatedCount)
    try driver.feed(scalars, into: &out)
    driver.finish(into: &out)
    return out
}
