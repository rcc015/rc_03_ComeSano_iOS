import Foundation
import SwiftUI
import ComeSanoCore
import ComeSanoAI

struct NutritionMeal: Codable, Sendable {
    let titulo: String
    let calorias: Int
    let descripcion: String
    let horaSugerida: String

    private enum CodingKeys: String, CodingKey {
        case titulo, calorias, descripcion, horaSugerida
    }

    init(titulo: String, calorias: Int, descripcion: String, horaSugerida: String = "") {
        self.titulo = titulo
        self.calorias = calorias
        self.descripcion = descripcion
        self.horaSugerida = horaSugerida
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        titulo = try container.decodeIfPresent(String.self, forKey: .titulo) ?? "Comida"
        descripcion = try container.decodeIfPresent(String.self, forKey: .descripcion) ?? ""
        calorias = container.decodeFlexibleInt(forKey: .calorias) ?? 0
        horaSugerida = try container.decodeIfPresent(String.self, forKey: .horaSugerida) ?? ""
    }
}

struct NutritionPlan: Codable, Sendable {
    let caloriasDiarias: Int
    let proteinaGramos: Int
    let carbohidratosGramos: Int
    let grasasGramos: Int
    let desayuno: NutritionMeal
    let colacion1: NutritionMeal
    let comida: NutritionMeal
    let colacion2: NutritionMeal
    let cena: NutritionMeal
    let createdAt: Date
    let source: String

    init(
        caloriasDiarias: Int,
        proteinaGramos: Int,
        carbohidratosGramos: Int,
        grasasGramos: Int,
        desayuno: NutritionMeal,
        colacion1: NutritionMeal,
        comida: NutritionMeal,
        colacion2: NutritionMeal,
        cena: NutritionMeal,
        createdAt: Date = .now,
        source: String = "ai"
    ) {
        self.caloriasDiarias = caloriasDiarias
        self.proteinaGramos = proteinaGramos
        self.carbohidratosGramos = carbohidratosGramos
        self.grasasGramos = grasasGramos
        self.desayuno = desayuno
        self.colacion1 = colacion1
        self.comida = comida
        self.colacion2 = colacion2
        self.cena = cena
        self.createdAt = createdAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case caloriasDiarias, proteinaGramos, carbohidratosGramos, grasasGramos
        case desayuno, colacion1, comida, colacion2, cena
        case createdAt, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        caloriasDiarias = container.decodeFlexibleInt(forKey: .caloriasDiarias) ?? 0
        proteinaGramos = container.decodeFlexibleInt(forKey: .proteinaGramos) ?? 0
        carbohidratosGramos = container.decodeFlexibleInt(forKey: .carbohidratosGramos) ?? 0
        grasasGramos = container.decodeFlexibleInt(forKey: .grasasGramos) ?? 0
        desayuno = (try? container.decode(NutritionMeal.self, forKey: .desayuno)) ?? NutritionMeal(titulo: "Desayuno", calorias: 0, descripcion: "")
        colacion1 = (try? container.decode(NutritionMeal.self, forKey: .colacion1)) ?? NutritionMeal(titulo: "Colación 1", calorias: 0, descripcion: "")
        comida = (try? container.decode(NutritionMeal.self, forKey: .comida)) ?? NutritionMeal(titulo: "Comida", calorias: 0, descripcion: "")
        colacion2 = (try? container.decode(NutritionMeal.self, forKey: .colacion2)) ?? NutritionMeal(titulo: "Colación 2", calorias: 0, descripcion: "")
        cena = (try? container.decode(NutritionMeal.self, forKey: .cena)) ?? NutritionMeal(titulo: "Cena", calorias: 0, descripcion: "")

        if let dateString = try? container.decode(String.self, forKey: .createdAt),
           let parsed = Self.parseISO8601(dateString) {
            createdAt = parsed
        } else {
            createdAt = .now
        }
        source = (try? container.decode(String.self, forKey: .source)) ?? "ai"
    }

    static func parseISO8601(_ text: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = withFractional.date(from: text) {
            return value
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: text)
    }
}

struct WeeklyPlanDay: Codable, Sendable, Identifiable {
    let id: UUID
    let dia: String
    let desayuno: NutritionMeal
    let colacion1: NutritionMeal
    let comida: NutritionMeal
    let colacion2: NutritionMeal
    let cena: NutritionMeal
    let caloriasTotales: Int

