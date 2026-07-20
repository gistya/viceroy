#if Japanese
// JIS X 0212 — decode-only, reached via EUC-JP's 0x8F prefix.
let jis0212: [UInt16] = decodeU16Table(_jis0212_b64, count: _jis0212_count)
#endif
