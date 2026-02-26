const args = process.argv.slice(2);

function argValue(name, fallback = "") {
  const idx = args.indexOf(`--${name}`);
  if (idx === -1) return fallback;
  return args[idx + 1] ?? fallback;
}

function toNumber(value, fallback) {
  const num = Number(value);
  return Number.isFinite(num) ? num : fallback;
}

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.max(0, Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

function summarize(values) {
  if (!values.length) {
    return { count: 0, avg: 0, p50: 0, p90: 0, p95: 0, p99: 0, min: 0, max: 0 };
  }
  const sum = values.reduce((acc, value) => acc + value, 0);
  return {
    count: values.length,
    avg: Math.round(sum / values.length),
    p50: Math.round(percentile(values, 50)),
    p90: Math.round(percentile(values, 90)),
    p95: Math.round(percentile(values, 95)),
    p99: Math.round(percentile(values, 99)),
    min: Math.round(Math.min(...values)),
    max: Math.round(Math.max(...values))
  };
}

const baseURL = String(argValue("url", process.env.FLOWSPEAK_BACKEND_URL || "http://127.0.0.1:3000")).replace(/\/+$/, "");
const endpoint = `${baseURL}/polish`;
const token = argValue("token", process.env.FLOWSPEAK_BENCH_TOKEN || process.env.FLOWSPEAK_API_TOKEN || "");
const totalRequests = Math.max(1, Math.floor(toNumber(argValue("n", "40"), 40)));
const concurrency = Math.max(1, Math.floor(toNumber(argValue("c", "8"), 8)));
const budgetMs = Math.max(1, Math.floor(toNumber(argValue("budget", "700"), 700)));
const warmupRequests = Math.max(0, Math.floor(toNumber(argValue("warmup", "0"), 0)));
const mode = argValue("mode", "email_body");
const targetLanguage = argValue("lang", "nb-NO");
const style = argValue("style", "clean");
const cacheBypass = String(argValue("cache-bypass", "false")).toLowerCase() === "true";
const uniqueText = String(argValue("unique-text", "false")).toLowerCase() === "true";
const text = argValue(
  "text",
  "hei patrick skal vi spise middag klokken 7 nei jeg mener klokken 8 hilsen adrian"
);

const results = [];
let counter = 0;

async function runOne(index) {
  const requestText = uniqueText ? `${text} [bench-${index}]` : text;
  const body = {
    text: requestText,
    mode,
    style,
    targetLanguage
  };
  const startedAt = Date.now();
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(cacheBypass ? { "X-Fastpath-Bypass": "1" } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {})
      },
      body: JSON.stringify(body)
    });

    const endpointMs = Date.now() - startedAt;
    let json = null;
    try {
      json = await response.json();
    } catch {
      json = null;
    }

    results[index] = {
      ok: response.ok,
      status: response.status,
      endpointMs,
      modelMs: Number(json?.timings?.modelMs || 0),
      fallback: Boolean(json?.fallback),
      cache: String(response.headers.get("x-fastpath-cache") || "MISS").toUpperCase(),
      error: json?.error || ""
    };
  } catch (error) {
    const endpointMs = Date.now() - startedAt;
    results[index] = {
      ok: false,
      status: 0,
      endpointMs,
      modelMs: 0,
      fallback: false,
      cache: "MISS",
      error: error?.message || "request failed"
    };
  }
}

async function worker() {
  while (true) {
    const index = counter;
    counter += 1;
    if (index >= totalRequests) return;
    await runOne(index);
  }
}

for (let i = 0; i < warmupRequests; i += 1) {
  await runOne(-1 - i);
}

results.length = 0;
counter = 0;

const startedAt = Date.now();
await Promise.all(Array.from({ length: Math.min(concurrency, totalRequests) }, () => worker()));
const totalMs = Date.now() - startedAt;

const endpointValues = results.map((r) => r.endpointMs).filter((v) => Number.isFinite(v));
const modelValues = results.map((r) => r.modelMs).filter((v) => Number.isFinite(v) && v > 0);
const endpointStats = summarize(endpointValues);
const modelStats = summarize(modelValues);
const successCount = results.filter((r) => r.ok).length;
const fallbackCount = results.filter((r) => r.fallback).length;
const cacheHitCount = results.filter((r) => r.cache === "HIT").length;
const failures = results.filter((r) => !r.ok);

const output = {
  endpoint,
  totalRequests,
  concurrency,
  warmupRequests,
  cacheBypass,
  uniqueText,
  wallClockMs: totalMs,
  throughputRps: Number((totalRequests / Math.max(0.001, totalMs / 1000)).toFixed(2)),
  successCount,
  failureCount: totalRequests - successCount,
  fallbackRate: Number((fallbackCount / Math.max(1, totalRequests)).toFixed(4)),
  cacheHitRate: Number((cacheHitCount / Math.max(1, totalRequests)).toFixed(4)),
  endpointMs: endpointStats,
  modelMs: modelStats,
  failures: failures.slice(0, 5).map((f) => ({ status: f.status, error: f.error }))
};

console.log(JSON.stringify(output, null, 2));

if (endpointStats.p95 > budgetMs) {
  console.error(`P95 ${endpointStats.p95}ms is above budget ${budgetMs}ms`);
  process.exit(2);
}