    init(
        id: UUID = UUID(),
        dia: String,
        desayuno: NutritionMeal,
        colacion1: NutritionMeal,
        comida: NutritionMeal,
        colacion2: NutritionMeal,
        cena: NutritionMeal,
        caloriasTotales: Int
    ) {
        self.id = id
        self.dia = dia
        self.desayuno = desayuno
        self.colacion1 = colacion1
        self.comida = comida
        self.colacion2 = colacion2
        self.cena = cena
        self.caloriasTotales = caloriasTotales
    }

    private enum CodingKeys: String, CodingKey {
        case id, dia, desayuno, colacion1, comida, colacion2, cena, caloriasTotales
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        dia = try container.decodeIfPresent(String.self, forKey: .dia) ?? "Día"
        desayuno = (try? container.decode(NutritionMeal.self, forKey: .desayuno)) ?? NutritionMeal(titulo: "Desayuno", calorias: 0, descripcion: "")
        colacion1 = (try? container.decode(NutritionMeal.self, forKey: .colacion1)) ?? NutritionMeal(titulo: "Colación 1", calorias: 0, descripcion: "")
        comida = (try? container.decode(NutritionMeal.self, forKey: .comida)) ?? NutritionMeal(titulo: "Comida", calorias: 0, descripcion: "")
        colacion2 = (try? container.decode(NutritionMeal.self, forKey: .colacion2)) ?? NutritionMeal(titulo: "Colación 2", calorias: 0, descripcion: "")
        cena = (try? container.decode(NutritionMeal.self, forKey: .cena)) ?? NutritionMeal(titulo: "Cena", calorias: 0, descripcion: "")
        caloriasTotales = container.decodeFlexibleInt(forKey: .caloriasTotales) ?? (desayuno.calorias + colacion1.calorias + comida.calorias + colacion2.calorias + cena.calorias)
    }
}

struct NutritionMealSchedule: Sendable {
    let desayuno: String
    let colacion1: String
    let comida: String
    let colacion2: String
    let cena: String
}

struct WeeklyNutritionPlan: Codable, Sendable {
    let caloriasObjetivoDiarias: Int
    let proteinaObjetivoGramos: Int
    let carbohidratosObjetivoGramos: Int
    let grasasObjetivoGramos: Int
    let dias: [WeeklyPlanDay]
    let recomendaciones: String
    let createdAt: Date
    let source: String

    init(
        caloriasObjetivoDiarias: Int,
        proteinaObjetivoGramos: Int,
        carbohidratosObjetivoGramos: Int,
        grasasObjetivoGramos: Int,
        dias: [WeeklyPlanDay],
        recomendaciones: String,
        createdAt: Date = .now,
        source: String = "ai"
    ) {
        self.caloriasObjetivoDiarias = caloriasObjetivoDiarias
        self.proteinaObjetivoGramos = proteinaObjetivoGramos
        self.carbohidratosObjetivoGramos = carbohidratosObjetivoGramos
        self.grasasObjetivoGramos = grasasObjetivoGramos
        self.dias = dias
        self.recomendaciones = recomendaciones
        self.createdAt = createdAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case caloriasObjetivoDiarias, proteinaObjetivoGramos, carbohidratosObjetivoGramos, grasasObjetivoGramos
        case dias, recomendaciones, createdAt, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        caloriasObjetivoDiarias = container.decodeFlexibleInt(forKey: .caloriasObjetivoDiarias) ?? 0
        proteinaObjetivoGramos = container.decodeFlexibleInt(forKey: .proteinaObjetivoGramos) ?? 0
        carbohidratosObjetivoGramos = container.decodeFlexibleInt(forKey: .carbohidratosObjetivoGramos) ?? 0
        grasasObjetivoGramos = container.decodeFlexibleInt(forKey: .grasasObjetivoGramos) ?? 0
        dias = (try? container.decode([WeeklyPlanDay].self, forKey: .dias)) ?? []
        recomendaciones = (try? container.decode(String.self, forKey: .recomendaciones)) ?? ""

        if let dateString = try? container.decode(String.self, forKey: .createdAt),
           let parsed = NutritionPlan.parseISO8601(dateString) {
            createdAt = parsed
        } else {
            createdAt = .now
        }
        source = (try? container.decode(String.self, forKey: .source)) ?? "ai"
    }
}

struct NutritionProfileInput: Sendable {
    let nombre: String
    let sexo: String
    let edad: Int
    let alturaCM: Double
    let pesoKG: Double
    let meta: PrimaryGoal
    let diasGym: Int
    let preferenciaAlimenticia: String
    let alergias: String
    let horarios: NutritionMealSchedule
}

