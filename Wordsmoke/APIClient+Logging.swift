import Foundation

@MainActor
final class LogState {
  var signatures: [String: String] = [:]
}

extension APIClient {
  func logRequest(_ request: URLRequest, strategy: LogStrategy = .always) {
    #if DEBUG
    guard strategy == .always else { return }
    let method = request.httpMethod ?? "GET"
    let urlString = request.url?.absoluteString ?? "unknown"
    let headers = request.allHTTPHeaderFields ?? [:]
    let body: String = {
      guard let data = request.httpBody else { return "" }
      if let pretty = prettyPrintedJSON(from: data) {
        return pretty
      }
      return String(data: data, encoding: .utf8) ?? ""
    }()

    print("[API] ➡️ \(method) \(urlString)")
    if !headers.isEmpty {
      print("[API] Headers: \(headers)")
    }
    if !body.isEmpty {
      print("[API] ➡️ Body:\n\(body)")
    }
    #endif
  }

  func logResponse(_ response: URLResponse, data: Data, strategy: LogStrategy = .always) {
    #if DEBUG
    guard shouldLogResponse(response, data: data, strategy: strategy) else { return }
    guard let httpResponse = response as? HTTPURLResponse else {
      print("[API] ⬅️😵 invalid response")
      return
    }

    let body: String = {
      if let pretty = prettyPrintedJSON(from: data) {
        return pretty
      }
      return String(data: data, encoding: .utf8) ?? ""
    }()

    let symbol = responseSymbol(for: httpResponse.statusCode)
    print("[API] \(symbol) \(httpResponse.statusCode) \(httpResponse.url?.absoluteString ?? "")")

    if !body.isEmpty {
      print("[API] ⬅️ Body:\n\(body)")
    }
    #endif
  }
}

private extension APIClient {
  func shouldLogResponse(_ response: URLResponse, data: Data, strategy: LogStrategy) -> Bool {
    guard let httpResponse = response as? HTTPURLResponse else {
      return true
    }
    if httpResponse.statusCode == 304 {
      return false
    }
    if strategy == .silent {
      return false
    }
    if strategy == .changesOnly {
      let signature = responseSignature(for: httpResponse, body: data)
      let key = httpResponse.url?.absoluteString ?? ""
      if let signature, logState.signatures[key] == signature {
        return false
      }
      if let signature {
        logState.signatures[key] = signature
      }
    }
    return true
  }

  func responseSymbol(for statusCode: Int) -> String {
    switch statusCode {
    case 200..<300:
      return "⬅️✅"
    case 400..<500:
      return "⬅️‼️"
    case 500...:
      return "⬅️❌"
    default:
      return "⬅️🤔"
    }
  }

  func responseSignature(for response: HTTPURLResponse, body: Data) -> String? {
    if let etag = response.value(forHTTPHeaderField: "ETag") {
      return "etag:\(etag)"
    }
    if let lastModified = response.value(forHTTPHeaderField: "Last-Modified") {
      return "last:\(lastModified)"
    }
    if body.isEmpty {
      return nil
    }
    return "len:\(body.count)-hash:\(body.hashValue)"
  }

  func prettyPrintedJSON(from data: Data) -> String? {
    do {
      let object = try JSONSerialization.jsonObject(with: data, options: [])
      var occurrences: [MarksOccurrence] = []
      let traversed = replacingMarks(in: object, occurrences: &occurrences)
      let prettyData = try JSONSerialization.data(withJSONObject: traversed, options: [.prettyPrinted])
      let pretty = String(data: prettyData, encoding: .utf8) ?? ""
      return replacingMarksPlaceholders(in: pretty, occurrences: occurrences)
    } catch {
      return nil
    }
  }

  func replacingMarks(in object: Any, occurrences: inout [MarksOccurrence]) -> Any {
    if var dict = object as? [String: Any] {
      for (key, value) in dict {
        if key == "marks", let compact = compactArrayString(from: value) {
          let placeholder = "__MARKS_PLACEHOLDER_\(UUID().uuidString)__"
          dict[key] = placeholder
          occurrences.append(.init(placeholder: placeholder, compact: compact))
        } else {
          dict[key] = replacingMarks(in: value, occurrences: &occurrences)
        }
      }
      return dict
    }
    if let array = object as? [Any] {
      return array.map { replacingMarks(in: $0, occurrences: &occurrences) }
    }
    return object
  }

  func replacingMarksPlaceholders(in pretty: String, occurrences: [MarksOccurrence]) -> String {
    var updated = pretty
    for occ in occurrences {
      let quotedPlaceholder = "\"\(occ.placeholder)\""
      updated = updated.replacingOccurrences(of: quotedPlaceholder, with: occ.compact)
    }
    return updated
  }

  func compactArrayString(from value: Any) -> String? {
    guard let array = value as? [Any] else { return nil }
    let elements: [String] = array.compactMap { element in
      if let stringValue = element as? String {
        if let jsonData = try? JSONSerialization.data(withJSONObject: [stringValue], options: []),
           let jsonArrayString = String(data: jsonData, encoding: .utf8),
           jsonArrayString.hasPrefix("[") && jsonArrayString.hasSuffix("]") {
          let inner = jsonArrayString.dropFirst().dropLast()
          return String(inner)
        }
        return "\"\(stringValue)\""
      }
      if let numberValue = element as? NSNumber {
        return numberValue.stringValue
      }
      if element is NSNull {
      return "null"
      }
      if let dict = element as? [String: Any],
         let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: []),
         let jsonString = String(data: jsonData, encoding: .utf8) {
        return jsonString
      }
      if let arrayValue = element as? [Any],
         let jsonData = try? JSONSerialization.data(withJSONObject: arrayValue, options: []),
         let jsonString = String(data: jsonData, encoding: .utf8) {
        return jsonString
      }
      return nil
    }
    return "[" + elements.joined(separator: ",") + "]"
  }
}

private struct MarksOccurrence {
  let placeholder: String
  let compact: String
}
