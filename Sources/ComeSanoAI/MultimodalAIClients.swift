import Foundation
import ComeSanoCore

public enum AIClientError: Error {
    case missingAPIKey(provider: String)
    case invalidResponse(provider: String, statusCode: Int, message: String)
    case missingContent(provider: String)
    case invalidPayload(provider: String, rawText: String)
}

extension AIClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider):
            return "No hay API key de \(provider) configurada."
        case let .invalidResponse(provider, statusCode, message):
            return "\(provider) respondió \(statusCode): \(message)"
        case let .missingContent(provider):
            return "\(provider) no devolvió contenido utilizable."
        case let .invalidPayload(provider, rawText):
            let snippet = String(rawText.prefix(180))
            return "La respuesta de \(provider) no fue JSON válido. Respuesta parcial: \(snippet)"
        }
    }
}

public enum AIProviderChoice: String, CaseIterable, Sendable {
    case openAI
    case gemini
}

public enum OpenAIModel: String, Sendable {
    case gpt4point1 = "gpt-4.1"
    case gpt4point1mini = "gpt-4.1-mini"
}

public enum GeminiModel: String, Sendable {
    case gemini25Flash = "gemini-2.5-flash"
    case gemini25FlashLite = "gemini-2.5-flash-lite"
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

    public static func makeGemini(
        apiKey: String,
        model: GeminiModel = .gemini25Flash,
        urlSession: URLSession = .shared
    ) -> MultimodalNutritionInference {
        let network = GeminiNetworkManager(apiKey: apiKey, model: model.rawValue, session: urlSession)
        return GeminiNutritionClient(networkManager: network)
    }

    public static func makeWithFallback(primary: MultimodalNutritionInference, secondary: MultimodalNutritionInference?) -> MultimodalNutritionInference {
        FallbackNutritionClient(primary: primary, secondary: secondary)
    }

    public static func makeOpenAIRecipe(
        apiKey: String,
        model: OpenAIModel = .gpt4point1,
        urlSession: URLSession = .shared
    ) -> MultimodalRecipeInference {
        let network = OpenAINetworkManager(apiKey: apiKey, model: model.rawValue, session: urlSession)
        return OpenAIRecipeClient(networkManager: network)
    }

    public static func makeGeminiRecipe(
        apiKey: String,
        model: GeminiModel = .gemini25Flash,
        urlSession: URLSession = .shared
    ) -> MultimodalRecipeInference {
        let network = GeminiNetworkManager(apiKey: apiKey, model: model.rawValue, session: urlSession)
        return GeminiRecipeClient(networkManager: network)
    }

    public static func makeRecipeWithFallback(primary: MultimodalRecipeInference, secondary: MultimodalRecipeInference?) -> MultimodalRecipeInference {
        FallbackRecipeClient(primary: primary, secondary: secondary)
    }
}

public protocol ProviderNetworkManaging: Sendable {
    func analyzeImage(base64JPEG: String, prompt: String) async throws -> String
    func analyzeImages(base64JPEGs: [String], prompt: String) async throws -> String
}

public extension ProviderNetworkManaging {
    func analyzeImage(base64JPEG: String, prompt: String) async throws -> String {
        try await analyzeImages(base64JPEGs: [base64JPEG], prompt: prompt)
    }
}

public struct OpenAINetworkManager: ProviderNetworkManaging, Sendable {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, model: String = "gpt-4.1", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func analyzeImage(base64JPEG: String, prompt: String) async throws -> String {
        try await analyzeImages(base64JPEGs: [base64JPEG], prompt: prompt)
    }

    public func analyzeImages(base64JPEGs: [String], prompt: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AIClientError.missingAPIKey(provider: "OpenAI")
        }

        let imageContent: [[String: Any]] = base64JPEGs.map { image in
            ["type": "input_image", "image_url": "data:image/jpeg;base64,\(image)"]
        }

        let userContent = [["type": "input_text", "text": prompt]] + imageContent

        let body: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": [["type": "input_text", "text": "Follow the user instructions and return only the requested format."]]
                ],
                [
                    "role": "user",
                    "content": userContent
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
            throw AIClientError.invalidResponse(provider: "OpenAI", statusCode: -1, message: "Respuesta HTTP inválida.")
        }

        guard (200..<300).contains(http.statusCode) else {
            let apiMessage = OpenAIErrorExtractor.message(from: responseData) ?? "Sin detalle de error."
            throw AIClientError.invalidResponse(provider: "OpenAI", statusCode: http.statusCode, message: apiMessage)
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

        throw AIClientError.missingContent(provider: "OpenAI")
    }
}