struct WeeklyPlanGenerationInput: Sendable {
    let profile: NutritionProfileInput
    let ajustes: String
    let ingredientesRefri: [String]
}

struct WeeklyShoppingListInput: Sendable {
    let profile: NutritionProfileInput
    let weeklyPlan: WeeklyNutritionPlan
    let ingredientesRefri: [String]
}

enum WeeklyPlanSlot: String, CaseIterable, Codable, Sendable {
    case current
    case next

    var title: String {
        switch self {
        case .current: return "Semana Actual"
        case .next: return "Próxima Semana"
        }
    }
}

protocol NutritionPlanGenerating: Sendable {
    func generatePlan(for profile: NutritionProfileInput) async throws -> NutritionPlan
    func generateWeeklyPlan(for input: WeeklyPlanGenerationInput) async throws -> WeeklyNutritionPlan
    func generateWeeklyShoppingList(for input: WeeklyShoppingListInput) async throws -> [ShoppingListItem]
}

struct EmptyNutritionPlanGenerator: NutritionPlanGenerating {
    func generatePlan(for profile: NutritionProfileInput) async throws -> NutritionPlan {
        _ = profile
        throw NutritionPlanGenerationError.missingAPIKey
    }

    func generateWeeklyPlan(for input: WeeklyPlanGenerationInput) async throws -> WeeklyNutritionPlan {
        _ = input
        throw NutritionPlanGenerationError.missingAPIKey
    }

    func generateWeeklyShoppingList(for input: WeeklyShoppingListInput) async throws -> [ShoppingListItem] {
        _ = input
        throw NutritionPlanGenerationError.missingAPIKey
    }
}

struct NutritionPlanRemoteGenerator: NutritionPlanGenerating {
    let primaryProvider: AIProviderChoice
    let openAIKey: String?
    let geminiKey: String?
    let backendBaseURL: URL?
    let backendSessionToken: String?
    let openAIModel: String
    let geminiModel: String
    let session: URLSession

    init(
        primaryProvider: AIProviderChoice,
        openAIKey: String?,
        geminiKey: String?,
        backendBaseURL: URL? = nil,
        backendSessionToken: String? = nil,
        openAIModel: String = "gpt-4.1-mini",
        geminiModel: String = "gemini-2.5-flash",
        session: URLSession = .shared
    ) {
        self.primaryProvider = primaryProvider
        self.openAIKey = openAIKey
        self.geminiKey = geminiKey
        self.backendBaseURL = backendBaseURL
        self.backendSessionToken = backendSessionToken
        self.openAIModel = openAIModel
        self.geminiModel = geminiModel
        self.session = session
    }

    func generatePlan(for profile: NutritionProfileInput) async throws -> NutritionPlan {
        let prompt = NutritionPlanPromptBuilder.prompt(for: profile)

        switch primaryProvider {
        case .backend:
            if let url = normalizedURL(backendBaseURL), let token = normalized(backendSessionToken) {
                return try await generateWithBackend(prompt: prompt, baseURL: url, sessionToken: token)
            }
            if let key = normalized(geminiKey) {
                return try await generateWithGemini(prompt: prompt, apiKey: key)
            }
            if let key = normalized(openAIKey) {
                return try await generateWithOpenAI(prompt: prompt, apiKey: key)
            }
        case .gemini:
            if let key = normalized(geminiKey) {
                return try await generateWithGemini(prompt: prompt, apiKey: key)
            }
            if let key = normalized(openAIKey) {
                return try await generateWithOpenAI(prompt: prompt, apiKey: key)
            }
        case .openAI:
            if let key = normalized(openAIKey) {
                return try await generateWithOpenAI(prompt: prompt, apiKey: key)
            }
            if let key = normalized(geminiKey) {
                return try await generateWithGemini(prompt: prompt, apiKey: key)
            }
        }

        throw NutritionPlanGenerationError.missingAPIKey
    }

