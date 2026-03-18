import Foundation

public enum HostLibraryXML {
    public static func parseApplications(from data: Data) throws -> [HostApplication] {
        let parser = HostLibraryXMLParser()
        parser.parse(data: data)
        if let error = parser.error {
            throw error
        }
        return parser.applications
    }
}

private final class HostLibraryXMLParser: NSObject, XMLParserDelegate {
    private(set) var applications: [HostApplication] = []
    private(set) var error: Error?

    private var statusCode: Int?
    private var statusMessage: String?
    private var currentText = ""
    private var currentAppFields: [String: String]?
    private var currentElementPath: [String] = []

    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        if let parserError = parser.parserError {
            error = PairingError.malformedXML(parserError.localizedDescription)
        } else if let statusCode, statusCode != 200 {
            error = PairingError.invalidResponseStatus(action: "applist", code: statusCode, message: statusMessage)
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElementPath.append(elementName)
        currentText = ""

        if elementName == "root" {
            statusCode = attributeDict["status_code"].flatMap(Int.init)
            statusMessage = attributeDict["status_message"]
        } else if elementName == "App" {
            currentAppFields = [:]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer {
            currentText = ""
            _ = currentElementPath.popLast()
        }

        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "App" {
            guard let currentAppFields,
                  let idText = currentAppFields["ID"],
                  let id = Int(idText),
                  let title = currentAppFields["AppTitle"],
                  !title.isEmpty
            else {
                self.currentAppFields = nil
                return
            }

            applications.append(
                HostApplication(
                    id: id,
                    name: title
                )
            )
            self.currentAppFields = nil
            return
        }

        guard currentElementPath.last == elementName, elementName != "root", !trimmed.isEmpty else {
            return
        }

        if currentAppFields != nil {
            currentAppFields?[elementName] = trimmed
        }
    }
}