public struct GeminiNetworkManager: ProviderNetworkManaging, Sendable {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, model: String = "gemini-2.5-flash", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func analyzeImage(base64JPEG: String, prompt: String) async throws -> String {
        try await analyzeImages(base64JPEGs: [base64JPEG], prompt: prompt)
    }

    public func analyzeImages(base64JPEGs: [String], prompt: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AIClientError.missingAPIKey(provider: "Gemini")
        }

        let imageParts: [[String: Any]] = base64JPEGs.map { image in
            [
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": image
                ]
            ]
        }

        let parts = [["text": prompt]] + imageParts

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ]
        ]

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(trimmedKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse(provider: "Gemini", statusCode: -1, message: "Respuesta HTTP inválida.")
        }

        guard (200..<300).contains(http.statusCode) else {
            let apiMessage = GeminiErrorExtractor.message(from: responseData) ?? "Sin detalle de error."
            throw AIClientError.invalidResponse(provider: "Gemini", statusCode: http.statusCode, message: apiMessage)
        }

        let envelope = try JSONDecoder().decode(GeminiResponsesEnvelope.self, from: responseData)
        guard let text = envelope.candidates.first?.content.parts.compactMap({ $0.text }).first,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.missingContent(provider: "Gemini")
        }

        return text
    }
}

public struct OpenAINutritionClient: MultimodalNutritionInference, Sendable {
    private let networkManager: ProviderNetworkManaging

    public init(networkManager: ProviderNetworkManaging) {
        self.networkManager = networkManager
    }

    public func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult {
        let imageBase64 = data.base64EncodedString()
        let finalPrompt = NutritionPromptBuilder.systemInstruction + "\n\n" + NutritionPromptBuilder.userPrompt(extraInstruction: prompt)
        let rawText = try await networkManager.analyzeImage(base64JPEG: imageBase64, prompt: finalPrompt)
        let jsonText = try JSONExtractor.extractJSONObject(from: rawText, provider: "OpenAI")

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AIClientError.invalidPayload(provider: "OpenAI", rawText: rawText)
        }
        return try JSONDecoder().decode(NutritionInferenceResult.self, from: jsonData)
    }
}

public struct GeminiNutritionClient: MultimodalNutritionInference, Sendable {
    private let networkManager: ProviderNetworkManaging

    public init(networkManager: ProviderNetworkManaging) {
        self.networkManager = networkManager
    }

    public func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult {
        let imageBase64 = data.base64EncodedString()
        let finalPrompt = NutritionPromptBuilder.systemInstruction + "\n\n" + NutritionPromptBuilder.userPrompt(extraInstruction: prompt)
        let rawText = try await networkManager.analyzeImage(base64JPEG: imageBase64, prompt: finalPrompt)
        let jsonText = try JSONExtractor.extractJSONObject(from: rawText, provider: "Gemini")

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AIClientError.invalidPayload(provider: "Gemini", rawText: rawText)
        }
        return try JSONDecoder().decode(NutritionInferenceResult.self, from: jsonData)
    }
}

public struct FallbackNutritionClient: MultimodalNutritionInference, Sendable {
    private let primary: MultimodalNutritionInference
    private let secondary: MultimodalNutritionInference?

    public init(primary: MultimodalNutritionInference, secondary: MultimodalNutritionInference?) {
        self.primary = primary
        self.secondary = secondary
    }

    public func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult {
        do {
            return try await primary.inferNutrition(fromImageData: data, prompt: prompt)
        } catch let caughtError as AIClientError {
            guard case .invalidResponse(_, let statusCode, _) = caughtError, statusCode == 429 else {
                throw caughtError
            }
            guard let secondary else { throw caughtError }
            return try await secondary.inferNutrition(fromImageData: data, prompt: prompt)
        }
    }
}

public struct OpenAIRecipeClient: MultimodalRecipeInference, Sendable {
    private let networkManager: ProviderNetworkManaging

    public init(networkManager: ProviderNetworkManaging) {
        self.networkManager = networkManager
    }