    func generateWeeklyPlan(for input: WeeklyPlanGenerationInput) async throws -> WeeklyNutritionPlan {
        let prompt = NutritionPlanPromptBuilder.weeklyPrompt(for: input)

        switch primaryProvider {
        case .backend:
            if let url = normalizedURL(backendBaseURL), let token = normalized(backendSessionToken) {
                return try await generateWeeklyWithBackend(prompt: prompt, baseURL: url, sessionToken: token)
            }
            if let key = normalized(geminiKey) {
                return try await generateWeeklyWithGemini(prompt: prompt, apiKey: key)
            }
            if let key = normalized(openAIKey) {
                return try await generateWeeklyWithOpenAI(prompt: prompt, apiKey: key)
            }
        case .gemini:
            if let key = normalized(geminiKey) {
                return try await generateWeeklyWithGemini(prompt: prompt, apiKey: key)
            }
            if let key = normalized(openAIKey) {
                return try await generateWeeklyWithOpenAI(prompt: prompt, apiKey: key)
            }
        case .openAI:
            if let key = normalized(openAIKey) {
                return try await generateWeeklyWithOpenAI(prompt: prompt, apiKey: key)
            }
            if let key = normalized(geminiKey) {
                return try await generateWeeklyWithGemini(prompt: prompt, apiKey: key)
            }
        }

        throw NutritionPlanGenerationError.missingAPIKey
    }

