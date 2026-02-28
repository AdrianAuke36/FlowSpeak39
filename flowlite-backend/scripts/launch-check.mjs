const args = process.argv.slice(2);

function argValue(name, fallback = "") {
  const idx = args.indexOf(`--${name}`);
  if (idx === -1) return fallback;
  return args[idx + 1] ?? fallback;
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

async function request({ baseURL, path, method = "GET", body, token, headers = {} }) {
  const url = `${baseURL}${path}`;
  const startedAt = Date.now();
  const response = await fetch(url, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers
    },
    body: body ? JSON.stringify(body) : undefined
  });
  const durationMs = Date.now() - startedAt;
  const text = await response.text();
  const json = safeJsonParse(text);
  return { url, status: response.status, headers: response.headers, text, json, durationMs };
}

function assertStatus(result, expected, label) {
  if (!expected.includes(result.status)) {
    throw new Error(`${label} expected ${expected.join(" or ")}, got ${result.status}. Body: ${result.text.slice(0, 500)}`);
  }
}

function assertTruthy(value, message) {
  if (!value) throw new Error(message);
}

async function main() {
  const baseURL = String(argValue("url", process.env.FLOWSPEAK_BACKEND_URL || "")).trim().replace(/\/+$/, "");
  const token = String(argValue("token", process.env.FLOWSPEAK_BENCH_TOKEN || process.env.FLOWSPEAK_API_TOKEN || "")).trim();
  const origin = String(argValue("origin", process.env.FLOWSPEAK_ALLOWED_ORIGIN || "")).trim();
  const timeoutMs = Number(argValue("timeout", process.env.FLOWSPEAK_LAUNCH_TIMEOUT_MS || "2500"));

  requireValue("--url", baseURL);

  const output = {
    baseURL,
    checks: []
  };

  const health = await request({ baseURL, path: "/health" });
  assertStatus(health, [200], "health");
  assertTruthy(health.json?.ok === true, "health response missing ok=true");
  output.checks.push({ name: "health", status: health.status, durationMs: health.durationMs });

  const ready = await request({ baseURL, path: "/ready" });
  if (ready.status !== 200) {
    throw new Error(`ready expected 200, got ${ready.status}. Body: ${ready.text.slice(0, 500)}`);
  }
  assertTruthy(ready.json?.ok === true, `ready failed: ${JSON.stringify(ready.json?.issues || [])}`);
  output.checks.push({ name: "ready", status: ready.status, durationMs: ready.durationMs });

  if (token) {
    const version = await request({ baseURL, path: "/version", token });
    assertStatus(version, [200], "version(auth)");
    output.checks.push({ name: "version(auth)", status: version.status, durationMs: version.durationMs });

    const metrics = await request({ baseURL, path: "/metrics", token });
    assertStatus(metrics, [200], "metrics(auth)");
    output.checks.push({ name: "metrics(auth)", status: metrics.status, durationMs: metrics.durationMs });

    const polish = await request({
      baseURL,
      path: "/polish",
      method: "POST",
      token,
      body: {
        text: "hei kan vi ta et kort møte i morgen klokken 10 nei jeg mener klokken 11",
        mode: "generic",
        style: "clean",
        targetLanguage: "nb-NO"
      }
    });
    assertStatus(polish, [200], "polish(auth)");
    assertTruthy(typeof polish.json?.text === "string" && polish.json.text.trim().length > 0, "polish returned empty text");
    if (Number.isFinite(timeoutMs) && timeoutMs > 0) {
      const totalMs = Number(polish.json?.timings?.totalMs || 0);
      if (totalMs > timeoutMs) {
        throw new Error(`polish timing too high: ${totalMs}ms > ${timeoutMs}ms`);
      }
    }
    output.checks.push({
      name: "polish(auth)",
      status: polish.status,
      durationMs: polish.durationMs,
      totalMs: Number(polish.json?.timings?.totalMs || 0),
      modelMs: Number(polish.json?.timings?.modelMs || 0),
      localFastpath: Boolean(polish.json?.localFastpath)
    });

    const rewrite = await request({
      baseURL,
      path: "/rewrite",
      method: "POST",
      token,
      body: {
        text: "Dette er en lang tekst som kan være kortere.",
        instruction: "Gjør teksten kortere.",
        targetLanguage: "nb-NO",
        style: "clean"
      }
    });
    assertStatus(rewrite, [200], "rewrite(auth)");
    assertTruthy(typeof rewrite.json?.text === "string" && rewrite.json.text.trim().length > 0, "rewrite returned empty text");
    output.checks.push({
      name: "rewrite(auth)",
      status: rewrite.status,
      durationMs: rewrite.durationMs,
      totalMs: Number(rewrite.json?.timings?.totalMs || 0),
      modelMs: Number(rewrite.json?.timings?.modelMs || 0)
    });
  } else {
    output.checks.push({
      name: "auth checks",
      skipped: true,
      note: "Pass --token or FLOWSPEAK_BENCH_TOKEN to validate /version, /metrics, /polish, /rewrite."
    });
  }

  if (origin) {
    const preflight = await request({
      baseURL,
      path: "/polish",
      method: "OPTIONS",
      headers: {
        Origin: origin,
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "content-type,authorization"
      }
    });
    assertStatus(preflight, [204], "cors preflight");
    const allowOrigin = String(preflight.headers.get("access-control-allow-origin") || "");
    if (allowOrigin !== origin && allowOrigin !== "*") {
      throw new Error(`cors mismatch: expected '${origin}' or '*', got '${allowOrigin || "<empty>"}'`);
    }
    output.checks.push({
      name: "cors preflight",
      status: preflight.status,
      durationMs: preflight.durationMs,
      allowOrigin
    });
  }

  output.ok = true;
  console.log(JSON.stringify(output, null, 2));
}

main().catch((error) => {
  console.error("Launch check failed:", error?.message || String(error));
  process.exit(1);
});
