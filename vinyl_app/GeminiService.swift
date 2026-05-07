//
//  GeminiService.swift
//  vinyl_app
//
//  Created by Dhruv bareja on 10/02/26.
//

import Foundation

// MARK: - Gemini Service
final class GeminiService {

    static let shared = GeminiService()
    private init() {}

    // MARK: - Config
    private let model = "gemini-1.5-flash"

    // ⚠️ DO NOT hardcode in production
    // Replace this with env / xcconfig later
    private let apiKey: String = {
        guard let key = AppConfig.geminiAPIKey else {
            fatalError("❌ GEMINI_API_KEY not found in Info.plist")
        }
        return key
    }()

    // MARK: - Public API
    func generateText(prompt: String) async throws -> String {
        let url = try makeURL()
        let body = makeRequestBody(prompt: prompt)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        return try parseResponse(data: data)
    }

    // MARK: - Helpers
    private func makeURL() throws -> URL {
        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        ) else {
            throw GeminiError.invalidURL
        }
        return url
    }

    private func makeRequestBody(prompt: String) -> Data {
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(message)
        }
    }

    private func parseResponse(data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let text = decoded
            .candidates?
            .first?
            .content
            .parts
            .first?
            .text
        else {
            throw GeminiError.emptyResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Models
private struct GeminiResponse: Decodable {
    let candidates: [Candidate]?
}

private struct Candidate: Decodable {
    let content: Content
}

private struct Content: Decodable {
    let parts: [Part]
}

private struct Part: Decodable {
    let text: String
}

// MARK: - Errors
enum GeminiError: Error {
    case invalidURL
    case invalidResponse
    case emptyResponse
    case apiError(String)
}