    func generateWeeklyShoppingList(for input: WeeklyShoppingListInput) async throws -> [ShoppingListItem] {
        let prompt = NutritionPlanPromptBuilder.weeklyShoppingPrompt(for: input)

        let rawText: String
        switch primaryProvider {
        case .backend:
            if let url = normalizedURL(backendBaseURL), let token = normalized(backendSessionToken) {
                rawText = try await generateTextWithBackend(prompt: prompt, path: "/v1/ai/weekly-shopping", baseURL: url, sessionToken: token)
            } else if let key = normalized(geminiKey) {
                rawText = try await generateTextWithGemini(prompt: prompt, apiKey: key)
            } else if let key = normalized(openAIKey) {
                rawText = try await generateTextWithOpenAI(prompt: prompt, apiKey: key)
            } else {
                throw NutritionPlanGenerationError.missingAPIKey
            }
        case .gemini:
            if let key = normalized(geminiKey) {
                rawText = try await generateTextWithGemini(prompt: prompt, apiKey: key)
            } else if let key = normalized(openAIKey) {
                rawText = try await generateTextWithOpenAI(prompt: prompt, apiKey: key)
            } else {
                throw NutritionPlanGenerationError.missingAPIKey
            }
        case .openAI:
            if let key = normalized(openAIKey) {
                rawText = try await generateTextWithOpenAI(prompt: prompt, apiKey: key)
            } else if let key = normalized(geminiKey) {
                rawText = try await generateTextWithGemini(prompt: prompt, apiKey: key)
            } else {
                throw NutritionPlanGenerationError.missingAPIKey
            }
        }

        let jsonText = try JSONExtractor.extractJSONArray(from: rawText, provider: "PlanSemanal")
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw NutritionPlanGenerationError.invalidPayload
        }
        let items = try JSONDecoder().decode([AIShoppingItem].self, from: jsonData)
        return Self.normalizeShoppingItems(items.map(\.asShoppingListItem))
    }

    private func normalized(_ key: String?) -> String? {
        guard let key else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        let trimmed = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private func generateTextWithGemini(prompt: String, apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NutritionPlanGenerationError.invalidResponse(message: "Respuesta HTTP inválida.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(decoding: data, as: UTF8.self)
            throw NutritionPlanGenerationError.invalidResponse(message: "Gemini \(http.statusCode): \(raw)")
        }

        let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
        guard let text = envelope.candidates.first?.content.parts.compactMap(\.text).first else {
            throw NutritionPlanGenerationError.invalidPayload
        }
        return text
    }

    private func generateTextWithOpenAI(prompt: String, apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "model": openAIModel,
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NutritionPlanGenerationError.invalidResponse(message: "Respuesta HTTP inválida.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(decoding: data, as: UTF8.self)
            throw NutritionPlanGenerationError.invalidResponse(message: "OpenAI \(http.statusCode): \(raw)")
        }

        let envelope = try JSONDecoder().decode(OpenAIEnvelope.self, from: data)
        let outputText = envelope.outputText ?? envelope.output.first?.content?.first?.text
        guard let text = outputText, !text.isEmpty else {
            throw NutritionPlanGenerationError.invalidPayload
        }
        return text
    }

    private func generateTextWithBackend(prompt: String, path: String, baseURL: URL, sessionToken: String) async throws -> String {
        let body: [String: Any] = ["prompt": prompt]
        let endpoint = URL(string: path, relativeTo: baseURL)!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NutritionPlanGenerationError.invalidResponse(message: "Respuesta HTTP inválida.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(decoding: data, as: UTF8.self)
            throw NutritionPlanGenerationError.invalidResponse(message: "Backend \(http.statusCode): \(raw)")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let text = json["content"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let text = json["output_text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw NutritionPlanGenerationError.invalidPayload }
        return raw
    }

    private func generateWeeklyWithGemini(prompt: String, apiKey: String) async throws -> WeeklyNutritionPlan {
        let rawText = try await generateTextWithGemini(prompt: prompt, apiKey: apiKey)
        let jsonText = try JSONExtractor.extractJSONObject(from: rawText, provider: "Gemini")
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw NutritionPlanGenerationError.invalidPayload
        }

        var plan = try JSONDecoder().decode(WeeklyNutritionPlan.self, from: jsonData)
        plan = WeeklyNutritionPlan(
            caloriasObjetivoDiarias: plan.caloriasObjetivoDiarias,
            proteinaObjetivoGramos: plan.proteinaObjetivoGramos,
            carbohidratosObjetivoGramos: plan.carbohidratosObjetivoGramos,
            grasasObjetivoGramos: plan.grasasObjetivoGramos,
            dias: plan.dias,
            recomendaciones: plan.recomendaciones,
            createdAt: .now,
            source: "gemini"
        )
        guard plan.dias.count == 7 else {
            throw NutritionPlanGenerationError.invalidPayload
        }
        return plan
    }

    private func generateWeeklyWithOpenAI(prompt: String, apiKey: String) async throws -> WeeklyNutritionPlan {
        let rawText = try await generateTextWithOpenAI(prompt: prompt, apiKey: apiKey)
        let jsonText = try JSONExtractor.extractJSONObject(from: rawText, provider: "OpenAI")
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw NutritionPlanGenerationError.invalidPayload
        }

        var plan = try JSONDecoder().decode(WeeklyNutritionPlan.self, from: jsonData)
        plan = WeeklyNutritionPlan(
            caloriasObjetivoDiarias: plan.caloriasObjetivoDiarias,
            proteinaObjetivoGramos: plan.proteinaObjetivoGramos,
            carbohidratosObjetivoGramos: plan.carbohidratosObjetivoGramos,
            grasasObjetivoGramos: plan.grasasObjetivoGramos,
            dias: plan.dias,
            recomendaciones: plan.recomendaciones,
            createdAt: .now,
            source: "openai"
        )
        guard plan.dias.count == 7 else {
            throw NutritionPlanGenerationError.invalidPayload
        }
        return plan
    }

    private func generateWeeklyWithBackend(prompt: String, baseURL: URL, sessionToken: String) async throws -> WeeklyNutritionPlan {
        let rawText = try await generateTextWithBackend(prompt: prompt, path: "/v1/ai/weekly-plan", baseURL: baseURL, sessionToken: sessionToken)
        let jsonText = try JSONExtractor.extractJSONObject(from: rawText, provider: "Backend")
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw NutritionPlanGenerationError.invalidPayload
        }

        var plan = try JSONDecoder().decode(WeeklyNutritionPlan.self, from: jsonData)
        plan = WeeklyNutritionPlan(
            caloriasObjetivoDiarias: plan.caloriasObjetivoDiarias,
            proteinaObjetivoGramos: plan.proteinaObjetivoGramos,
            carbohidratosObjetivoGramos: plan.carbohidratosObjetivoGramos,
            grasasObjetivoGramos: plan.grasasObjetivoGramos,
            dias: plan.dias,
            recomendaciones: plan.recomendaciones,
            createdAt: .now,
            source: "backend"
        )
        guard plan.dias.count == 7 else {
            throw NutritionPlanGenerationError.invalidPayload
        }
        return plan
    }

    private func generateWithGemini(prompt: String, apiKey: String) async throws -> NutritionPlan {
        let rawText = try await generateTextWithGemini(prompt: prompt, apiKey: apiKey)
        let jsonText = try JSONExtractor.extractJSONObject(from: rawText, provider: "Gemini")
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw NutritionPlanGenerationError.invalidPayload
        }
        var plan = try JSONDecoder().decode(NutritionPlan.self, from: jsonData)
        plan = NutritionPlan(
            caloriasDiarias: plan.caloriasDiarias,
            proteinaGramos: plan.proteinaGramos,
            carbohidratosGramos: plan.carbohidratosGramos,
            grasasGramos: plan.grasasGramos,
            desayuno: plan.desayuno,
            colacion1: plan.colacion1,
            comida: plan.comida,
            colacion2: plan.colacion2,
            cena: plan.cena,
            createdAt: .now,
            source: "gemini"
        )
        return plan
    }

    private func generateWithOpenAI(prompt: String, apiKey: String) async throws -> NutritionPlan {
        let rawText = try await generateTextWithOpenAI(prompt: prompt, apiKey: apiKey)
        let jsonText = try JSONExtractor.extractJSONObject(from: rawText, provider: "OpenAI")
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw NutritionPlanGenerationError.invalidPayload
        }
        var plan = try JSONDecoder().decode(NutritionPlan.self, from: jsonData)
        plan = NutritionPlan(
            caloriasDiarias: plan.caloriasDiarias,
            proteinaGramos: plan.proteinaGramos,
            carbohidratosGramos: plan.carbohidratosGramos,
            grasasGramos: plan.grasasGramos,
            desayuno: plan.desayuno,
            colacion1: plan.colacion1,
            comida: plan.comida,
            colacion2: plan.colacion2,
            cena: plan.cena,
            createdAt: .now,
            source: "openai"
        )
        return plan
    }

    private func generateWithBackend(prompt: String, baseURL: URL, sessionToken: String) async throws -> NutritionPlan {
        let rawText = try await generateTextWithBackend(prompt: prompt, path: "/v1/ai/daily-plan", baseURL: baseURL, sessionToken: sessionToken)
        let jsonText = try JSONExtractor.extractJSONObject(from: rawText, provider: "Backend")
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw NutritionPlanGenerationError.invalidPayload
        }
        var plan = try JSONDecoder().decode(NutritionPlan.self, from: jsonData)
        plan = NutritionPlan(
            caloriasDiarias: plan.caloriasDiarias,
            proteinaGramos: plan.proteinaGramos,
            carbohidratosGramos: plan.carbohidratosGramos,
            grasasGramos: plan.grasasGramos,
            desayuno: plan.desayuno,
            colacion1: plan.colacion1,
            comida: plan.comida,
            colacion2: plan.colacion2,
            cena: plan.cena,
            createdAt: .now,
            source: "backend"
        )
        return plan
    }

    private static func normalizeShoppingItems(_ items: [ShoppingListItem]) -> [ShoppingListItem] {
        var map: [String: ShoppingListItem] = [:]
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if let existing = map[key] {
                map[key] = ShoppingListItem(
                    id: existing.id,
                    name: existing.name,
                    category: existing.category.isEmpty ? item.category : existing.category,
                    quantity: max(existing.quantity, item.quantity),
                    unit: existing.unit.isEmpty ? item.unit : existing.unit,
                    isPurchased: existing.isPurchased
                )
            } else {
                map[key] = ShoppingListItem(
                    name: name,
                    category: item.category.isEmpty ? "Otros" : item.category,
                    quantity: item.quantity <= 0 ? 1 : item.quantity,
                    unit: item.unit.isEmpty ? "pieza" : item.unit,
                    isPurchased: false
                )
            }
        }
        return map.values.sorted { $0.category < $1.category }
    }
}

