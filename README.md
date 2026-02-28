# ComeSano iOS

Base de la Semana 1 para una app de nutrición conectada con Apple Health.

## Incluye

- Modelo de usuario y meta calórica diaria.
- Cálculo de balance calórico diario y progreso semanal.
- Proveedor HealthKit para calorías activas y basales.
- Dashboard SwiftUI mínimo para visualizar progreso.
- Persistencia local con CoreData.
- Capa de IA multimodal desacoplada (OpenAI / Gemini).
- Tests unitarios del motor de cálculo.

## Estructura

- `Sources/ComeSanoCore`: dominio y reglas de cálculo.
- `Sources/ComeSanoHealthKit`: integración con HealthKit.
- `Sources/ComeSanoUI`: `DashboardView` y `DashboardViewModel`.
- `Sources/ComeSanoPersistence`: `NSPersistentContainer` y stores para alimentos/alacena/lista.
- `Sources/ComeSanoAI`: clientes multimodales para analizar foto de comida/alacena.
- `Tests/ComeSanoCoreTests`: pruebas de negocio.

## Configuración rápida

1. Core Data local:
   - Inicializa `PersistenceController()` para almacenamiento local en el dispositivo.
2. IA:
   - OpenAI: `NutritionAIClientFactory.make(provider: .openAI(apiKey: \"...\"))`
   - Gemini: `NutritionAIClientFactory.make(provider: .gemini(apiKey: \"...\"))`
3. Recomendado:
   - Guardar API keys en Keychain.
   - Confirmación manual de calorías estimadas por IA antes de guardar.

## Nota futura

Cuando tengas Apple Developer habilitado, se puede migrar este contenedor a `NSPersistentCloudKitContainer` para sincronización por iCloud sin cambiar la capa de dominio.

## Siguiente fase sugerida

1. Crear target iOS App y target Watch App en Xcode.
2. Conectar `DashboardView` como pantalla inicial.
3. Guardar ingestas reales y reemplazar `MockIntakeProvider`.
4. Programar recordatorios de agua/comidas con `UserNotifications`.
