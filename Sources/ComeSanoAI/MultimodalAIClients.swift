import Foundation
import ComeSanoCore

public enum AIClientError: Error {
    case missingAPIKey
    case invalidResponse(statusCode: Int, message: String)
    case missingContent
    case invalidPayload(rawText: String)
}

extension AIClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No hay API key de OpenAI configurada."
        case let .invalidResponse(statusCode, message):
            return "OpenAI respondió \(statusCode): \(message)"
        case .missingContent:
            return "OpenAI no devolvió contenido utilizable."
        case let .invalidPayload(rawText):
            let snippet = String(rawText.prefix(180))
            return "La respuesta de OpenAI no fue JSON válido. Respuesta parcial: \(snippet)"
        }
    }
}

public enum OpenAIModel: String, Sendable {
    case gpt4point1 = "gpt-4.1"
    case gpt4point1mini = "gpt-4.1-mini"
}

public struct NutritionAIClientFactory {
    public static func makeOpenAI(
        apiKey: String,
        model: OpenAIModel = .gpt4point1,
        urlSession: URLSession = .shared
    ) -> MultimodalNutritionInference {
        let network = OpenAINetworkManager(apiKey: apiKey, model: model.rawValue, session: urlSession)
        return OpenAINutritionClient(networkManager: network)
    }
}

public protocol OpenAINetworkManaging: Sendable {
    func analyzeImage(base64JPEG: String, prompt: String) async throws -> String
}

public struct OpenAINetworkManager: OpenAINetworkManaging, Sendable {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, model: String = "gpt-4.1", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func analyzeImage(base64JPEG: String, prompt: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }

        let body: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": [["type": "input_text", "text": OpenAINutritionPromptBuilder.systemInstruction]]
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt],
                        ["type": "input_image", "image_url": "data:image/jpeg;base64,\(base64JPEG)"]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse(statusCode: -1, message: "Respuesta HTTP inválida.")
        }

        guard (200..<300).contains(http.statusCode) else {
            let apiMessage = OpenAIErrorExtractor.message(from: responseData) ?? "Sin detalle de error."
            throw AIClientError.invalidResponse(statusCode: http.statusCode, message: apiMessage)
        }

        let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: responseData)

        if let outputText = envelope.outputText, !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }

        if let text = envelope.output.compactMap({ item in
            item.content?.compactMap { $0.text }.first
        }).first {
            return text
        }

        throw AIClientError.missingContent
    }
}

public struct OpenAINutritionClient: MultimodalNutritionInference, Sendable {
    private let networkManager: OpenAINetworkManaging

    public init(networkManager: OpenAINetworkManaging) {
        self.networkManager = networkManager
    }

    public func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult {
        let imageBase64 = data.base64EncodedString()
        let finalPrompt = OpenAINutritionPromptBuilder.userPrompt(extraInstruction: prompt)
        let rawText = try await networkManager.analyzeImage(base64JPEG: imageBase64, prompt: finalPrompt)
        let jsonText = try OpenAIJSONExtractor.extractJSONObject(from: rawText)

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AIClientError.invalidPayload(rawText: rawText)
        }
        return try JSONDecoder().decode(NutritionInferenceResult.self, from: jsonData)
    }
}

public enum OpenAINutritionPromptBuilder {
    public static let systemInstruction = """
    You are a nutrition analyzer. Return ONLY strict JSON (no markdown, no prose) using this exact schema:
    {
      "foodItems": [
        {
          "name": "string",
          "servingDescription": "string",
          "nutrition": {
            "calories": number,
            "proteinGrams": number,
            "carbsGrams": number,
            "fatGrams": number
          },
          "source": "ai"
        }
      ],
      "shoppingList": [
        {
          "name": "string",
          "quantity": number,
          "unit": "string"
        }
      ],
      "notes": "string"
    }
    """

    public static func userPrompt(extraInstruction: String) -> String {
        let cleanedInstruction = extraInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Analiza esta imagen de comida, alacena o refrigerador. Detecta alimentos y estima calorías/macros por porción.
        También sugiere lo que falta comprar para una alimentación balanceada según lo observado.
        Instrucción adicional del usuario: \(cleanedInstruction.isEmpty ? "Ninguna" : cleanedInstruction)
        """
    }
}

public enum OpenAIJSONExtractor {
    public static func extractJSONObject(from text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }

        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else {
            throw AIClientError.invalidPayload(rawText: text)
        }

        return String(trimmed[start...end])
    }
}

private enum OpenAIErrorExtractor {
    static func message(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.error.message
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }
    let error: APIError
}

private struct OpenAIResponsesEnvelope: Decodable {
    struct Item: Decodable {
        struct Content: Decodable {
            let text: String?
        }
        let content: [Content]?
    }

    let output: [Item]
    let outputText: String?

    private enum CodingKeys: String, CodingKey {
        case output
        case outputText = "output_text"
    }
}
