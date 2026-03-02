import "dotenv/config";
import express from "express";
import jwt from "jsonwebtoken";

const app = express();
app.use(express.json({ limit: "20mb" }));

const config = {
  port: Number(process.env.PORT || 8080),
  jwtSecret: process.env.SESSION_JWT_SECRET || "",
  primaryAIProvider: (process.env.PRIMARY_AI_PROVIDER || "openai").toLowerCase(),
  fallbackAIProvider: (process.env.FALLBACK_AI_PROVIDER || "gemini").toLowerCase(),
  googleClientID: process.env.GOOGLE_CLIENT_ID || "",
  googleClientSecret: process.env.GOOGLE_CLIENT_SECRET || "",
  googleRedirectURI: process.env.GOOGLE_REDIRECT_URI || "",
  openAIKey: process.env.OPENAI_API_KEY || "",
  openAIModel: process.env.OPENAI_MODEL || "gpt-4.1-mini",
  geminiKey: process.env.GEMINI_API_KEY || "",
  geminiModel: process.env.GEMINI_MODEL || "gemini-2.5-flash",
  mockAI: String(process.env.MOCK_AI || "false").toLowerCase() === "true"
};

if (!config.jwtSecret) {
  console.warn("[WARN] SESSION_JWT_SECRET is empty. Set it in backend/.env for production.");
}

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "comesano-backend" });
});

app.get("/auth/google/start", (req, res) => {
  if (!config.googleClientID || !config.googleRedirectURI) {
    return res.status(500).json({ error: "Missing Google OAuth backend config." });
  }

  const redirectURI = String(req.query.redirect_uri || "comesano://auth/callback");
  const state = jwt.sign(
    { redirectURI, typ: "google_oauth_state" },
    config.jwtSecret,
    { expiresIn: "10m" }
  );

  const googleURL = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  googleURL.searchParams.set("client_id", config.googleClientID);
  googleURL.searchParams.set("redirect_uri", config.googleRedirectURI);
  googleURL.searchParams.set("response_type", "code");
  googleURL.searchParams.set("scope", "openid email profile");
  googleURL.searchParams.set("state", state);
  googleURL.searchParams.set("prompt", "select_account");

  return res.redirect(googleURL.toString());
});

app.get("/auth/google/callback", async (req, res) => {
  try {
    const code = String(req.query.code || "");
    const state = String(req.query.state || "");

    if (!code || !state) {
      return res.status(400).json({ error: "Missing code/state." });
    }

    const decodedState = jwt.verify(state, config.jwtSecret);
    if (!decodedState || decodedState.typ !== "google_oauth_state") {
      return res.status(400).json({ error: "Invalid OAuth state." });
    }

    const tokenPayload = new URLSearchParams({
      code,
      client_id: config.googleClientID,
      client_secret: config.googleClientSecret,
      redirect_uri: config.googleRedirectURI,
      grant_type: "authorization_code"
    });

    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: tokenPayload.toString()
    });

    if (!tokenResponse.ok) {
      const detail = await tokenResponse.text();
      return res.status(401).json({ error: `Google token exchange failed: ${detail}` });
    }

    const tokenJSON = await tokenResponse.json();
    const accessToken = tokenJSON.access_token;
    if (!accessToken) {
      return res.status(401).json({ error: "No Google access token returned." });
    }

    const profileResponse = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
      headers: { Authorization: `Bearer ${accessToken}` }
    });

    if (!profileResponse.ok) {
      const detail = await profileResponse.text();
      return res.status(401).json({ error: `Google userinfo failed: ${detail}` });
    }

    const profile = await profileResponse.json();
    const sessionToken = jwt.sign(
      {
        sub: profile.sub,
        email: profile.email,
        name: profile.name,
        picture: profile.picture,
        provider: "google"
      },
      config.jwtSecret,
      { expiresIn: "30d" }
    );

    const appRedirect = new URL(decodedState.redirectURI);
    appRedirect.searchParams.set("token", sessionToken);

    return res.redirect(appRedirect.toString());
  } catch (error) {
    return res.status(401).json({ error: "Google auth callback failed.", detail: error.message });
  }
});

