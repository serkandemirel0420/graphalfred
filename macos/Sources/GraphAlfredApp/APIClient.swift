import Foundation

actor APIClient {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func healthCheck() async -> Bool {
        do {
            let _: EmptyResponse = try await request(path: "health", method: "GET")
            return true
        } catch {
            return false
        }
    }

    func fetchGraph() async throws -> GraphPayload {
        try await request(path: "graph", method: "GET")
    }

    func fetchNote(id: Int64) async throws -> Note {
        try await request(path: "notes/\(id)", method: "GET")
    }

    func createNote(_ requestBody: CreateNoteRequest) async throws -> Note {
        try await request(path: "notes", method: "POST", body: requestBody)
    }

    func updateNote(id: Int64, _ requestBody: UpdateNoteRequest) async throws -> Note {
        try await request(path: "notes/\(id)", method: "PUT", body: requestBody)
    }

    func updatePosition(id: Int64, x: Double, y: Double) async throws -> Note {
        try await request(
            path: "notes/\(id)/position",
            method: "PUT",
            body: UpdatePositionRequest(x: x, y: y)
        )
    }

    func deleteNote(id: Int64) async throws {
        _ = try await requestNoResponse(path: "notes/\(id)", method: "DELETE")
    }

    func createLink(_ link: LinkRequest) async throws {
        _ = try await requestNoResponse(path: "links", method: "POST", body: link)
    }

    func deleteLink(_ link: LinkRequest) async throws {
        _ = try await requestNoResponse(path: "links", method: "DELETE", body: link)
    }

    func autoLayout() async throws -> GraphPayload {
        try await request(path: "layout/auto", method: "POST")
    }

    func search(query: String, limit: Int = 20) async throws -> [Note] {
        let response: SearchResponse = try await request(
            path: "search",
            method: "GET",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        return response.results
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        let url = try buildURL(path: path, query: query)
        return try await performRequest(url: url, method: method, bodyData: nil)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        let url = try buildURL(path: path)
        let bodyData = try encoder.encode(body)
        return try await performRequest(url: url, method: method, bodyData: bodyData)
    }

    private func requestNoResponse(path: String, method: String) async throws -> Bool {
        let _: EmptyResponse = try await request(path: path, method: method)
        return true
    }

    private func requestNoResponse<Body: Encodable>(path: String, method: String, body: Body) async throws -> Bool {
        let _: EmptyResponse = try await request(path: path, method: method, body: body)
        return true
    }

    private func performRequest<Response: Decodable>(
        url: URL,
        method: String,
        bodyData: Data?
    ) async throws -> Response {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method

        if let bodyData {
            urlRequest.httpBody = bodyData
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorBody.self, from: data).error) ?? "Request failed"
            throw APIClientError.serverError(message)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func buildURL(
        path: String,
        query: [URLQueryItem] = []
    ) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidResponse
        }

        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + trimmed
        if !query.isEmpty {
            components.queryItems = query
        }

        guard let url = components.url else {
            throw APIClientError.invalidResponse
        }
        return url
    }
}

private struct ErrorBody: Codable {
    let error: String
}

private struct EmptyResponse: Codable {}

enum APIClientError: LocalizedError {
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid backend response"
        case let .serverError(message):
            return message
        }
    }
}
