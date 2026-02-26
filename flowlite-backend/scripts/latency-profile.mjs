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
const perScenarioRequests = Math.max(1, Math.floor(toNumber(argValue("n", "24"), 24)));
const concurrency = Math.max(1, Math.floor(toNumber(argValue("c", "6"), 6)));
const budgetMs = Math.max(1, Math.floor(toNumber(argValue("budget", "700"), 700)));
const cacheBypass = String(argValue("cache-bypass", "true")).toLowerCase() === "true";
const strictScenario = String(argValue("strict-scenario", "false")).toLowerCase() === "true";

const scenarios = [
  {
    name: "email_nb_self_correct",
    body: {
      text: "hei patrick skal vi spise middag klokken 7 nei jeg mener klokken 8 hilsen adrian",
      mode: "email_body",
      style: "clean",
      targetLanguage: "nb-NO"
    }
  },
  {
    name: "generic_nb_clean",
    body: {
      text: "jeg har lyst på en lamborghini men skriver fort uten tegnsetting ehm",
      mode: "generic",
      style: "clean",
      targetLanguage: "nb-NO"
    }
  },
  {
    name: "translate_en_clean",
    body: {
      text: "hei sebastian kan du komme på møtet i morgen klokken åtte hilsen adrian",
      mode: "generic",
      style: "clean",
      targetLanguage: "en-US"
    }
  }
];

async function runScenario(scenario) {
  const results = [];
  let counter = 0;

  async function runOne(index) {
    const payload = {
      ...scenario.body,
      text: scenario.body.text
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
        body: JSON.stringify(payload)
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
      if (index >= perScenarioRequests) return;
      await runOne(index);
    }
  }

  const startedAt = Date.now();
  await Promise.all(
    Array.from({ length: Math.min(concurrency, perScenarioRequests) }, () => worker())
  );
  const wallClockMs = Date.now() - startedAt;
  const endpointValues = results.map((r) => r.endpointMs).filter((v) => Number.isFinite(v));
  const modelValues = results.map((r) => r.modelMs).filter((v) => Number.isFinite(v) && v > 0);
  const successCount = results.filter((r) => r.ok).length;
  const fallbackCount = results.filter((r) => r.fallback).length;
  const failures = results.filter((r) => !r.ok);

  return {
    name: scenario.name,
    requests: perScenarioRequests,
    wallClockMs,
    throughputRps: Number((perScenarioRequests / Math.max(0.001, wallClockMs / 1000)).toFixed(2)),
    successCount,
    failureCount: perScenarioRequests - successCount,
    fallbackRate: Number((fallbackCount / Math.max(1, perScenarioRequests)).toFixed(4)),
    endpointMs: summarize(endpointValues),
    modelMs: summarize(modelValues),
    failures: failures.slice(0, 5).map((f) => ({ status: f.status, error: f.error })),
    _endpointValues: endpointValues,
    _modelValues: modelValues
  };
}

const startedAt = Date.now();
const scenarioResults = [];
for (const scenario of scenarios) {
  const result = await runScenario(scenario);
  scenarioResults.push(result);
}
const totalMs = Date.now() - startedAt;

const allEndpoint = scenarioResults.flatMap((s) => s._endpointValues);
const allModel = scenarioResults.flatMap((s) => s._modelValues);

const overall = {
  endpointMs: summarize(allEndpoint),
  modelMs: summarize(allModel),
  wallClockMs: totalMs,
  totalRequests: scenarioResults.reduce((acc, s) => acc + s.requests, 0),
  totalFailures: scenarioResults.reduce((acc, s) => acc + s.failureCount, 0),
  totalFallbackRate: Number(
    (
      scenarioResults.reduce((acc, s) => acc + s.fallbackRate * s.requests, 0)
      / Math.max(1, scenarioResults.reduce((acc, s) => acc + s.requests, 0))
    ).toFixed(4)
  )
};

const output = {
  endpoint,
  cacheBypass,
  perScenarioRequests,
  concurrency,
  budgetMs,
  overall,
  scenarios: scenarioResults.map((scenario) => ({
    name: scenario.name,
    requests: scenario.requests,
    wallClockMs: scenario.wallClockMs,
    throughputRps: scenario.throughputRps,
    successCount: scenario.successCount,
    failureCount: scenario.failureCount,
    fallbackRate: scenario.fallbackRate,
    endpointMs: scenario.endpointMs,
    modelMs: scenario.modelMs,
    failures: scenario.failures
  }))
};

console.log(JSON.stringify(output, null, 2));

const scenarioBudgetMiss = scenarioResults.filter((s) => s.endpointMs.p95 > budgetMs).map((s) => `${s.name}:${s.endpointMs.p95}`);
if (strictScenario && scenarioBudgetMiss.length > 0) {
  console.error(`Scenario budget miss (> ${budgetMs}ms): ${scenarioBudgetMiss.join(", ")}`);
  process.exit(2);
}
if (overall.endpointMs.p95 > budgetMs) {
  console.error(`Overall P95 ${overall.endpointMs.p95}ms is above budget ${budgetMs}ms`);
  process.exit(2);
}