function requireSession(req, res, next) {
  const header = String(req.headers.authorization || "");
  if (!header.toLowerCase().startsWith("bearer ")) {
    return res.status(401).json({ error: "Missing bearer token." });
  }

  const token = header.slice(7).trim();
  try {
    req.session = jwt.verify(token, config.jwtSecret);
    return next();
  } catch {
    return res.status(401).json({ error: "Invalid session token." });
  }
}

app.post("/v1/ai/nutrition/analyze", requireSession, async (req, res) => {
  try {
    const prompt = String(req.body?.prompt || "");
    const imagesBase64 = Array.isArray(req.body?.imagesBase64) ? req.body.imagesBase64 : [];
    const text = config.mockAI
      ? mockText("nutrition")
      : await generateAIText({ prompt, imagesBase64 });

    return res.json({ text });
  } catch (error) {
    return res.status(502).json({ error: error.message || "AI request failed." });
  }
});

app.post("/v1/ai/suggestions", requireSession, async (req, res) => {
  try {
    const prompt = String(req.body?.prompt || "");
    const text = config.mockAI
      ? "Hoy prioriza proteína magra y verduras en la siguiente comida para cerrar mejor tus macros."
      : await generateAIText({ prompt, imagesBase64: [] });

    return res.json({ text });
  } catch (error) {
    return res.status(502).json({ error: error.message || "AI request failed." });
  }
});

app.post("/v1/ai/daily-plan", requireSession, proxyPrompt("dailyPlan"));
app.post("/v1/ai/weekly-plan", requireSession, proxyPrompt("weeklyPlan"));
app.post("/v1/ai/weekly-shopping", requireSession, proxyPrompt("weeklyShopping"));

function proxyPrompt(kind) {
  return async (req, res) => {
    try {
      const prompt = String(req.body?.prompt || "");
      const text = config.mockAI
        ? mockText(kind)
        : await generateAIText({ prompt, imagesBase64: [] });

      return res.json({ text });
    } catch (error) {
      return res.status(502).json({ error: error.message || "AI request failed." });
    }
  };
}

async function generateAIText({ prompt, imagesBase64 }) {
  const providers = [config.primaryAIProvider, config.fallbackAIProvider].filter(Boolean);
  const uniqueProviders = [...new Set(providers)];

  let lastError = "";
  for (const provider of uniqueProviders) {
    try {
      if (provider === "openai") {
        return await callOpenAI({ prompt, imagesBase64 });
      }
      if (provider === "gemini") {
        return await callGemini({ prompt, imagesBase64 });
      }
    } catch (error) {
      lastError = error.message || String(error);
    }
  }

  throw new Error(lastError || "No AI provider available.");
}

