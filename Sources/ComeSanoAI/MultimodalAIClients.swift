import Foundation
import ComeSanoCore

public enum AIClientError: Error {
    case invalidResponse
    case missingContent
    case invalidPayload
}

public enum OpenAIModel: String, Sendable {
    case gpt4point1 = "gpt-4.1"
    case gpt4point1mini = "gpt-4.1-mini"
}

public struct NutritionAIClientFactory {
    public static func makeOpenAI(
        apiKey: String,
        model: OpenAIModel = .gpt4point1
    ) -> MultimodalNutritionInference {
        OpenAINutritionClient(apiKey: apiKey, model: model.rawValue)
    }
}

public struct OpenAINutritionClient: MultimodalNutritionInference, Sendable {
    private let apiKey: String
    private let model: String

    public init(apiKey: String, model: String = "gpt-4.1") {
        self.apiKey = apiKey
        self.model = model
    }

    public func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult {
        let imageBase64 = data.base64EncodedString()
        let systemPrompt = """
        Return ONLY valid JSON with this schema:
        {"foodItems":[{"name":"...","servingDescription":"...","nutrition":{"calories":0,"proteinGrams":0,"carbsGrams":0,"fatGrams":0},"source":"ai"}],"notes":"..."}
        """

        let body: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": [["type": "input_text", "text": systemPrompt]]
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt],
                        ["type": "input_image", "image_url": "data:image/jpeg;base64,\(imageBase64)"]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIClientError.invalidResponse
        }

        let envelope = try JSONDecoder().decode(OpenAIEnvelope.self, from: responseData)
        guard let text = envelope.output.compactMap({ $0.content?.first?.text }).first else {
            throw AIClientError.missingContent
        }

        let jsonData = Data(text.utf8)
        return try JSONDecoder().decode(NutritionInferenceResult.self, from: jsonData)
    }
}

private struct OpenAIEnvelope: Decodable {
    struct Item: Decodable {
        struct Content: Decodable {
            let text: String?
        }
        let content: [Content]?
    }
    let output: [Item]
}