enum NutritionPlanGenerationError: LocalizedError {
    case missingAPIKey
    case invalidResponse(message: String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No hay credenciales configuradas para generar plan (API key o sesión backend)."
        case let .invalidResponse(message):
            return "La IA no respondió correctamente: \(message)"
        case .invalidPayload:
            return "La IA respondió en formato inválido."
        }
    }
}

enum NutritionPlanPromptBuilder {
    static func prompt(for profile: NutritionProfileInput) -> String {
        """
        Eres un nutriólogo deportivo. Crea un plan alimenticio de 1 día para este perfil:
        - Nombre: \(profile.nombre)
        - Sexo: \(profile.sexo)
        - Edad: \(profile.edad)
        - Altura: \(Int(profile.alturaCM.rounded())) cm
        - Peso: \(Int(profile.pesoKG.rounded())) kg
        - Meta: \(goalText(profile.meta))
        - Días de gym por semana: \(profile.diasGym)
        - Preferencia alimenticia: \(profile.preferenciaAlimenticia)
        - Alergias/restricciones: \(profile.alergias.isEmpty ? "Ninguna" : profile.alergias)
        - Horarios sugeridos:
          desayuno \(profile.horarios.desayuno), colación 1 \(profile.horarios.colacion1), comida \(profile.horarios.comida), colación 2 \(profile.horarios.colacion2), cena \(profile.horarios.cena)

        Reglas:
        1) Calcula calorías y macros coherentes para la meta.
        2) Propón desayuno, colación 1, comida, colación 2 y cena realistas.
        3) Responde únicamente JSON estricto, sin markdown, con este esquema exacto:
        {
          "caloriasDiarias": 2100,
          "proteinaGramos": 150,
          "carbohidratosGramos": 200,
          "grasasGramos": 70,
          "desayuno": {"titulo":"", "calorias":450, "descripcion":"", "horaSugerida":"10:30"},
          "colacion1": {"titulo":"", "calorias":180, "descripcion":"", "horaSugerida":"13:00"},
          "comida": {"titulo":"", "calorias":750, "descripcion":"", "horaSugerida":"15:30"},
          "colacion2": {"titulo":"", "calorias":180, "descripcion":"", "horaSugerida":"18:30"},
          "cena": {"titulo":"", "calorias":600, "descripcion":"", "horaSugerida":"21:00"},
          "createdAt": "2026-01-01T00:00:00Z",
          "source": "ai"
        }
        """
    }

