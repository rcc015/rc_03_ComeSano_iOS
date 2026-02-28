# ComeSano iOS

Base de la Semana 1 para una app de nutrición conectada con Apple Health.

## Incluye

- Modelo de usuario y meta calórica diaria.
- Cálculo de balance calórico diario y progreso semanal.
- Proveedor HealthKit para calorías activas y basales.
- Dashboard SwiftUI mínimo para visualizar progreso.
- Tests unitarios del motor de cálculo.

## Estructura

- `Sources/ComeSanoCore`: dominio y reglas de cálculo.
- `Sources/ComeSanoHealthKit`: integración con HealthKit.
- `Sources/ComeSanoUI`: `DashboardView` y `DashboardViewModel`.
- `Tests/ComeSanoCoreTests`: pruebas de negocio.

## Siguiente fase sugerida

1. Crear target iOS App y target Watch App en Xcode.
2. Conectar `DashboardView` como pantalla inicial.
3. Guardar ingestas reales en SwiftData y reemplazar `MockIntakeProvider`.
4. Programar recordatorios de agua/comidas con `UserNotifications`.
