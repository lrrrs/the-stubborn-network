//
//  RequestStub.swift
//  
//
//  Created by Martin Kim Dung-Pham on 22.07.19.
//

import Foundation

enum RequestStubCodableError: Error {
    case missingRequestURLError(String)
    case missingResponseURLError(String)
}

/// The representation of a request and its recorded response.
///
/// The http version of any stubbed response is `HTTP/1.1`.
///
/// Header fields are stringified in the process of converting them to a `Codable` data format. Each header
/// value will be concatenated with the key with `HeaderEncoding.separator` as their infix.
///
struct RequestStub: CustomDebugStringConvertible, Codable {

    enum HeaderEncoding {
        /// A separator in between a HTTP header's key and value that is used for encoding.
        static let separator: String = "[:::]"
    }

    let error: Error?
    let request: URLRequest
    let response: URLResponse?
    let responseData: Data?

    enum CodingKeys: String, CodingKey {
        case error
        case request
        case response
        case responseData
    }

    enum RequestCodingKeys: String, CodingKey {
        case headerFields
        case method
        case requestData
        case url
    }

    enum ResponseCodingKeys: String, CodingKey {
        case headerFields
        case responseData
        case statusCode
        case url
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        var requestContainer = container.nestedContainer(keyedBy: RequestCodingKeys.self, forKey: .request)
        try requestContainer.encode(request.url?.absoluteString, forKey: .url)
        let requestHeaderFieldsAsStrings = request.allHTTPHeaderFields?.compactMap { key, value in
            "\(key)\(HeaderEncoding.separator)\(value)"
        }
        .sorted(by: <)

        try requestContainer.encode(requestHeaderFieldsAsStrings, forKey: .headerFields)
        try requestContainer.encode(request.httpMethod, forKey: .method)

        try requestContainer.encode(request.httpBody, forKey: .requestData)

        var responseContainer = container.nestedContainer(keyedBy: ResponseCodingKeys.self, forKey: .response)
        if let response = response as? HTTPURLResponse {
            if let responseUrl = response.url?.absoluteString {
                try responseContainer.encode(responseUrl, forKey: .url)
            }
            try responseContainer.encode(response.statusCode, forKey: .statusCode)
            let responseHeaderFieldsAsStrings = response.allHeaderFields.map { key, value in
                "\(key)\(HeaderEncoding.separator)\(value)"
            }
            .sorted(by: <)

            try responseContainer.encode(responseHeaderFieldsAsStrings,
                                         forKey: .headerFields)
        }

        try responseContainer.encode(responseData, forKey: .responseData)
    }

    init(request: URLRequest, response: URLResponse? = nil, responseData: Data? = nil, error: Error? = nil) {
        self.request = request
        self.response = response
        self.responseData = responseData
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let requestContainer = try container.nestedContainer(keyedBy: RequestCodingKeys.self, forKey: .request)
        let requestUrl = try requestContainer.decode(String.self, forKey: .url)

        guard let decodedURL = URL(string: requestUrl) else {
            throw RequestStubCodableError.missingRequestURLError("Unable to decode URL")
        }
        var request = URLRequest(url: decodedURL)
        request.httpMethod = try requestContainer.decode(String.self, forKey: .method)

        let headers = try requestContainer.decode([String].self, forKey: .headerFields)

        request.allHTTPHeaderFields = RequestStub.httpHeaders(from: headers)
        let requestBodyData = try requestContainer.decode(Data?.self, forKey: .requestData)
        request.httpBody = requestBodyData

        let responseContainer = try container.nestedContainer(keyedBy: ResponseCodingKeys.self, forKey: .response)
        let responseBodyData = try responseContainer.decode(Data?.self, forKey: .responseData)
        let responseUrlString = try responseContainer.decode(String.self, forKey: .url)
        let resHeaders = try responseContainer.decode([String].self, forKey: .headerFields)
        let responseHeaders = RequestStub.httpHeaders(from: resHeaders)
        let responseStatusCode = try responseContainer.decode(Int.self, forKey: .statusCode)

        guard let responseUrl = URL(string: responseUrlString) else {
            throw RequestStubCodableError.missingResponseURLError(responseUrlString)
        }

        let response = HTTPURLResponse(url: responseUrl,
                                       statusCode: responseStatusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: responseHeaders)

        self.init(request: request, response: response, responseData: responseBodyData)
    }

    var debugDescription: String {
        let requestDescription = String(describing: request.debugDescription)
        let dataDescription = String(describing: request.httpBody?.count)
        return "[RequestStub] \(requestDescription) \(dataDescription) \(response.debugDescription)"
    }

    static func httpHeaders(from headers: [String]) -> [String: String] {
        let httpHeaders = headers.reduce(into: [String: String]()) { result, field in

            let keyValue = field.components(separatedBy: HeaderEncoding.separator)

            if let key = keyValue.first, let value = keyValue.last {
                result[key] = value
            }
        }

        return httpHeaders
    }
}