    private static func goalText(_ goal: PrimaryGoal) -> String {
        switch goal {
        case .loseFat: return "Perder peso"
        case .maintain: return "Mantener peso"
        case .gainMuscle: return "Ganar masa muscular"
        }
    }

    static func weeklyPrompt(for input: WeeklyPlanGenerationInput) -> String {
        let profile = input.profile
        let ajustes = input.ajustes.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredientes = input.ingredientesRefri.joined(separator: ", ")

        return """
        Eres un nutriólogo deportivo. Crea un plan alimenticio semanal de 7 días (lunes a domingo) para este perfil:
        - Nombre: \(profile.nombre)
        - Sexo: \(profile.sexo)
        - Edad: \(profile.edad)
        - Altura: \(Int(profile.alturaCM.rounded())) cm
        - Peso: \(Int(profile.pesoKG.rounded())) kg
        - Meta: \(goalText(profile.meta))
        - Días de gym por semana: \(profile.diasGym)
        - Preferencia alimenticia: \(profile.preferenciaAlimenticia)
        - Alergias/restricciones: \(profile.alergias.isEmpty ? "Ninguna" : profile.alergias)
        - Ajustes solicitados por usuario: \(ajustes.isEmpty ? "Ninguno" : ajustes)
        - Ingredientes disponibles en refri/alacena: \(ingredientes.isEmpty ? "No especificados" : ingredientes)
        - Horarios sugeridos:
          desayuno \(profile.horarios.desayuno), colación 1 \(profile.horarios.colacion1), comida \(profile.horarios.comida), colación 2 \(profile.horarios.colacion2), cena \(profile.horarios.cena)

        Reglas:
        1) Entregar 7 días completos con desayuno, colación 1, comida, colación 2 y cena.
        2) Mantener coherencia calórica/macros con objetivo.
        3) Priorizar ingredientes de refri si se proporcionan.
        4) Responder únicamente JSON estricto con este esquema:
        {
          "caloriasObjetivoDiarias": 2100,
          "proteinaObjetivoGramos": 170,
          "carbohidratosObjetivoGramos": 200,
          "grasasObjetivoGramos": 70,
          "dias": [
            {
              "dia": "Lunes",
              "desayuno": {"titulo":"", "calorias":450, "descripcion":"", "horaSugerida":"10:30"},
              "colacion1": {"titulo":"", "calorias":180, "descripcion":"", "horaSugerida":"13:00"},
              "comida": {"titulo":"", "calorias":850, "descripcion":"", "horaSugerida":"15:30"},
              "colacion2": {"titulo":"", "calorias":180, "descripcion":"", "horaSugerida":"18:30"},
              "cena": {"titulo":"", "calorias":800, "descripcion":"", "horaSugerida":"21:00"},
              "caloriasTotales": 2100
            }
          ],
          "recomendaciones": "Texto breve",
          "createdAt": "2026-01-01T00:00:00Z",
          "source": "ai"
        }
        """
    }

    static func weeklyShoppingPrompt(for input: WeeklyShoppingListInput) -> String {
        let profile = input.profile
        let ingredientes = input.ingredientesRefri.joined(separator: ", ")
        let weeklySummary = input.weeklyPlan.dias.map { day in
            "\(day.dia): \(day.desayuno.titulo), \(day.colacion1.titulo), \(day.comida.titulo), \(day.colacion2.titulo), \(day.cena.titulo)"
        }.joined(separator: " | ")

        return """
        Eres un asistente de compras de nutrición. Genera lista de súper semanal para el siguiente plan:
        - Meta: \(goalText(profile.meta))
        - Preferencia alimenticia: \(profile.preferenciaAlimenticia)
        - Alergias/restricciones: \(profile.alergias.isEmpty ? "Ninguna" : profile.alergias)
        - Plan semanal: \(weeklySummary)
        - Ingredientes ya disponibles en refri/alacena: \(ingredientes.isEmpty ? "No especificados" : ingredientes)

        Reglas:
        1) Excluir ingredientes ya disponibles.
        2) Agrupar por categoría.
        3) Cantidades realistas para 7 días.
        4) Responder únicamente JSON estricto en arreglo con el esquema:
        [
          {"name":"Pechuga de pollo", "category":"Proteínas", "quantity":1.5, "unit":"kg", "isPurchased":false}
        ]
        """
    }
}

