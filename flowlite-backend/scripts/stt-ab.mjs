import fs from "node:fs/promises";
import path from "node:path";

const args = process.argv.slice(2);

function argValue(name, fallback = "") {
  const index = args.indexOf(`--${name}`);
  if (index === -1) return fallback;
  return args[index + 1] ?? fallback;
}

function hasFlag(name) {
  return args.includes(`--${name}`);
}

function toNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.max(0, Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

function summarizeNumbers(values) {
  if (!values.length) {
    return { count: 0, avg: 0, p50: 0, p90: 0, p95: 0, min: 0, max: 0 };
  }
  const sum = values.reduce((acc, value) => acc + value, 0);
  return {
    count: values.length,
    avg: Number((sum / values.length).toFixed(2)),
    p50: Number(percentile(values, 50).toFixed(2)),
    p90: Number(percentile(values, 90).toFixed(2)),
    p95: Number(percentile(values, 95).toFixed(2)),
    min: Number(Math.min(...values).toFixed(2)),
    max: Number(Math.max(...values).toFixed(2))
  };
}

function cleanBase64(raw) {
  const value = String(raw || "").trim();
  if (!value) return "";
  const comma = value.indexOf(",");
  const data = comma >= 0 ? value.slice(comma + 1) : value;
  return data.replace(/\s+/g, "");
}

function inferMimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === ".wav") return "audio/wav";
  if (ext === ".mp3") return "audio/mpeg";
  if (ext === ".m4a") return "audio/mp4";
  if (ext === ".mp4") return "audio/mp4";
  if (ext === ".webm") return "audio/webm";
  if (ext === ".ogg" || ext === ".oga") return "audio/ogg";
  if (ext === ".flac") return "audio/flac";
  return "application/octet-stream";
}

function normalizeLanguageHint(raw) {
  const value = String(raw || "").trim().toLowerCase();
  if (!value) return "";

  const map = new Map([
    ["nb", "no"],
    ["nb-no", "no"],
    ["no-nb", "no"],
    ["nn-no", "nn"],
    ["en-us", "en"],
    ["en-gb", "en"],
    ["pt-br", "pt"],
    ["pt-pt", "pt"],
    ["zh-cn", "zh"],
    ["zh-tw", "zh"]
  ]);
  return map.get(value) || value;
}

