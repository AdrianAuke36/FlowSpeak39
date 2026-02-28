const args = process.argv.slice(2);

function argValue(name, fallback = "") {
  const idx = args.indexOf(`--${name}`);
  if (idx === -1) return fallback;
  return args[idx + 1] ?? fallback;
}

function hasFlag(name) {
  return args.includes(`--${name}`);
}

function safeJsonParse(text) {
  try {
    return JSON.parse(String(text || ""));
  } catch {
    return null;
  }
}

function requireValue(label, value) {
  if (!String(value || "").trim()) {
    throw new Error(`Missing required value: ${label}`);
  }
}

async function request({ url, method = "GET", headers = {}, body }) {
  const response = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await response.text();
  return {
    status: response.status,
    headers: response.headers,
    text,
    json: safeJsonParse(text)
  };
}

function decodeJwtPayload(token) {
  const parts = String(token || "").split(".");
  if (parts.length < 2) return null;
  try {
    const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    return JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
  } catch {
    return null;
  }
}

async function main() {
  if (hasFlag("help")) {
    console.log([
      "Usage:",
      "  node scripts/supabase-auth-check.mjs --email you@example.com --password secret",
      "",
      "Env fallbacks:",
      "  SUPABASE_URL",
      "  SUPABASE_ANON_KEY",
      "  SUPABASE_EMAIL",
      "  SUPABASE_PASSWORD",
      "  FLOWSPEAK_BACKEND_URL (optional, defaults to http://127.0.0.1:3000)",
      "",
      "Flags:",
      "  --skip-backend    Only test Supabase login and print token metadata"
    ].join("\n"));
    return;
  }

  const supabaseURL = String(argValue("supabase-url", process.env.SUPABASE_URL || process.env.SUPABASE_PROJECT_URL || "")).trim().replace(/\/+$/, "");
  const anonKey = String(argValue("anon-key", process.env.SUPABASE_ANON_KEY || process.env.FLOWSPEAK_SUPABASE_ANON_KEY || "")).trim();
  const email = String(argValue("email", process.env.SUPABASE_EMAIL || "")).trim();
  const password = String(argValue("password", process.env.SUPABASE_PASSWORD || "")).trim();
  const backendURL = String(argValue("backend-url", process.env.FLOWSPEAK_BACKEND_URL || "http://127.0.0.1:3000")).trim().replace(/\/+$/, "");
  const skipBackend = hasFlag("skip-backend");

  requireValue("SUPABASE_URL", supabaseURL);
  requireValue("SUPABASE_ANON_KEY", anonKey);
  requireValue("email", email);
  requireValue("password", password);

  const login = await request({
    url: `${supabaseURL}/auth/v1/token?grant_type=password`,
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`
    },
    body: { email, password }
  });

  if (login.status !== 200) {
    const parts = [];
    if (login.json?.error_code) parts.push(String(login.json.error_code));
    if (login.json?.msg) parts.push(String(login.json.msg));
    if (login.json?.message) parts.push(String(login.json.message));
    if (parts.length === 0) parts.push(login.text.slice(0, 500) || "Unknown Supabase auth error");
    throw new Error(`Supabase login failed (${login.status}): ${parts.join(" | ")}`);
  }

  const accessToken = String(login.json?.access_token || "").trim();
  requireValue("access_token", accessToken);

  const claims = decodeJwtPayload(accessToken) || {};
  const output = {
    supabase: {
      ok: true,
      project: supabaseURL,
      userId: String(login.json?.user?.id || claims.sub || ""),
      email: String(login.json?.user?.email || claims.email || email),
      audience: claims.aud || null,
      issuer: claims.iss || null,
      expiresAt: typeof login.json?.expires_at === "number"
        ? new Date(Number(login.json.expires_at) * 1000).toISOString()
        : null,
      tokenLength: accessToken.length
    }
  };

  if (!skipBackend) {
    const version = await request({
      url: `${backendURL}/version`,
      headers: {
        Authorization: `Bearer ${accessToken}`
      }
    });

    if (version.status !== 200) {
      throw new Error(`Backend token check failed (${version.status}): ${version.text.slice(0, 500)}`);
    }

    output.backend = {
      ok: true,
      url: backendURL,
      authRequired: Boolean(version.json?.authRequired),
      supabaseJwtEnabled: Boolean(version.json?.auth?.supabaseJwtEnabled),
      audiences: Array.isArray(version.json?.auth?.supabaseAudiences) ? version.json.auth.supabaseAudiences : [],
      issuer: version.json?.auth?.supabaseIssuer || null
    };
  } else {
    output.backend = {
      skipped: true,
      note: "Use --backend-url or FLOWSPEAK_BACKEND_URL to verify backend accepts this token."
    };
  }

  console.log(JSON.stringify(output, null, 2));
}

main().catch((error) => {
  console.error("Supabase auth check failed:", error?.message || String(error));
  process.exit(1);
});
