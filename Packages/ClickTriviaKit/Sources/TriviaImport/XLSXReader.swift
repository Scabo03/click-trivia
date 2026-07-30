import Foundation

/// Il contenuto di un foglio: valori per riga e colonna (1-based, come nel
/// formato: riga 9, colonna B = 2).
struct XLSXSheet {
    /// riga → (colonna → valore testuale della cella)
    var rows: [Int: [Int: String]] = [:]

    func value(row: Int, column: Int) -> String? {
        rows[row]?[column]
    }
}

/// Lettura di un .xlsx: zip → sharedStrings + primo foglio, con XMLParser
/// di Foundation. Copre ciò che serve al template Kahoot: celle con stringhe
/// condivise, stringhe inline e valori numerici.
enum XLSXReader {
    static func firstSheet(from data: Data) throws -> XLSXSheet {
        let entries = try ZipReader.entries(from: data)

        let sheetPath: String
        if entries["xl/worksheets/sheet1.xml"] != nil {
            sheetPath = "xl/worksheets/sheet1.xml"
        } else if let first = entries.keys
            .filter({ $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") })
            .sorted()
            .first {
            sheetPath = first
        } else {
            throw ImportError.malformedData(
                details: String(localized: "Il file non contiene fogli di calcolo: non sembra un .xlsx.")
            )
        }

        let sharedStrings: [String]
        if let sharedData = entries["xl/sharedStrings.xml"] {
            sharedStrings = parseSharedStrings(sharedData)
        } else {
            sharedStrings = []
        }

        guard let sheetData = entries[sheetPath] else {
            throw ImportError.unsupportedFormat
        }
        return parseSheet(sheetData, sharedStrings: sharedStrings)
    }

    // MARK: - sharedStrings.xml

    private static func parseSharedStrings(_ data: Data) -> [String] {
        let delegate = SharedStringsDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    private final class SharedStringsDelegate: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current = ""
        private var insideText = false

        func parser(
            _ parser: XMLParser, didStartElement elementName: String,
            namespaceURI: String?, qualifiedName qName: String?,
            attributes attributeDict: [String: String]
        ) {
            switch elementName {
            case "si": current = ""
            case "t": insideText = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if insideText { current += string }
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String,
            namespaceURI: String?, qualifiedName qName: String?
        ) {
            switch elementName {
            case "t": insideText = false
            case "si": strings.append(current)
            default: break
            }
        }
    }

    // MARK: - sheetN.xml

    private static func parseSheet(_ data: Data, sharedStrings: [String]) -> XLSXSheet {
        let delegate = SheetDelegate(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.sheet
    }

    private final class SheetDelegate: NSObject, XMLParserDelegate {
        var sheet = XLSXSheet()
        private let sharedStrings: [String]
        private var currentCellReference: String?
        private var currentCellType: String?
        private var buffer = ""
        private var isCollecting = false

        init(sharedStrings: [String]) {
            self.sharedStrings = sharedStrings
        }

        func parser(
            _ parser: XMLParser, didStartElement elementName: String,
            namespaceURI: String?, qualifiedName qName: String?,
            attributes attributeDict: [String: String]
        ) {
            switch elementName {
            case "c":
                currentCellReference = attributeDict["r"]
                currentCellType = attributeDict["t"]
                buffer = ""
            case "v", "t":
                // "v" per valori e indici di stringhe condivise;
                // "t" dentro <is> per le stringhe inline.
                isCollecting = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if isCollecting { buffer += string }
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String,
            namespaceURI: String?, qualifiedName qName: String?
        ) {
            switch elementName {
            case "v", "t":
                isCollecting = false
            case "c":
                storeCurrentCell()
                currentCellReference = nil
                currentCellType = nil
                buffer = ""
            default:
                break
            }
        }

        private func storeCurrentCell() {
            guard let reference = currentCellReference,
                  let (row, column) = Self.parseReference(reference) else { return }

            let value: String
            switch currentCellType {
            case "s":
                guard let index = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines)),
                      sharedStrings.indices.contains(index) else { return }
                value = sharedStrings[index]
            default:
                value = buffer
            }

            guard !value.isEmpty else { return }
            sheet.rows[row, default: [:]][column] = value
        }

        /// "B9" → (riga 9, colonna 2)
        private static func parseReference(_ reference: String) -> (row: Int, column: Int)? {
            var column = 0
            var rowDigits = ""
            for character in reference {
                if let letterValue = character.uppercased().unicodeScalars.first,
                   character.isLetter {
                    column = column * 26 + Int(letterValue.value) - 64
                } else if character.isNumber {
                    rowDigits.append(character)
                }
            }
            guard column > 0, let row = Int(rowDigits) else { return nil }
            return (row, column)
        }
    }
}
