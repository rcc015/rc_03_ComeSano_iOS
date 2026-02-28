# ComeSano iOS

Base de la Semana 1 para una app de nutrición conectada con Apple Health.

## Incluye

- Modelo de usuario y meta calórica diaria.
- Cálculo de balance calórico diario y progreso semanal.
- Proveedor HealthKit para calorías activas y basales.
- Dashboard SwiftUI mínimo para visualizar progreso.
- Persistencia local con CoreData.
- Capa de IA multimodal con OpenAI.
- Tests unitarios del motor de cálculo.

## Estructura

- `Sources/ComeSanoCore`: dominio y reglas de cálculo.
- `Sources/ComeSanoHealthKit`: integración con HealthKit.
- `Sources/ComeSanoUI`: `DashboardView` y `DashboardViewModel`.
- `Sources/ComeSanoPersistence`: `NSPersistentContainer` y stores para alimentos/alacena/lista.
- `Sources/ComeSanoAI`: cliente OpenAI para analizar foto de comida/alacena.
- `App/Config/Info.plist`: plantilla con llaves de permisos HealthKit.
- `Tests/ComeSanoCoreTests`: pruebas de negocio.

## Configuración rápida

1. Core Data local:
   - Inicializa `PersistenceController()` para almacenamiento local en el dispositivo.
2. IA:
   - OpenAI: `NutritionAIClientFactory.makeOpenAI(apiKey: \"...\", model: .gpt4point1)`
3. Recomendado:
   - Guardar API keys en Keychain.
   - Confirmación manual de calorías estimadas por IA antes de guardar.

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

1. Crear target iOS App y target Watch App en Xcode.
2. Conectar `DashboardView` como pantalla inicial.
3. Guardar ingestas reales y reemplazar `MockIntakeProvider`.
4. Programar recordatorios de agua/comidas con `UserNotifications`.
