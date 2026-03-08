import Foundation

public struct PairingXMLResponse: Sendable {
    public var rootAttributes: [String: String]
    public var fields: [String: String]

    public init(rootAttributes: [String: String], fields: [String: String]) {
        self.rootAttributes = rootAttributes
        self.fields = fields
    }

    public var statusCode: Int? {
        rootAttributes["status_code"].flatMap(Int.init)
    }

    public var statusMessage: String? {
        rootAttributes["status_message"]
    }

    public func value(for field: String) -> String? {
        fields[field]
    }

    public func requireOK(action: String) throws {
        guard statusCode == nil || statusCode == 200 else {
            throw PairingError.invalidResponseStatus(action: action, code: statusCode, message: statusMessage)
        }
    }
}

enum PairingXML {
    static func parseResponse(data: Data) throws -> PairingXMLResponse {
        let parser = PairingXMLParser()
        parser.parse(data: data)
        if let error = parser.error {
            throw error
        }
        return PairingXMLResponse(rootAttributes: parser.rootAttributes, fields: parser.fields)
    }
}

private final class PairingXMLParser: NSObject, XMLParserDelegate {
    private(set) var rootAttributes: [String: String] = [:]
    private(set) var fields: [String: String] = [:]
    private var currentText = ""
    private var currentElementName: String?
    private(set) var error: PairingError?

    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        if parser.parserError != nil, error == nil {
            error = .malformedXML(parser.parserError?.localizedDescription ?? "Unknown parser error")
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        currentElementName = elementName

        if elementName == "root" {
            rootAttributes = attributeDict
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer {
            currentText = ""
            currentElementName = nil
        }

        guard elementName != "root" else {
            return
        }

        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            fields[elementName] = trimmed
        }
    }
}