    public func inferRecipes(fromImageData images: [Data], prompt: String) async throws -> [RecipeSuggestion] {
        guard !images.isEmpty else {
            throw AIClientError.invalidPayload(provider: "OpenAI", rawText: "Sin imágenes para analizar.")
        }
        let base64Images = images.map { $0.base64EncodedString() }
        let finalPrompt = RecipePromptBuilder.systemInstruction + "\n\n" + RecipePromptBuilder.userPrompt(extraInstruction: prompt)
        let rawText = try await networkManager.analyzeImages(base64JPEGs: base64Images, prompt: finalPrompt)
        let jsonText = try JSONExtractor.extractJSONArray(from: rawText, provider: "OpenAI")

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AIClientError.invalidPayload(provider: "OpenAI", rawText: rawText)
        }
        return try JSONDecoder().decode([RecipeSuggestion].self, from: jsonData)
    }
}

public struct GeminiRecipeClient: MultimodalRecipeInference, Sendable {
    private let networkManager: ProviderNetworkManaging

    public init(networkManager: ProviderNetworkManaging) {
        self.networkManager = networkManager
    }

    public func inferRecipes(fromImageData images: [Data], prompt: String) async throws -> [RecipeSuggestion] {
        guard !images.isEmpty else {
            throw AIClientError.invalidPayload(provider: "Gemini", rawText: "Sin imágenes para analizar.")
        }
        let base64Images = images.map { $0.base64EncodedString() }
        let finalPrompt = RecipePromptBuilder.systemInstruction + "\n\n" + RecipePromptBuilder.userPrompt(extraInstruction: prompt)
        let rawText = try await networkManager.analyzeImages(base64JPEGs: base64Images, prompt: finalPrompt)
        let jsonText = try JSONExtractor.extractJSONArray(from: rawText, provider: "Gemini")

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AIClientError.invalidPayload(provider: "Gemini", rawText: rawText)
        }
        return try JSONDecoder().decode([RecipeSuggestion].self, from: jsonData)
    }
}

public struct FallbackRecipeClient: MultimodalRecipeInference, Sendable {
    private let primary: MultimodalRecipeInference
    private let secondary: MultimodalRecipeInference?

    public init(primary: MultimodalRecipeInference, secondary: MultimodalRecipeInference?) {
        self.primary = primary
        self.secondary = secondary
    }

    public func inferRecipes(fromImageData images: [Data], prompt: String) async throws -> [RecipeSuggestion] {
        do {
            return try await primary.inferRecipes(fromImageData: images, prompt: prompt)
        } catch let caughtError as AIClientError {
            guard case .invalidResponse(_, let statusCode, _) = caughtError, statusCode == 429 else {
                throw caughtError
            }
            guard let secondary else { throw caughtError }
            return try await secondary.inferRecipes(fromImageData: images, prompt: prompt)
        }
    }
}

public enum NutritionPromptBuilder {
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
          "category": "string",
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

public enum RecipePromptBuilder {
    public static let systemInstruction = """
    You are a nutrition chef assistant. Return ONLY strict JSON array (no markdown, no prose) using this exact schema:
    [
      {
        "nombre": "string",
        "tiempoMinutos": number,
        "calorias": number,
        "ingredientesUsados": ["string"],
        "ingredientesFaltantes": ["string"],
        "pasos": ["string"]
      }
    ]
    """

    public static func userPrompt(extraInstruction: String) -> String {
        let cleanedInstruction = extraInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Analiza TODAS las imágenes del refrigerador/alacena en conjunto.
        Sugiere exactamente 3 recetas saludables usando principalmente ingredientes detectados.
        Puedes asumir básicos: sal, pimienta, agua y aceite.
        Responde únicamente con el arreglo JSON solicitado.
        Instrucción adicional del usuario: \(cleanedInstruction.isEmpty ? "Ninguna" : cleanedInstruction)
        """
    }
}

public enum JSONExtractor {
    public static func extractJSONObject(from text: String, provider: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }

        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else {
            throw AIClientError.invalidPayload(provider: provider, rawText: text)
        }

        return String(trimmed[start...end])
    }

    public static func extractJSONArray(from text: String, provider: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "[", trimmed.last == "]" {
            return trimmed
        }

        guard let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]") else {
            throw AIClientError.invalidPayload(provider: provider, rawText: text)
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

private enum GeminiErrorExtractor {
    static func message(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data) else {
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

private struct GeminiErrorEnvelope: Decodable {
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

private struct GeminiResponsesEnvelope: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }
            let parts: [Part]
        }
        let content: Content
    }

    let candidates: [Candidate]
}