@MainActor
final class NutritionPlanStore: ObservableObject {
    @Published private(set) var currentPlan: NutritionPlan?
    @Published private(set) var weeklyPlansBySlot: [WeeklyPlanSlot: WeeklyNutritionPlan] = [:]
    @Published private(set) var frequentAdjustments: [String] = []
    private let defaults: UserDefaults
    private let key = "nutrition.plan.current"
    private let weeklyCurrentKey = "nutrition.plan.weekly.current"
    private let weeklyNextKey = "nutrition.plan.weekly.next"
    private let frequentAdjustmentsKey = "nutrition.plan.adjustments.frequent"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let plan = try? JSONDecoder().decode(NutritionPlan.self, from: data) {
            currentPlan = plan
        }
        if let data = defaults.data(forKey: weeklyCurrentKey),
           let plan = try? JSONDecoder().decode(WeeklyNutritionPlan.self, from: data) {
            weeklyPlansBySlot[.current] = plan
        }
        if let data = defaults.data(forKey: weeklyNextKey),
           let plan = try? JSONDecoder().decode(WeeklyNutritionPlan.self, from: data) {
            weeklyPlansBySlot[.next] = plan
        }
        if let array = defaults.array(forKey: frequentAdjustmentsKey) as? [String] {
            frequentAdjustments = array
        }
    }

    func save(_ plan: NutritionPlan) {
        currentPlan = plan
        if let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: key)
        }
    }

    func saveWeekly(_ plan: WeeklyNutritionPlan, for slot: WeeklyPlanSlot = .current) {
        weeklyPlansBySlot[slot] = plan
        if let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: slot == .current ? weeklyCurrentKey : weeklyNextKey)
        }
    }

    func weeklyPlan(for slot: WeeklyPlanSlot) -> WeeklyNutritionPlan? {
        weeklyPlansBySlot[slot]
    }

    func saveFrequentAdjustment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var values = frequentAdjustments.filter {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != normalized
        }
        values.insert(trimmed, at: 0)
        if values.count > 8 {
            values = Array(values.prefix(8))
        }
        frequentAdjustments = values
        defaults.set(values, forKey: frequentAdjustmentsKey)
    }
}

private struct GeminiEnvelope: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}

private struct OpenAIEnvelope: Decodable {
    struct Item: Decodable {
        struct Content: Decodable { let text: String? }
        let content: [Content]?
    }
    let output: [Item]
    let outputText: String?

    private enum CodingKeys: String, CodingKey {
        case output
        case outputText = "output_text"
    }
}

private struct AIShoppingItem: Decodable {
    let name: String
    let category: String
    let quantity: Double
    let unit: String
    let isPurchased: Bool

    private enum CodingKeys: String, CodingKey {
        case name, category, quantity, unit, isPurchased
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        category = (try? container.decode(String.self, forKey: .category)) ?? "Otros"
        if let q = try? container.decode(Double.self, forKey: .quantity) {
            quantity = q
        } else if let q = try? container.decode(Int.self, forKey: .quantity) {
            quantity = Double(q)
        } else if let q = try? container.decode(String.self, forKey: .quantity),
                  let parsed = Double(q.replacingOccurrences(of: ",", with: ".")) {
            quantity = parsed
        } else {
            quantity = 1
        }
        unit = (try? container.decode(String.self, forKey: .unit)) ?? "pieza"
        isPurchased = (try? container.decode(Bool.self, forKey: .isPurchased)) ?? false
    }

    var asShoppingListItem: ShoppingListItem {
        ShoppingListItem(
            name: name,
            category: category,
            quantity: quantity,
            unit: unit,
            isPurchased: isPurchased
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        if let text = try? decode(String.self, forKey: key) {
            let normalized = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
            if let intValue = Int(normalized) {
                return intValue
            }
            if let doubleValue = Double(normalized) {
                return Int(doubleValue.rounded())
            }
        }
        return nil
    }
}
