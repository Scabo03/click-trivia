import Compression
import Foundation

/// Lettore ZIP minimale, quanto basta per aprire un .xlsx (che è uno zip di
/// XML). Scritto in casa per restare nel perimetro "Swift puro, nessuna
/// dipendenza": il formato è documentato e stabile, l'inflate lo fa il
/// framework Apple `Compression`.
///
/// Limiti dichiarati (adeguati ai template Kahoot, file piccoli):
/// niente ZIP64, niente cifratura; metodi supportati: stored e deflate.
enum ZipReader {
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    private static let centralDirectorySignature: UInt32 = 0x0201_4b50
    private static let localHeaderSignature: UInt32 = 0x0403_4b50

    /// Estrae tutte le voci dell'archivio: nome → contenuto decompresso.
    static func entries(from data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard bytes.count > 22, bytes[0] == 0x50, bytes[1] == 0x4b else {
            throw ImportError.unsupportedFormat
        }

        // End of Central Directory: si cerca a ritroso dalla coda.
        guard let eocd = findEndOfCentralDirectory(in: bytes) else {
            throw ImportError.unsupportedFormat
        }
        let entryCount = Int(readU16(bytes, at: eocd + 10))
        var offset = Int(readU32(bytes, at: eocd + 16))

        var result: [String: Data] = [:]
        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count,
                  readU32(bytes, at: offset) == centralDirectorySignature else {
                throw ImportError.unsupportedFormat
            }
            let method = Int(readU16(bytes, at: offset + 10))
            let compressedSize = Int(readU32(bytes, at: offset + 20))
            let uncompressedSize = Int(readU32(bytes, at: offset + 24))
            let nameLength = Int(readU16(bytes, at: offset + 28))
            let extraLength = Int(readU16(bytes, at: offset + 30))
            let commentLength = Int(readU16(bytes, at: offset + 32))
            let localHeaderOffset = Int(readU32(bytes, at: offset + 42))

            guard compressedSize != 0xFFFF_FFFF, localHeaderOffset != 0xFFFF_FFFF else {
                // ZIP64: fuori dai limiti dichiarati.
                throw ImportError.unsupportedFormat
            }

            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else {
                throw ImportError.unsupportedFormat
            }
            let name = String(
                decoding: bytes[nameStart..<(nameStart + nameLength)],
                as: UTF8.self
            )

            if let content = try extractEntry(
                bytes: bytes,
                localHeaderOffset: localHeaderOffset,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize
            ) {
                result[name] = content
            }

            offset = nameStart + nameLength + extraLength + commentLength
        }
        return result
    }

    private static func extractEntry(
        bytes: [UInt8],
        localHeaderOffset: Int,
        method: Int,
        compressedSize: Int,
        uncompressedSize: Int
    ) throws -> Data? {
        guard localHeaderOffset + 30 <= bytes.count,
              readU32(bytes, at: localHeaderOffset) == localHeaderSignature else {
            throw ImportError.unsupportedFormat
        }
        let nameLength = Int(readU16(bytes, at: localHeaderOffset + 26))
        let extraLength = Int(readU16(bytes, at: localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + nameLength + extraLength
        guard dataStart + compressedSize <= bytes.count else {
            throw ImportError.unsupportedFormat
        }
        if compressedSize == 0 { return Data() }
        let compressed = Array(bytes[dataStart..<(dataStart + compressedSize)])

        switch method {
        case 0: // stored
            return Data(compressed)
        case 8: // deflate
            return inflate(compressed, expectedSize: uncompressedSize)
        default:
            throw ImportError.unsupportedFormat
        }
    }

    private static func inflate(_ compressed: [UInt8], expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { destination.deallocate() }
        let written = compressed.withUnsafeBufferPointer { source in
            compression_decode_buffer(
                destination, expectedSize,
                source.baseAddress!, compressed.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written == expectedSize else { return nil }
        return Data(bytes: destination, count: written)
    }

    private static func findEndOfCentralDirectory(in bytes: [UInt8]) -> Int? {
        // Il record è in coda, preceduto al più da un commento di 64 KiB.
        let lowerBound = max(0, bytes.count - 22 - 65_536)
        var index = bytes.count - 22
        while index >= lowerBound {
            if readU32(bytes, at: index) == endOfCentralDirectorySignature {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func readU16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readU32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
