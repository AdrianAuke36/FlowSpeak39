import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const host = "127.0.0.1";
const port = Number(process.env.CI_SMOKE_PORT || 3199);
const baseURL = `http://${host}:${port}`;

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForHealth(maxAttempts = 40) {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      const response = await fetch(`${baseURL}/health`);
      if (response.ok) {
        return;
      }
    } catch {
      // retry
    }
    await wait(250);
  }
  throw new Error("Backend did not become healthy in time.");
}

async function assertJson(path, { method = "GET", expectedStatus, body = null, validate }) {
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: {
      "Content-Type": "application/json"
    },
    body: body ? JSON.stringify(body) : undefined
  });
  const payload = await response.json();
  if (response.status !== expectedStatus) {
    throw new Error(`Expected ${path} status ${expectedStatus}, got ${response.status}: ${JSON.stringify(payload)}`);
  }
  if (validate) {
    validate(payload);
  }
}

async function run() {
  const child = spawn("node", ["server.js"], {
    cwd: path.resolve(__dirname, ".."),
    env: {
      ...process.env,
      HOST: host,
      PORT: String(port),
      REQUIRE_AUTH: "false",
      FLOWSPEAK_API_TOKENS: "",
      FLOWSPEAK_API_TOKEN: "",
      FLOWSPEAK_JWT_SECRET: "",
      FLOWSPEAK_JWT_SECRETS: "",
      SUPABASE_URL: "",
      SUPABASE_PROJECT_URL: "",
      SUPABASE_JWKS_URL: "",
      OPENAI_API_KEY: "",
      ALLOWED_ORIGINS: ""
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  let stderr = "";
  child.stderr.on("data", (chunk) => {
    stderr += String(chunk);
  });

  try {
    await waitForHealth();

    await assertJson("/health", {
      expectedStatus: 200,
      validate: (payload) => {
        if (payload.ok !== true) throw new Error("/health payload missing ok=true");
      }
    });

    await assertJson("/ready", {
      expectedStatus: 503,
      validate: (payload) => {
        if (!Array.isArray(payload.issues) || payload.issues.length === 0) {
          throw new Error("/ready should report issues when OPENAI_API_KEY is missing.");
        }
      }
    });

    await assertJson("/rewrite", {
      method: "POST",
      expectedStatus: 400,
      body: {},
      validate: (payload) => {
        if (!String(payload.error || "").toLowerCase().includes("missing text")) {
          throw new Error("Expected /rewrite missing text validation error.");
        }
      }
    });

    await assertJson("/polish", {
      method: "POST",
      expectedStatus: 200,
      body: {
        text: "hei der",
        mode: "generic",
        style: "clean",
        targetLanguage: "nb-NO"
      },
      validate: (payload) => {
        if (!payload.text || typeof payload.text !== "string") {
          throw new Error("Expected /polish to return text.");
        }
      }
    });

    console.log("Smoke test passed.");
  } finally {
    child.kill("SIGTERM");
    await wait(200);
    if (stderr.trim()) {
      process.stderr.write(stderr);
    }
  }
}

run().catch((error) => {
  console.error("Smoke test failed:", error.message);
  process.exit(1);
});
