# ComeSano Backend (Auth + AI Proxy)

Backend mínimo para:
- Login Google desde servidor (`/auth/google/start` -> `/auth/google/callback`)
- Emitir token de sesión para app iOS
- Proxyear llamadas de IA para que el usuario NO tenga que pegar API keys

## Requisitos
- Node.js 20+

## Setup
1. Instala dependencias:
   ```bash
   cd backend
   npm install
   ```
2. Crea `.env` desde `.env.example` y completa variables.
3. Ejecuta:
   ```bash
   npm run dev
   ```

## Endpoints
- `GET /health`
- `GET /auth/google/start?redirect_uri=comesano://auth/callback`
- `GET /auth/google/callback`
- `POST /v1/ai/nutrition/analyze`
- `POST /v1/ai/suggestions`
- `POST /v1/ai/daily-plan`
- `POST /v1/ai/weekly-plan`
- `POST /v1/ai/weekly-shopping`

Todos los endpoints `/v1/ai/*` requieren `Authorization: Bearer <session_token>`.

## Notas
- `MOCK_AI=true` permite pruebas sin consumir OpenAI/Gemini.
- En producción agrega rate limiting, control de costos por usuario y auditoría de uso.
