import fs from "node:fs/promises";

const args = process.argv.slice(2);

function argValue(name, fallback = "") {
  const idx = args.indexOf(`--${name}`);
  if (idx === -1) return fallback;
  return args[idx + 1] ?? fallback;
}

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.max(0, Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

function summarize(values) {
  if (!values.length) {
    return { count: 0, avg: 0, p50: 0, p90: 0, p95: 0, min: 0, max: 0 };
  }
  const sum = values.reduce((acc, n) => acc + n, 0);
  return {
    count: values.length,
    avg: Number((sum / values.length).toFixed(2)),
    p50: percentile(values, 50),
    p90: percentile(values, 90),
    p95: percentile(values, 95),
    min: Math.min(...values),
    max: Math.max(...values)
  };
}

async function main() {
  const file = String(argValue("file", "")).trim();
  const provider = String(argValue("provider", "apple_speech")).trim();
  const message = String(argValue("message", "STT capture finished")).trim();
  if (!file) {
    throw new Error("Missing --file path to debug log export");
  }

  const text = await fs.readFile(file, "utf8");
  const lines = text.split(/\r?\n/);
  const matched = lines.filter((line) => line.includes(message) && line.includes(`provider=${provider}`));

  const msValues = [];
  const samples = [];
  for (const line of matched) {
    const msMatch = line.match(/\bms=(\d+)\b/);
    if (!msMatch) continue;
    const ms = Number(msMatch[1]);
    if (Number.isFinite(ms)) {
      msValues.push(ms);
      if (samples.length < 5) samples.push(line);
    }
  }

  const output = {
    file,
    provider,
    message,
    matchedLines: matched.length,
    parsedSamples: msValues.length,
    latencyMs: summarize(msValues),
    sampleLines: samples
  };
  console.log(JSON.stringify(output, null, 2));
}

main().catch((error) => {
  console.error(`stt-log-summary failed: ${error?.message || String(error)}`);
  process.exit(1);
});
