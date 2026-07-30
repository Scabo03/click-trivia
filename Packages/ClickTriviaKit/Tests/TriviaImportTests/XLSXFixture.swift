import Compression
import Foundation

/// Costruisce .xlsx di prova in memoria: uno zip scritto a mano (metodo
/// stored o deflate) con sharedStrings e un foglio nel layout del template
/// Kahoot. Serve a testare l'intera catena reale: zip → XML → bozza.
enum XLSXFixture {

    /// Una riga dati del template: domanda, opzioni (fino a 4), contenuto
    /// della colonna H (risposta corretta, testuale com'è nel file).
    struct Row {
        var question: String
        var options: [String]
        var correct: String
        var timeLimit: String = "20"
    }

    /// Costruisce l'xlsx con le righe dati a partire dalla riga 9.
    static func workbook(rows: [Row], deflated: Bool = false) -> Data {
        var sharedStrings: [String] = []
        func sharedIndex(_ string: String) -> Int {
            if let existing = sharedStrings.firstIndex(of: string) { return existing }
            sharedStrings.append(string)
            return sharedStrings.count - 1
        }

        var rowsXML = ""
        for (offset, row) in rows.enumerated() {
            let rowNumber = 9 + offset
            var cells = ""
            func cell(_ columnLetter: String, text: String) {
                guard !text.isEmpty else { return }
                cells += #"<c r="\#(columnLetter)\#(rowNumber)" t="s"><v>\#(sharedIndex(text))</v></c>"#
            }
            func numericCell(_ columnLetter: String, raw: String) {
                guard !raw.isEmpty else { return }
                cells += #"<c r="\#(columnLetter)\#(rowNumber)"><v>\#(raw)</v></c>"#
            }
            cell("B", text: row.question)
            let letters = ["C", "D", "E", "F"]
            for (index, option) in row.options.prefix(4).enumerated() {
                cell(letters[index], text: option)
            }
            numericCell("G", raw: row.timeLimit)
            numericCell("H", raw: row.correct)
            rowsXML += #"<row r="\#(rowNumber)">\#(cells)</row>"#
        }

        let sheetXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(rowsXML)</sheetData>
        </worksheet>
        """

        let stringItems = sharedStrings
            .map { "<si><t>\(escapeXML($0))</t></si>" }
            .joined()
        let sharedXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(sharedStrings.count)" uniqueCount="\(sharedStrings.count)">\(stringItems)</sst>
        """

        return zip(
            entries: [
                ("xl/sharedStrings.xml", Data(sharedXML.utf8)),
                ("xl/worksheets/sheet1.xml", Data(sheetXML.utf8)),
            ],
            deflated: deflated
        )
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Scrittura ZIP

    static func zip(entries: [(name: String, content: Data)], deflated: Bool) -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            let crc = crc32(entry.content)
            let payload: Data
            let method: UInt16
            if deflated, let compressed = deflate(entry.content) {
                payload = compressed
                method = 8
            } else {
                payload = entry.content
                method = 0
            }

            let localHeaderOffset = UInt32(archive.count)

            var local = Data()
            appendU32(&local, 0x0403_4b50)
            appendU16(&local, 20)          // version needed
            appendU16(&local, 0)           // flags
            appendU16(&local, method)
            appendU16(&local, 0)           // mod time
            appendU16(&local, 0)           // mod date
            appendU32(&local, crc)
            appendU32(&local, UInt32(payload.count))
            appendU32(&local, UInt32(entry.content.count))
            appendU16(&local, UInt16(nameBytes.count))
            appendU16(&local, 0)           // extra length
            local += nameBytes
            local += payload
            archive += local

            var central = Data()
            appendU32(&central, 0x0201_4b50)
            appendU16(&central, 20)        // version made by
            appendU16(&central, 20)        // version needed
            appendU16(&central, 0)         // flags
            appendU16(&central, method)
            appendU16(&central, 0)         // mod time
            appendU16(&central, 0)         // mod date
            appendU32(&central, crc)
            appendU32(&central, UInt32(payload.count))
            appendU32(&central, UInt32(entry.content.count))
            appendU16(&central, UInt16(nameBytes.count))
            appendU16(&central, 0)         // extra
            appendU16(&central, 0)         // comment
            appendU16(&central, 0)         // disk
            appendU16(&central, 0)         // internal attrs
            appendU32(&central, 0)         // external attrs
            appendU32(&central, localHeaderOffset)
            central += nameBytes
            centralDirectory += central
        }

        let centralOffset = UInt32(archive.count)
        archive += centralDirectory

        appendU32(&archive, 0x0605_4b50)
        appendU16(&archive, 0)             // disk
        appendU16(&archive, 0)             // disk with central dir
        appendU16(&archive, UInt16(entries.count))
        appendU16(&archive, UInt16(entries.count))
        appendU32(&archive, UInt32(centralDirectory.count))
        appendU32(&archive, centralOffset)
        appendU16(&archive, 0)             // comment length

        return archive
    }

    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let source = [UInt8](data)
        let capacity = source.count + 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let written = source.withUnsafeBufferPointer { buffer in
            compression_encode_buffer(
                destination, capacity,
                buffer.baseAddress!, source.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written > 0 else { return nil }
        return Data(bytes: destination, count: written)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) == 1 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func appendU16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    private static func appendU32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
