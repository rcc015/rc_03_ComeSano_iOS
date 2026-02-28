# ComeSano iOS

Base de la Semana 1 para una app de nutrición conectada con Apple Health.

## Incluye

- Modelo de usuario y meta calórica diaria.
- Cálculo de balance calórico diario y progreso semanal.
- Proveedor HealthKit para calorías activas y basales.
- Dashboard SwiftUI mínimo para visualizar progreso.
- Persistencia local con CoreData.
- Capa de IA multimodal con OpenAI.
- Flujo de foto (cámara/galería) para análisis de comida/alacena.
- Tests unitarios del motor de cálculo.

## Estructura

- `Sources/ComeSanoCore`: dominio y reglas de cálculo.
- `Sources/ComeSanoHealthKit`: integración con HealthKit.
- `Sources/ComeSanoUI`: `DashboardView` y `DashboardViewModel`.
- `Sources/ComeSanoPersistence`: `NSPersistentContainer` y stores para alimentos/alacena/lista.
- `Sources/ComeSanoAI`: cliente OpenAI para analizar foto de comida/alacena.
- `Sources/ComeSanoUI/FoodPhotoAnalyzerView.swift`: captura de foto y visualización de resultados.
- `Sources/ComeSanoUI/FoodPhotoAnalyzerViewModel.swift`: orquestación UI -> IA.
- `App/Sources/ComeSanoApp.swift`: app iOS real (SwiftUI + tabs).
- `App/Config/Info.plist`: plantilla con llaves de permisos HealthKit.
- `project.yml`: especificación XcodeGen para generar `ComeSano.xcodeproj`.
- `Tests/ComeSanoCoreTests`: pruebas de negocio.

## Configuración rápida

1. Proyecto iOS:
   - Ejecuta `xcodegen generate`.
   - Abre `ComeSano.xcodeproj`.
   - Usa el esquema `ComeSanoApp`.
2. OpenAI API key:
   - Método recomendado: pestaña `IA` dentro de la app y botón `Guardar en Keychain`.
   - Método alterno para pruebas rápidas: variable `OPENAI_API_KEY` en Scheme.
3. Core Data local:
   - Inicializa `PersistenceController()` para almacenamiento local en el dispositivo.
4. IA:
   - OpenAI: `NutritionAIClientFactory.makeOpenAI(apiKey: \"...\", model: .gpt4point1)`
5. Recomendado:
   - Guardar API keys en Keychain.
   - Confirmación manual de calorías estimadas por IA antes de guardar.

## Keychain (OpenAI)

La app incluye almacenamiento seguro de la API key en Keychain:

1. Abre la app.
2. Ve a la pestaña `IA`.
3. Pega tu key `sk-...` en el campo seguro.
4. Toca `Guardar en Keychain`.
5. Regresa a `Foto` y analiza.

Si quieres resetearla, usa `Eliminar de Keychain`.

## Flujo IA (foto -> JSON -> UI)

1. Acceso a cámara/galería:
   - `FoodPhotoAnalyzerView` usa `UIImagePickerController` (cámara) y `PhotosPicker` (galería).
2. Network manager:
   - `OpenAINetworkManager` envía la imagen en base64 al endpoint `POST /v1/responses`.
3. Prompt fijo:
   - `OpenAINutritionPromptBuilder.systemInstruction` fuerza salida JSON estricta.
4. Decodificación:
   - `OpenAINutritionClient` extrae JSON y decodifica a `NutritionInferenceResult`.
5. Datos listos para app:
   - `foodItems` para calorías/macros.
   - `shoppingList` para sugerencias de súper.

## HealthKit (lectura + escritura)

La clase `HealthKitNutritionStore` ya incluye:

1. Autorización:
   - Lee `activeEnergyBurned` y `basalEnergyBurned`.
   - Escribe `dietaryEnergyConsumed`.
2. Lectura:
   - `fetchBurnedCalories(for:)`.
3. Escritura:
   - `saveDietaryEnergy(kilocalories:at:)`.

Ejemplo:

```swift
let health = HealthKitNutritionStore()
try await health.requestAuthorization()
let burned = try await health.fetchBurnedCalories(for: .now)
try await health.saveDietaryEnergy(kilocalories: 650, at: .now)
```

## Nota futura

Cuando tengas Apple Developer habilitado, se puede migrar este contenedor a `NSPersistentCloudKitContainer` para sincronización por iCloud sin cambiar la capa de dominio.

## Siguiente fase sugerida

1. Reemplazar `MockIntakeProvider` por persistencia real de comidas.
2. Guardar resultados de `FoodPhotoAnalyzerView` en Core Data.
3. Crear target Watch App y sincronizar recordatorios/comidas.
4. Programar recordatorios de agua/comidas con `UserNotifications`.