function normalizeWords(text) {
  return String(text || "")
    .toLowerCase()
    .replace(/[^a-z0-9æøåäöüßçñ'’]+/gi, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

function levenshteinDistance(a, b) {
  const rows = a.length + 1;
  const cols = b.length + 1;
  const dp = Array.from({ length: rows }, () => Array(cols).fill(0));

  for (let i = 0; i < rows; i += 1) dp[i][0] = i;
  for (let j = 0; j < cols; j += 1) dp[0][j] = j;

  for (let i = 1; i < rows; i += 1) {
    for (let j = 1; j < cols; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost
      );
    }
  }
  return dp[rows - 1][cols - 1];
}

function wordErrorRate(reference, hypothesis) {
  const refWords = normalizeWords(reference);
  const hypWords = normalizeWords(hypothesis);
  if (!refWords.length) {
    return {
      refWordCount: 0,
      hypWordCount: hypWords.length,
      edits: hypWords.length,
      wer: hypWords.length > 0 ? 1 : 0
    };
  }
  const edits = levenshteinDistance(refWords, hypWords);
  return {
    refWordCount: refWords.length,
    hypWordCount: hypWords.length,
    edits,
    wer: edits / refWords.length
  };
}

function printHelp() {
  const help = `
Usage:
  node scripts/stt-ab.mjs --file /abs/path/audio.m4a --api-key <GROQ_API_KEY>

Options:
  --file <path>                 Required audio file path.
  --api-key <key>               Groq API key (or set GROQ_API_KEY).
  --base-url <url>              Default: https://api.groq.com/openai/v1
  --models <csv>                Default: whisper-large-v3-turbo,whisper-large-v3
  --runs <n>                    Runs per model. Default: 3
  --timeout-ms <n>              Per request timeout. Default: 60000
  --language <code>             Optional language hint, e.g. nb or en.
  --prompt <text>               Optional prompt for STT.
  --temperature <n>             Default: 0
  --response-format <format>    verbose_json | json | text (default: verbose_json)
  --reference-text <text>       Optional ground truth for WER.
  --reference-file <path>       Optional text file for WER.
  --out <path>                  Optional output JSON path.

Example:
  GROQ_API_KEY=... npm run stt:ab -- --file /Users/me/Desktop/test.m4a --language nb --runs 5
`;
  console.log(help.trim());
}

async function transcribeOnce({
  baseURL,
  apiKey,
  model,
  bytes,
  filename,
  mimeType,
  responseFormat,
  language,
  prompt,
  temperature,
  timeoutMs
}) {
  const form = new FormData();
  form.append("model", model);
  form.append("temperature", String(temperature));
  form.append("response_format", responseFormat);
  form.append("file", new Blob([bytes], { type: mimeType }), filename);
  if (language) form.append("language", language);
  if (prompt) form.append("prompt", prompt);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const startedAt = Date.now();

  try {
    const response = await fetch(`${baseURL}/audio/transcriptions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
      signal: controller.signal
    });
    const latencyMs = Date.now() - startedAt;
    const text = await response.text();

    if (!response.ok) {
      let parsed = null;
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = null;
      }
      const detail = parsed?.error?.message || parsed?.message || text.slice(0, 500);
      throw new Error(`HTTP ${response.status}: ${detail}`);
    }

    let transcript = "";
    let payload = null;
    if (responseFormat === "text") {
      transcript = text.trim();
      payload = { text: transcript };
    } else {
      try {
        payload = JSON.parse(text);
      } catch {
        payload = null;
      }
      transcript = String(payload?.text || "").trim();
    }

    return { latencyMs, transcript, payload };
  } finally {
    clearTimeout(timeout);
  }
}

async function main() {
  if (hasFlag("help") || hasFlag("h")) {
    printHelp();
    return;
  }

  const filePath = String(argValue("file", "")).trim();
  const apiKey = String(argValue("api-key", process.env.GROQ_API_KEY || "")).trim();
  const baseURL = String(argValue("base-url", process.env.GROQ_API_BASE_URL || "https://api.groq.com/openai/v1"))
    .trim()
    .replace(/\/+$/, "");
  const defaultModels = process.env.GROQ_STT_MODEL
    ? `${process.env.GROQ_STT_MODEL},whisper-large-v3`
    : "whisper-large-v3-turbo,whisper-large-v3";
  const models = String(argValue("models", defaultModels))
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
  const runs = Math.max(1, Math.floor(toNumber(argValue("runs", "3"), 3)));
  const timeoutMs = Math.max(1000, Math.floor(toNumber(argValue("timeout-ms", "60000"), 60000)));
  const temperature = toNumber(argValue("temperature", process.env.GROQ_STT_TEMPERATURE || "0"), 0);
  const responseFormat = String(argValue("response-format", process.env.GROQ_STT_RESPONSE_FORMAT || "verbose_json")).trim() || "verbose_json";
  const languageRaw = String(argValue("language", "")).trim();
  const language = normalizeLanguageHint(languageRaw);
  const prompt = String(argValue("prompt", "")).trim();
  const outputPath = String(argValue("out", "")).trim();
  const referenceTextArg = String(argValue("reference-text", "")).trim();
  const referenceFile = String(argValue("reference-file", "")).trim();

  if (!filePath) throw new Error("Missing --file");
  if (!apiKey) throw new Error("Missing Groq API key. Pass --api-key or set GROQ_API_KEY.");
  if (!models.length) throw new Error("No models provided.");
  if (!globalThis.FormData || !globalThis.Blob || !globalThis.fetch) {
    throw new Error("This Node runtime is missing fetch/FormData/Blob support.");
  }

  const bytes = await fs.readFile(filePath);
  const filename = path.basename(filePath);
  const mimeType = inferMimeType(filePath);

  let referenceText = referenceTextArg;
  if (!referenceText && referenceFile) {
    referenceText = String(await fs.readFile(referenceFile, "utf8")).trim();
  }

  const output = {
    provider: "groq",
    endpoint: `${baseURL}/audio/transcriptions`,
    file: { path: filePath, name: filename, bytes: bytes.length, mimeType },
    config: {
      models,
      runs,
      timeoutMs,
      temperature,
      responseFormat,
      language: language || null,
      languageInput: languageRaw || null,
      prompt: prompt || null,
      hasReference: Boolean(referenceText)
    },
    models: [],
    recommendation: null
  };

  if (languageRaw && language && languageRaw.toLowerCase() !== language.toLowerCase()) {
    console.error(`Language hint normalized: '${languageRaw}' -> '${language}'`);
  }

  for (const model of models) {
    const runResults = [];
    for (let i = 0; i < runs; i += 1) {
      try {
        const result = await transcribeOnce({
          baseURL,
          apiKey,
          model,
          bytes,
          filename,
          mimeType,
          responseFormat,
          language,
          prompt,
          temperature,
          timeoutMs
        });
        const werResult = referenceText ? wordErrorRate(referenceText, result.transcript) : null;
        runResults.push({
          ok: true,
          run: i + 1,
          latencyMs: result.latencyMs,
          transcript: result.transcript,
          wer: werResult ? Number(werResult.wer.toFixed(4)) : null,
          edits: werResult?.edits ?? null,
          refWordCount: werResult?.refWordCount ?? null
        });
      } catch (error) {
        runResults.push({
          ok: false,
          run: i + 1,
          latencyMs: null,
          transcript: "",
          wer: null,
          edits: null,
          refWordCount: null,
          error: error?.message || String(error)
        });
      }
    }

    const successful = runResults.filter((entry) => entry.ok);
    const latencyValues = successful.map((entry) => entry.latencyMs);
    const werValues = successful.map((entry) => entry.wer).filter((value) => Number.isFinite(value));
    const summary = {
      successCount: successful.length,
      failureCount: runResults.length - successful.length,
      latencyMs: summarizeNumbers(latencyValues),
      wer: summarizeNumbers(werValues)
    };
    output.models.push({
      model,
      summary,
      sampleTranscript: successful[0]?.transcript || "",
      runs: runResults
    });
  }

  const candidates = output.models
    .filter((entry) => entry.summary.successCount > 0)
    .map((entry) => ({
      model: entry.model,
      avgLatency: entry.summary.latencyMs.avg,
      avgWer: entry.summary.wer.count > 0 ? entry.summary.wer.avg : null
    }));

  if (candidates.length > 0) {
    const sorted = [...candidates].sort((a, b) => {
      if (a.avgWer != null && b.avgWer != null && a.avgWer !== b.avgWer) return a.avgWer - b.avgWer;
      if (a.avgWer == null && b.avgWer != null) return 1;
      if (a.avgWer != null && b.avgWer == null) return -1;
      return a.avgLatency - b.avgLatency;
    });
    output.recommendation = sorted[0];
  }

  const json = JSON.stringify(output, null, 2);
  console.log(json);

  if (outputPath) {
    await fs.writeFile(outputPath, `${json}\n`, "utf8");
    console.error(`Saved report to ${outputPath}`);
  }
}

main().catch((error) => {
  console.error(`stt-ab failed: ${error?.message || String(error)}`);
  process.exit(1);
});
