import Foundation

enum TelegramClientError: LocalizedError {
    case missingToken
    case invalidURL
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Add the Telegram bot token in Settings first."
        case .invalidURL:
            return "The Telegram request URL is invalid."
        case .apiError(let message):
            return message
        case .invalidResponse:
            return "Telegram returned an unexpected response."
        }
    }
}

struct TelegramClient {
    func sendMessage(token: String, chatID: String, text: String) async throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw TelegramClientError.missingToken }
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw TelegramClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "chat_id": chatID,
            "text": text,
            "disable_web_page_preview": true
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw TelegramClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(TelegramEnvelope<TelegramSentMessage>.self, from: data)
        guard decoded.ok else {
            throw TelegramClientError.apiError(decoded.description ?? "Telegram could not send the message.")
        }
    }

    func getUpdates(token: String, offset: Int) async throws -> [TelegramUpdate] {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw TelegramClientError.missingToken }

        var components = URLComponents(string: "https://api.telegram.org/bot\(token)/getUpdates")
        components?.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "timeout", value: "0")
        ]
        guard let url = components?.url else { throw TelegramClientError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw TelegramClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(TelegramEnvelope<[TelegramUpdate]>.self, from: data)
        guard decoded.ok, let result = decoded.result else {
            throw TelegramClientError.apiError(decoded.description ?? "Telegram could not fetch bot updates.")
        }
        return result
    }
}

struct TelegramEnvelope<Result: Decodable>: Decodable {
    var ok: Bool
    var result: Result?
    var description: String?
}

struct TelegramSentMessage: Decodable {
    var messageID: Int?

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
    }
}

struct TelegramUpdate: Decodable, Hashable {
    var updateID: Int
    var message: TelegramMessage?

    enum CodingKeys: String, CodingKey {
        case updateID = "update_id"
        case message
    }
}

struct TelegramMessage: Decodable, Hashable {
    var text: String?
    var chat: TelegramChat
}

struct TelegramChat: Decodable, Hashable {
    var id: Int64
}

extension TelegramUpdate {
    var startPayload: String? {
        guard let text = message?.text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        if text.hasPrefix("/start ") {
            return String(text.dropFirst("/start ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.hasPrefix("/start@") {
            let pieces = text.split(separator: " ", maxSplits: 1).map(String.init)
            return pieces.count == 2 ? pieces[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }

        return nil
    }
}