async function callOpenAI({ prompt, imagesBase64 }) {
  const key = config.openAIKey.trim();
  if (!key) throw new Error("OPENAI_API_KEY is missing.");

  const content = [{ type: "input_text", text: prompt }];
  for (const image of imagesBase64) {
    content.push({ type: "input_image", image_url: `data:image/jpeg;base64,${image}` });
  }

  const body = {
    model: config.openAIModel,
    input: [
      {
        role: "user",
        content
      }
    ]
  };

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`
    },
    body: JSON.stringify(body)
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(`OpenAI ${response.status}: ${JSON.stringify(data)}`);
  }

  const outputText = data.output_text || data?.output?.[0]?.content?.[0]?.text;
  const text = String(outputText || "").trim();
  if (!text) throw new Error("OpenAI returned empty content.");
  return text;
}

async function callGemini({ prompt, imagesBase64 }) {
  const key = config.geminiKey.trim();
  if (!key) throw new Error("GEMINI_API_KEY is missing.");

  const parts = [{ text: prompt }];
  for (const image of imagesBase64) {
    parts.push({
      inlineData: {
        mimeType: "image/jpeg",
        data: image
      }
    });
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(config.geminiModel)}:generateContent?key=${encodeURIComponent(key)}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ contents: [{ parts }] })
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(`Gemini ${response.status}: ${JSON.stringify(data)}`);
  }

  const text = String(data?.candidates?.[0]?.content?.parts?.[0]?.text || "").trim();
  if (!text) throw new Error("Gemini returned empty content.");
  return text;
}

function mockText(kind) {
  if (kind === "nutrition") {
    return JSON.stringify({
      foodItems: [
        {
          name: "Pollo a la plancha",
          servingDescription: "150g",
          nutrition: { calories: 260, proteinGrams: 35, carbsGrams: 0, fatGrams: 10 },
          source: "ai"
        }
      ],
      shoppingList: [
        { name: "Brócoli", category: "Verduras", quantity: 1, unit: "pieza" }
      ],
      notes: "Estimación inicial. Confirma porciones en app."
    });
  }

  if (kind === "dailyPlan") {
    return JSON.stringify({
      caloriasDiarias: 2100,
      proteinaGramos: 150,
      carbohidratosGramos: 220,
      grasasGramos: 65,
      desayuno: { titulo: "Avena con yogurt", calorias: 450, descripcion: "Avena, yogurt griego, fruta", horaSugerida: "08:00" },
      colacion1: { titulo: "Fruta y nueces", calorias: 220, descripcion: "Manzana y nuez", horaSugerida: "11:00" },
      comida: { titulo: "Pollo con arroz", calorias: 650, descripcion: "Pollo, arroz y ensalada", horaSugerida: "14:30" },
      colacion2: { titulo: "Sándwich integral", calorias: 260, descripcion: "Pavo y aguacate", horaSugerida: "17:30" },
      cena: { titulo: "Salmón con verduras", calorias: 520, descripcion: "Salmón y verduras asadas", horaSugerida: "20:30" },
      createdAt: new Date().toISOString(),
      source: "backend"
    });
  }

  if (kind === "weeklyPlan") {
    const dias = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"].map((dia) => ({
      dia,
      desayuno: { titulo: "Huevos con tortilla", calorias: 420, descripcion: "2 huevos y 2 tortillas", horaSugerida: "08:00" },
      colacion1: { titulo: "Yogurt", calorias: 200, descripcion: "Yogurt natural", horaSugerida: "11:00" },
      comida: { titulo: "Carne con arroz", calorias: 700, descripcion: "Carne magra y arroz", horaSugerida: "14:00" },
      colacion2: { titulo: "Fruta", calorias: 180, descripcion: "Fruta de temporada", horaSugerida: "17:00" },
      cena: { titulo: "Atún con ensalada", calorias: 500, descripcion: "Atún, aguacate y verduras", horaSugerida: "20:00" },
      caloriasTotales: 2000
    }));

    return JSON.stringify({
      caloriasObjetivoDiarias: 2100,
      proteinaObjetivoGramos: 150,
      carbohidratosObjetivoGramos: 220,
      grasasObjetivoGramos: 65,
      dias,
      recomendaciones: "Prioriza hidratación y proteína en cada comida.",
      createdAt: new Date().toISOString(),
      source: "backend"
    });
  }

  if (kind === "weeklyShopping") {
    return JSON.stringify([
      { name: "Pechuga de pollo", category: "Proteínas", quantity: 2, unit: "kg" },
      { name: "Arroz", category: "Granos", quantity: 1, unit: "kg" },
      { name: "Espinaca", category: "Verduras", quantity: 3, unit: "bolsa" }
    ]);
  }

  return "Respuesta mock.";
}

app.listen(config.port, () => {
  console.log(`[comesano-backend] listening on http://localhost:${config.port}`);
});
