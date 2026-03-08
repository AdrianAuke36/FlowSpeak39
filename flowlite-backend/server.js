import fs from "node:fs";
import path from "node:path";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";
import { createRemoteJWKSet, jwtVerify } from "jose";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function loadDotenv() {
  const envPath = path.resolve(__dirname, ".env");
  if (!fs.existsSync(envPath)) return;

  try {
    const raw = fs.readFileSync(envPath, "utf8");
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const eq = trimmed.indexOf("=");
      if (eq <= 0) continue;
      const key = trimmed.slice(0, eq).trim();
      let value = trimmed.slice(eq + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      if (!(key in process.env)) {
        process.env[key] = value;
      }
    }
  } catch (error) {
    console.warn("⚠️ failed to read .env:", error?.message || String(error));
  }
}

loadDotenv();

const MODEL = process.env.OPENAI_MODEL || "gpt-4.1-nano";
const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || "127.0.0.1";
const BACKEND_TAG = "flowspeak-backend-2026-02-25-supabase-stripe-foundation";
const OPENAI_TIMEOUT_MS = Number(process.env.OPENAI_TIMEOUT_MS || 1800);
const OPENAI_MAX_MODEL_MS = Number(process.env.OPENAI_MAX_MODEL_MS || 2200);
const OPENAI_RETRIES = Math.max(1, Number(process.env.OPENAI_RETRIES || 1));
const OPENAI_RETRY_BACKOFF_MS = Math.max(0, Number(process.env.OPENAI_RETRY_BACKOFF_MS || 80));
const OPENAI_MAX_TOKENS_POLISH = Math.max(32, Number(process.env.OPENAI_MAX_TOKENS_POLISH || 96));
const OPENAI_MAX_TOKENS_POLISH_SHORT = Math.max(32, Number(process.env.OPENAI_MAX_TOKENS_POLISH_SHORT || 72));
const OPENAI_MAX_TOKENS_POLISH_MEANING = Math.max(64, Number(process.env.OPENAI_MAX_TOKENS_POLISH_MEANING || 160));
const OPENAI_MAX_TOKENS_POLISH_TRANSLATE = Math.max(32, Number(process.env.OPENAI_MAX_TOKENS_POLISH_TRANSLATE || 80));
const OPENAI_MAX_TOKENS_POLISH_SUBJECT = Math.max(24, Number(process.env.OPENAI_MAX_TOKENS_POLISH_SUBJECT || 48));
const OPENAI_MAX_TOKENS_POLISH_EMAIL_BODY = Math.max(64, Number(process.env.OPENAI_MAX_TOKENS_POLISH_EMAIL_BODY || 144));
const OPENAI_MAX_TOKENS_REWRITE = Math.max(64, Number(process.env.OPENAI_MAX_TOKENS_REWRITE || 128));
const POLISH_LOCAL_FASTPATH_ENABLED = String(process.env.POLISH_LOCAL_FASTPATH_ENABLED || "true").toLowerCase() !== "false";
const POLISH_LOCAL_FASTPATH_MAX_CHARS = Math.max(20, Number(process.env.POLISH_LOCAL_FASTPATH_MAX_CHARS || 90));
const POLISH_LOCAL_FASTPATH_MAX_WORDS = Math.max(3, Number(process.env.POLISH_LOCAL_FASTPATH_MAX_WORDS || 18));
const OPENAI_API_KEY_RAW = String(process.env.OPENAI_API_KEY || "").trim();
const OPENAI_API_KEY = OPENAI_API_KEY_RAW === "sk-..." ? "" : OPENAI_API_KEY_RAW;
const OPENAI_API_BASE_URL = String(process.env.OPENAI_API_BASE_URL || "https://api.openai.com/v1").trim().replace(/\/+$/, "");
const hasOpenAI = OPENAI_API_KEY.length > 0;
const DEFAULT_TARGET_LANGUAGE = process.env.DEFAULT_TARGET_LANGUAGE || "nb-NO";
const DEFAULT_DICTIONARY_PATH = path.resolve(__dirname, "dictionary.json");
const MAX_BODY_BYTES = 1_000_000;
const ALLOWED_ORIGINS = parseListEnv(process.env.ALLOWED_ORIGINS || "");
const API_TOKENS = parseListEnv(process.env.FLOWSPEAK_API_TOKENS || process.env.FLOWSPEAK_API_TOKEN || "");
const JWT_SECRETS = parseListEnv(process.env.FLOWSPEAK_JWT_SECRETS || process.env.FLOWSPEAK_JWT_SECRET || "");
const JWT_ACCEPTED_ISSUERS = parseListEnv(process.env.FLOWSPEAK_JWT_ISSUERS || process.env.FLOWSPEAK_JWT_ISSUER || "");
const JWT_ACCEPTED_AUDIENCES = parseListEnv(process.env.FLOWSPEAK_JWT_AUDIENCES || process.env.FLOWSPEAK_JWT_AUDIENCE || "");
const JWT_CLOCK_SKEW_SEC = Math.max(0, Number(process.env.JWT_CLOCK_SKEW_SEC || 20));
const JWT_ENABLED = JWT_SECRETS.length > 0;
const SUPABASE_URL = String(process.env.SUPABASE_URL || process.env.SUPABASE_PROJECT_URL || "").trim().replace(/\/+$/, "");
const SUPABASE_JWT_ISSUER = String(process.env.SUPABASE_JWT_ISSUER || (SUPABASE_URL ? `${SUPABASE_URL}/auth/v1` : "")).trim();
const SUPABASE_JWKS_URL = String(process.env.SUPABASE_JWKS_URL || (SUPABASE_JWT_ISSUER ? `${SUPABASE_JWT_ISSUER}/.well-known/jwks.json` : "")).trim();
const SUPABASE_JWT_AUDIENCES = parseListEnv(process.env.SUPABASE_JWT_AUDIENCES || process.env.SUPABASE_JWT_AUDIENCE || "authenticated");
const SUPABASE_JWKS_TIMEOUT_MS = Math.max(200, Number(process.env.SUPABASE_JWKS_TIMEOUT_MS || 1500));
const SUPABASE_JWKS_COOLDOWN_MS = Math.max(0, Number(process.env.SUPABASE_JWKS_COOLDOWN_MS || 30_000));
const SUPABASE_JWT_ENABLED = SUPABASE_JWKS_URL.length > 0;
const SUPABASE_REST_URL = String(process.env.SUPABASE_REST_URL || (SUPABASE_URL ? `${SUPABASE_URL}/rest/v1` : "")).trim().replace(/\/+$/, "");
const SUPABASE_SERVICE_ROLE_KEY = String(process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim();
const SUPABASE_BILLING_TABLE = String(process.env.SUPABASE_BILLING_TABLE || "billing_subscriptions").trim();
const DAILY_USAGE_TABLE = String(process.env.DAILY_USAGE_TABLE || "daily_usage_counters").trim() || "daily_usage_counters";
const SUPABASE_USER_COLUMN = String(process.env.SUPABASE_USER_COLUMN || "user_id").trim();
const SUPABASE_STRIPE_CUSTOMER_COLUMN = String(process.env.SUPABASE_STRIPE_CUSTOMER_COLUMN || "stripe_customer_id").trim();
const STRIPE_WEBHOOK_SECRET = String(process.env.STRIPE_WEBHOOK_SECRET || "").trim();
const STRIPE_SECRET_KEY = String(process.env.STRIPE_SECRET_KEY || "").trim();
const STRIPE_WEBHOOK_TOLERANCE_SEC = Math.max(0, Number(process.env.STRIPE_WEBHOOK_TOLERANCE_SEC || 300));
const STRIPE_PRICE_PLAN_MAP = parseJsonObjectMap(process.env.STRIPE_PRICE_PLAN_MAP || "");
const STRIPE_WEBHOOK_ENABLED = STRIPE_WEBHOOK_SECRET.length > 0;
const STRIPE_CHECKOUT_PRICE_ID = String(process.env.STRIPE_CHECKOUT_PRICE_ID || "").trim();
const STRIPE_CHECKOUT_SUCCESS_URL = String(process.env.STRIPE_CHECKOUT_SUCCESS_URL || "").trim();
const STRIPE_CHECKOUT_CANCEL_URL = String(process.env.STRIPE_CHECKOUT_CANCEL_URL || "").trim();
const STRIPE_CHECKOUT_ENABLED = STRIPE_CHECKOUT_PRICE_ID.length > 0 && STRIPE_SECRET_KEY.length > 0;
const SUPABASE_BILLING_SYNC_ENABLED = SUPABASE_REST_URL.length > 0 && SUPABASE_SERVICE_ROLE_KEY.length > 0;
const AUTH_DEBUG = String(process.env.AUTH_DEBUG || "").toLowerCase() === "true";
const AUTH_REQUIRED = String(process.env.REQUIRE_AUTH || "").toLowerCase() === "true" || API_TOKENS.length > 0 || JWT_ENABLED || SUPABASE_JWT_ENABLED;
const RATE_LIMIT_WINDOW_MS = Math.max(1_000, Number(process.env.RATE_LIMIT_WINDOW_MS || 60_000));
const RATE_LIMIT_MAX_AUTH = Math.max(1, Number(process.env.RATE_LIMIT_MAX_AUTH || 120));
const RATE_LIMIT_MAX_PUBLIC = Math.max(1, Number(process.env.RATE_LIMIT_MAX_PUBLIC || 30));
const RATE_LIMIT_MAX_AUTH_FREE = Math.max(1, Number(process.env.RATE_LIMIT_MAX_AUTH_FREE || RATE_LIMIT_MAX_AUTH));
const RATE_LIMIT_MAX_AUTH_PRO = Math.max(1, Number(process.env.RATE_LIMIT_MAX_AUTH_PRO || RATE_LIMIT_MAX_AUTH));
const RATE_LIMIT_MAX_AUTH_TEAM = Math.max(1, Number(process.env.RATE_LIMIT_MAX_AUTH_TEAM || RATE_LIMIT_MAX_AUTH));
const RATE_LIMIT_MAX_AUTH_ENTERPRISE = Math.max(1, Number(process.env.RATE_LIMIT_MAX_AUTH_ENTERPRISE || RATE_LIMIT_MAX_AUTH));
const DAILY_USAGE_MAX_AUTH_FREE = Math.max(0, Number(process.env.DAILY_USAGE_MAX_AUTH_FREE || 1_200));
const DAILY_USAGE_MAX_AUTH_PRO = Math.max(0, Number(process.env.DAILY_USAGE_MAX_AUTH_PRO || 5_000));
const DAILY_USAGE_MAX_AUTH_TEAM = Math.max(0, Number(process.env.DAILY_USAGE_MAX_AUTH_TEAM || 10_000));
const DAILY_USAGE_MAX_AUTH_ENTERPRISE = Math.max(0, Number(process.env.DAILY_USAGE_MAX_AUTH_ENTERPRISE || 25_000));
const DAILY_USAGE_SUPABASE_ENABLED = SUPABASE_REST_URL.length > 0 && SUPABASE_SERVICE_ROLE_KEY.length > 0;
const DAILY_USAGE_SUPABASE_RETRY_MAX = Math.max(1, Number(process.env.DAILY_USAGE_SUPABASE_RETRY_MAX || 4));
const TRUSTED_PROXY_IPS = parseListEnv(process.env.TRUSTED_PROXY_IPS || "");
const RATE_LIMIT_BUCKETS = new Map();
const DAILY_USAGE_BUCKETS = new Map();
const RATE_LIMIT_REDIS_URL = String(process.env.RATE_LIMIT_REDIS_URL || process.env.UPSTASH_REDIS_REST_URL || "").trim().replace(/\/+$/, "");
const RATE_LIMIT_REDIS_TOKEN = String(process.env.RATE_LIMIT_REDIS_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN || "").trim();
const RATE_LIMIT_REDIS_PREFIX = String(process.env.RATE_LIMIT_REDIS_PREFIX || "flowspeak:rl").trim() || "flowspeak:rl";
const RATE_LIMIT_REDIS_ENABLED = RATE_LIMIT_REDIS_URL.length > 0 && RATE_LIMIT_REDIS_TOKEN.length > 0;
const FASTPATH_CACHE_TTL_MS = Math.max(0, Number(process.env.FASTPATH_CACHE_TTL_MS || 10_000));
const FASTPATH_CACHE_MAX_ITEMS = Math.max(10, Number(process.env.FASTPATH_CACHE_MAX_ITEMS || 1_500));
const FASTPATH_CACHE = new Map();
const METRICS_HISTORY_MAX = Math.max(100, Number(process.env.METRICS_HISTORY_MAX || 2_000));
const METRICS_HISTORY = [];
const ERROR_HISTORY_MAX = Math.max(20, Number(process.env.ERROR_HISTORY_MAX || 250));
const ERROR_HISTORY = [];
const STARTED_AT_MS = Date.now();
let SUPABASE_REMOTE_JWKS = null;
const LOG_REQUEST_CONTENT = String(process.env.LOG_REQUEST_CONTENT || "").toLowerCase() === "true";
const WEBHOOK_DEDUP_TTL_MS = Math.max(60_000, Number(process.env.WEBHOOK_DEDUP_TTL_MS || 86_400_000));
const RECENT_WEBHOOK_EVENT_IDS = new Map();

const AUTH_TOKEN_HASHES = new Set(
  API_TOKENS.map((token) => shortHash(token))
);

if (AUTH_REQUIRED && AUTH_TOKEN_HASHES.size === 0 && !JWT_ENABLED && !SUPABASE_JWT_ENABLED) {
  console.warn("⚠️ auth is enabled but no FLOWSPEAK_API_TOKENS/FLOWSPEAK_JWT_SECRET/SUPABASE_JWKS_URL are configured.");
}
if (OPENAI_API_KEY_RAW && !hasOpenAI) {
  console.warn("⚠️ OPENAI_API_KEY uses placeholder value. Set a real key in .env or secrets.");
}
if ((RATE_LIMIT_REDIS_URL && !RATE_LIMIT_REDIS_TOKEN) || (!RATE_LIMIT_REDIS_URL && RATE_LIMIT_REDIS_TOKEN)) {
  console.warn("⚠️ redis rate-limit is partially configured. Set both RATE_LIMIT_REDIS_URL and RATE_LIMIT_REDIS_TOKEN.");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function shortHash(value) {
  return crypto.createHash("sha256").update(String(value || "")).digest("hex").slice(0, 16);
}

function parseListEnv(raw) {
  const out = [];
  const seen = new Set();
  for (const token of String(raw || "").split(/[,\n;]/)) {
    const normalized = token.trim();
    if (!normalized) continue;
    const key = normalized.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(normalized);
  }
  return out;
}

function parseJsonObjectMap(raw) {
  const text = String(raw || "").trim();
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    const out = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (!key) continue;
      out[String(key)] = String(value || "").trim();
    }
    return out;
  } catch {
    return {};
  }
}

function safePreview(text, maxChars = 40) {
  if (LOG_REQUEST_CONTENT) {
    return String(text || "").slice(0, maxChars);
  }
  return "[redacted]";
}

function buildReadinessReport() {
  const issues = [];
  if (!hasOpenAI) {
    issues.push("OPENAI_API_KEY missing.");
  }
  if (AUTH_REQUIRED && AUTH_TOKEN_HASHES.size === 0 && !JWT_ENABLED && !SUPABASE_JWT_ENABLED) {
    issues.push("Auth required but no validator configured.");
  }
  if (SUPABASE_JWT_ENABLED && !SUPABASE_JWT_ISSUER) {
    issues.push("SUPABASE_JWT_ISSUER is missing.");
  }
  return {
    ready: issues.length === 0,
    issues
  };
}

function safeEqualString(a, b) {
  const aBuf = Buffer.from(String(a || ""), "utf8");
  const bBuf = Buffer.from(String(b || ""), "utf8");
  if (aBuf.length !== bBuf.length) return false;
  return crypto.timingSafeEqual(aBuf, bBuf);
}

function normalizePlan(raw) {
  const value = String(raw || "").trim().toLowerCase();
  if (!value) return "free";
  if (value === "public") return "public";
  if (["free", "starter", "basic"].includes(value)) return "free";
  if (["pro", "plus", "premium"].includes(value)) return "pro";
  if (["team", "business"].includes(value)) return "team";
  if (["enterprise", "ent"].includes(value)) return "enterprise";
  return "free";
}

function resolveAuthenticatedRateLimit(plan) {
  const normalizedPlan = normalizePlan(plan);
  if (normalizedPlan === "enterprise") return RATE_LIMIT_MAX_AUTH_ENTERPRISE;
  if (normalizedPlan === "team") return RATE_LIMIT_MAX_AUTH_TEAM;
  if (normalizedPlan === "pro") return RATE_LIMIT_MAX_AUTH_PRO;
  return RATE_LIMIT_MAX_AUTH_FREE;
}

function resolveDailyUsageLimit(plan) {
  const normalizedPlan = normalizePlan(plan);
  if (normalizedPlan === "enterprise") return DAILY_USAGE_MAX_AUTH_ENTERPRISE;
  if (normalizedPlan === "team") return DAILY_USAGE_MAX_AUTH_TEAM;
  if (normalizedPlan === "pro") return DAILY_USAGE_MAX_AUTH_PRO;
  if (normalizedPlan === "public") return 0;
  return DAILY_USAGE_MAX_AUTH_FREE;
}

function currentUsageDayKey(now = Date.now()) {
  return new Date(now).toISOString().slice(0, 10);
}

function cleanupDailyUsageBuckets(dayKey = currentUsageDayKey()) {
  const prefix = `${dayKey}:`;
  for (const key of DAILY_USAGE_BUCKETS.keys()) {
    if (!key.startsWith(prefix)) {
      DAILY_USAGE_BUCKETS.delete(key);
    }
  }
}

function peekDailyUsageMemory(principalKey, plan) {
  const normalizedPlan = normalizePlan(plan);
  const limit = resolveDailyUsageLimit(normalizedPlan);
  const dayKey = currentUsageDayKey();
  cleanupDailyUsageBuckets(dayKey);

  if (limit <= 0) {
    return {
      dayKey,
      plan: normalizedPlan,
      limit: 0,
      used: 0,
      remaining: 0,
      enabled: false
    };
  }

  const bucket = DAILY_USAGE_BUCKETS.get(`${dayKey}:${principalKey}`);
  const used = Number(bucket?.count || 0);
  return {
    dayKey,
    plan: normalizedPlan,
    limit,
    used,
    remaining: Math.max(0, limit - used),
    enabled: true
  };
}

function consumeDailyUsageMemory(principalKey, plan) {
  const normalizedPlan = normalizePlan(plan);
  const limit = resolveDailyUsageLimit(normalizedPlan);
  const dayKey = currentUsageDayKey();
  cleanupDailyUsageBuckets(dayKey);

  if (limit <= 0) {
    return {
      dayKey,
      plan: normalizedPlan,
      limit: 0,
      used: 0,
      remaining: 0,
      enabled: false,
      allowed: true
    };
  }

  const key = `${dayKey}:${principalKey}`;
  const bucket = DAILY_USAGE_BUCKETS.get(key) || {
    count: 0,
    plan: normalizedPlan,
    lastSeenAt: 0
  };

  bucket.count += 1;
  bucket.plan = normalizedPlan;
  bucket.lastSeenAt = Date.now();
  DAILY_USAGE_BUCKETS.set(key, bucket);

  return {
    dayKey,
    plan: normalizedPlan,
    limit,
    used: bucket.count,
    remaining: Math.max(0, limit - bucket.count),
    enabled: true,
    allowed: bucket.count <= limit
  };
}

function buildSupabaseAdminHeaders(extra = {}) {
  return {
    apikey: SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    ...extra
  };
}

async function supabaseAdminRequest(endpoint, {
  method = "GET",
  body = undefined,
  headers = {}
} = {}) {
  const response = await fetch(endpoint, {
    method,
    headers: {
      ...(body == null ? {} : { "Content-Type": "application/json" }),
      ...buildSupabaseAdminHeaders(headers)
    },
    body: body == null ? undefined : JSON.stringify(body)
  });

  const bodyText = await response.text();
  let json = null;
  if (bodyText) {
    try {
      json = JSON.parse(bodyText);
    } catch {
      json = null;
    }
  }

  return {
    ok: response.ok,
    status: response.status,
    json,
    bodyText
  };
}

function recordBackendError(scope, details = {}) {
  const entry = {
    at: new Date().toISOString(),
    scope: String(scope || "unknown"),
    ...details
  };
  ERROR_HISTORY.push(entry);
  if (ERROR_HISTORY.length > ERROR_HISTORY_MAX) {
    ERROR_HISTORY.splice(0, ERROR_HISTORY.length - ERROR_HISTORY_MAX);
  }
  console.warn("⚠️ backend:", JSON.stringify(entry));
}

function recentBackendErrors(limit = 20) {
  return ERROR_HISTORY.slice(-limit).reverse();
}

function dailyUsageStorageMode() {
  return DAILY_USAGE_SUPABASE_ENABLED ? "supabase" : "memory";
}

function buildDailyUsageResult(dayKey, plan, used) {
  const normalizedPlan = normalizePlan(plan);
  const limit = resolveDailyUsageLimit(normalizedPlan);
  const safeUsed = Math.max(0, Number(used || 0));

  if (limit <= 0) {
    return {
      dayKey,
      plan: normalizedPlan,
      limit: 0,
      used: safeUsed,
      remaining: 0,
      enabled: false
    };
  }

  return {
    dayKey,
    plan: normalizedPlan,
    limit,
    used: safeUsed,
    remaining: Math.max(0, limit - safeUsed),
    enabled: true
  };
}

function dailyUsageTableBaseURL() {
  return `${SUPABASE_REST_URL}/${encodeURIComponent(DAILY_USAGE_TABLE)}`;
}

async function readDailyUsageRowSupabase(dayKey, principalKey) {
  const endpoint = `${dailyUsageTableBaseURL()}?select=day_key,principal_key,plan,request_count&day_key=eq.${encodeURIComponent(dayKey)}&principal_key=eq.${encodeURIComponent(principalKey)}&limit=1`;
  const response = await supabaseAdminRequest(endpoint);
  if (!response.ok) {
    throw new Error(`read failed (${response.status}): ${response.bodyText.slice(0, 200)}`);
  }
  const row = Array.isArray(response.json) ? response.json[0] : null;
  return row || null;
}

async function createDailyUsageRowSupabase(dayKey, principalKey, plan) {
  const response = await supabaseAdminRequest(dailyUsageTableBaseURL(), {
    method: "POST",
    headers: {
      Prefer: "return=representation"
    },
    body: [{
      day_key: dayKey,
      principal_key: principalKey,
      plan,
      request_count: 1
    }]
  });

  if (response.status === 409) {
    return null;
  }
  if (!response.ok) {
    throw new Error(`insert failed (${response.status}): ${response.bodyText.slice(0, 200)}`);
  }

  const row = Array.isArray(response.json) ? response.json[0] : null;
  if (!row) {
    throw new Error("insert failed: empty response");
  }
  return row;
}

async function updateDailyUsageRowSupabase(dayKey, principalKey, plan, currentCount) {
  const nextCount = Math.max(0, Number(currentCount || 0)) + 1;
  const endpoint = `${dailyUsageTableBaseURL()}?day_key=eq.${encodeURIComponent(dayKey)}&principal_key=eq.${encodeURIComponent(principalKey)}&request_count=eq.${encodeURIComponent(currentCount)}`;
  const response = await supabaseAdminRequest(endpoint, {
    method: "PATCH",
    headers: {
      Prefer: "return=representation"
    },
    body: {
      request_count: nextCount,
      plan,
      updated_at: new Date().toISOString()
    }
  });

  if (!response.ok) {
    throw new Error(`update failed (${response.status}): ${response.bodyText.slice(0, 200)}`);
  }

  const row = Array.isArray(response.json) ? response.json[0] : null;
  return row || null;
}

async function peekDailyUsageSupabase(principalKey, plan) {
  const dayKey = currentUsageDayKey();
  const row = await readDailyUsageRowSupabase(dayKey, principalKey);
  return buildDailyUsageResult(dayKey, row?.plan || plan, Number(row?.request_count || 0));
}

async function consumeDailyUsageSupabase(principalKey, plan) {
  const normalizedPlan = normalizePlan(plan);
  const dayKey = currentUsageDayKey();
  const limit = resolveDailyUsageLimit(normalizedPlan);
  if (limit <= 0) {
    return {
      ...buildDailyUsageResult(dayKey, normalizedPlan, 0),
      allowed: true
    };
  }

  for (let attempt = 0; attempt < DAILY_USAGE_SUPABASE_RETRY_MAX; attempt += 1) {
    const current = await readDailyUsageRowSupabase(dayKey, principalKey);
    let row = null;

    if (!current) {
      row = await createDailyUsageRowSupabase(dayKey, principalKey, normalizedPlan);
      if (!row) {
        continue;
      }
    } else {
      row = await updateDailyUsageRowSupabase(
        dayKey,
        principalKey,
        normalizedPlan,
        Number(current.request_count || 0)
      );
      if (!row) {
        continue;
      }
    }

    const usage = buildDailyUsageResult(dayKey, row.plan || normalizedPlan, Number(row.request_count || 0));
    return {
      ...usage,
      allowed: !usage.enabled || usage.used <= usage.limit
    };
  }

  throw new Error(`daily usage update exhausted after ${DAILY_USAGE_SUPABASE_RETRY_MAX} attempts`);
}

async function summarizeDailyUsageSupabase() {
  const dayKey = currentUsageDayKey();
  const endpoint = `${dailyUsageTableBaseURL()}?select=plan,request_count&day_key=eq.${encodeURIComponent(dayKey)}`;
  const response = await supabaseAdminRequest(endpoint);
  if (!response.ok) {
    throw new Error(`summary failed (${response.status}): ${response.bodyText.slice(0, 200)}`);
  }

  const rows = Array.isArray(response.json) ? response.json : [];
  const byPlan = {};
  let totalRequests = 0;
  for (const row of rows) {
    const plan = normalizePlan(row?.plan || "free");
    const count = Math.max(0, Number(row?.request_count || 0));
    totalRequests += count;
    byPlan[plan] = (byPlan[plan] || 0) + count;
  }

  return {
    dayKey,
    activeUsers: rows.length,
    totalRequests,
    byPlan
  };
}

async function peekDailyUsage(principalKey, plan) {
  if (!DAILY_USAGE_SUPABASE_ENABLED) {
    return peekDailyUsageMemory(principalKey, plan);
  }

  try {
    return await peekDailyUsageSupabase(principalKey, plan);
  } catch (error) {
    recordBackendError("daily_usage_peek_fallback", {
      storage: "memory",
      message: error?.message || "unknown"
    });
    return peekDailyUsageMemory(principalKey, plan);
  }
}

async function consumeDailyUsage(principalKey, plan) {
  if (!DAILY_USAGE_SUPABASE_ENABLED) {
    return consumeDailyUsageMemory(principalKey, plan);
  }

  try {
    return await consumeDailyUsageSupabase(principalKey, plan);
  } catch (error) {
    recordBackendError("daily_usage_consume_fallback", {
      storage: "memory",
      message: error?.message || "unknown"
    });
    return consumeDailyUsageMemory(principalKey, plan);
  }
}

function decodeBase64Url(input) {
  const normalized = String(input || "").replace(/-/g, "+").replace(/_/g, "/");
  if (!normalized || normalized.length % 4 === 1) return null;
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  try {
    return Buffer.from(padded, "base64").toString("utf8");
  } catch {
    return null;
  }
}

function decodeJwtPart(part) {
  const decoded = decodeBase64Url(part);
  if (!decoded) return null;
  try {
    return JSON.parse(decoded);
  } catch {
    return null;
  }
}

function toBase64Url(buffer) {
  return Buffer.from(buffer)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function verifySharedSecretJwtToken(token) {
  if (!JWT_ENABLED) return { ok: false };

  const parts = String(token || "").split(".");
  if (parts.length !== 3) {
    return { ok: false };
  }
  const [headerPart, payloadPart, signaturePart] = parts;
  if (!headerPart || !payloadPart || !signaturePart) {
    return { ok: false };
  }

  const header = decodeJwtPart(headerPart);
  const payload = decodeJwtPart(payloadPart);
  if (!header || !payload) {
    return { ok: false };
  }
  if (String(header.alg || "").toUpperCase() !== "HS256") {
    return { ok: false };
  }

  const signingInput = `${headerPart}.${payloadPart}`;
  let validSignature = false;
  for (const secret of JWT_SECRETS) {
    const expectedSignature = toBase64Url(
      crypto.createHmac("sha256", secret).update(signingInput).digest()
    );
    if (safeEqualString(expectedSignature, signaturePart)) {
      validSignature = true;
      break;
    }
  }
  if (!validSignature) {
    return { ok: false };
  }

  const nowSec = Math.floor(Date.now() / 1000);
  const skewSec = JWT_CLOCK_SKEW_SEC;
  const exp = Number(payload.exp);
  if (Number.isFinite(exp) && exp > 0 && exp < nowSec - skewSec) {
    return { ok: false };
  }
  const nbf = Number(payload.nbf);
  if (Number.isFinite(nbf) && nbf > 0 && nbf > nowSec + skewSec) {
    return { ok: false };
  }
  const iat = Number(payload.iat);
  if (Number.isFinite(iat) && iat > 0 && iat > nowSec + skewSec) {
    return { ok: false };
  }

  if (JWT_ACCEPTED_ISSUERS.length > 0) {
    const issuer = String(payload.iss || "").trim();
    if (!issuer || !JWT_ACCEPTED_ISSUERS.includes(issuer)) {
      return { ok: false };
    }
  }

  if (JWT_ACCEPTED_AUDIENCES.length > 0) {
    const rawAud = payload.aud;
    const audiences = Array.isArray(rawAud) ? rawAud.map((v) => String(v || "").trim()).filter(Boolean) : [String(rawAud || "").trim()].filter(Boolean);
    const hasAllowedAudience = audiences.some((aud) => JWT_ACCEPTED_AUDIENCES.includes(aud));
    if (!hasAllowedAudience) {
      return { ok: false };
    }
  }

  const principal = String(
    payload.sub
    || payload.user_id
    || payload.client_id
    || payload.device_id
    || payload.email
    || ""
  ).trim();
  const plan = normalizePlan(payload.plan || payload.tier || payload.subscription || payload.product);
  const ratePrincipal = principal || shortHash(signingInput);
  return {
    ok: true,
    tokenHash: shortHash(ratePrincipal),
    authenticated: true,
    authType: "jwt",
    principal: principal || "jwt-user",
    plan
  };
}

function claimString(value) {
  if (typeof value !== "string") return "";
  return value.trim();
}

function planFromClaims(payload) {
  return normalizePlan(
    payload?.plan
    || payload?.tier
    || payload?.subscription
    || payload?.product
    || payload?.app_metadata?.plan
    || payload?.app_metadata?.tier
    || payload?.user_metadata?.plan
    || payload?.user_metadata?.tier
  );
}

function getSupabaseRemoteJwks() {
  if (!SUPABASE_JWT_ENABLED) return null;
  if (SUPABASE_REMOTE_JWKS) return SUPABASE_REMOTE_JWKS;

  try {
    SUPABASE_REMOTE_JWKS = createRemoteJWKSet(new URL(SUPABASE_JWKS_URL), {
      timeoutDuration: SUPABASE_JWKS_TIMEOUT_MS,
      cooldownDuration: SUPABASE_JWKS_COOLDOWN_MS
    });
  } catch (error) {
    console.warn("⚠️ invalid SUPABASE_JWKS_URL:", error?.message || "unknown");
    SUPABASE_REMOTE_JWKS = null;
  }
  return SUPABASE_REMOTE_JWKS;
}

async function verifySupabaseJwtToken(token) {
  if (!SUPABASE_JWT_ENABLED) return { ok: false };
  const jwks = getSupabaseRemoteJwks();
  if (!jwks) return { ok: false };

  try {
    const verified = await jwtVerify(token, jwks, {
      issuer: SUPABASE_JWT_ISSUER || undefined,
      audience: SUPABASE_JWT_AUDIENCES.length > 0 ? SUPABASE_JWT_AUDIENCES : undefined,
      clockTolerance: JWT_CLOCK_SKEW_SEC
    });

    const payload = verified?.payload || {};
    const principal = claimString(payload.sub)
      || claimString(payload.user_id)
      || claimString(payload.email)
      || claimString(payload.phone)
      || "supabase-user";
    const plan = planFromClaims(payload);

    return {
      ok: true,
      tokenHash: shortHash(principal),
      authenticated: true,
      authType: "supabase_jwt",
      principal,
      plan
    };
  } catch (error) {
    if (AUTH_DEBUG) {
      console.warn("⚠️ supabase jwt verify failed:", error?.name || "Error", error?.message || "unknown");
    }
    return { ok: false };
  }
}

function extractBearerToken(req) {
  const authHeader = String(req.headers?.authorization || "");
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (match?.[1]) return match[1].trim();

  const fallback = String(req.headers?.["x-flowspeak-token"] || req.headers?.["x-api-key"] || "").trim();
  return fallback || "";
}

async function verifyToken(req) {
  if (!AUTH_REQUIRED) {
    return {
      ok: true,
      tokenHash: "public",
      authenticated: false,
      authType: "public",
      principal: "public",
      plan: "public"
    };
  }

  const presented = extractBearerToken(req);
  if (!presented) {
    return { ok: false, status: 401, error: "Missing API token." };
  }

  for (const configuredToken of API_TOKENS) {
    if (safeEqualString(configuredToken, presented)) {
      return {
        ok: true,
        tokenHash: shortHash(presented),
        authenticated: true,
        authType: "token",
        principal: shortHash(presented),
        plan: "pro"
      };
    }
  }

  const jwt = verifySharedSecretJwtToken(presented);
  if (jwt.ok) {
    return jwt;
  }

  const supabaseJwt = await verifySupabaseJwtToken(presented);
  if (supabaseJwt.ok) {
    return supabaseJwt;
  }

  return { ok: false, status: 401, error: "Invalid API token." };
}

function requestIP(req) {
  const socketIP = req.socket?.remoteAddress || "unknown";
  const proxyTrusted = TRUSTED_PROXY_IPS.length === 0 || TRUSTED_PROXY_IPS.includes(socketIP);
  if (proxyTrusted) {
    const forwarded = String(req.headers?.["x-forwarded-for"] || "").trim();
    if (forwarded) return forwarded.split(",")[0].trim();
    const realIP = String(req.headers?.["x-real-ip"] || "").trim();
    if (realIP) return realIP;
  }
  return socketIP;
}

function cleanupRateLimitBuckets(now) {
  if (RATE_LIMIT_BUCKETS.size < 2_000) return;
  for (const [key, bucket] of RATE_LIMIT_BUCKETS.entries()) {
    if (!bucket || bucket.resetAt <= now) {
      RATE_LIMIT_BUCKETS.delete(key);
    }
  }
}

function consumeRateLimitMemory(key, limit) {
  const now = Date.now();
  cleanupRateLimitBuckets(now);

  let bucket = RATE_LIMIT_BUCKETS.get(key);
  if (!bucket || bucket.resetAt <= now) {
    bucket = { count: 0, resetAt: now + RATE_LIMIT_WINDOW_MS };
  }

  bucket.count += 1;
  RATE_LIMIT_BUCKETS.set(key, bucket);

  const allowed = bucket.count <= limit;
  const remaining = Math.max(0, limit - bucket.count);
  return {
    allowed,
    limit,
    remaining,
    resetAt: bucket.resetAt
  };
}

function encodeRedisPart(value) {
  return encodeURIComponent(String(value == null ? "" : value));
}

async function redisRateLimitCommand(parts) {
  const path = parts.map(encodeRedisPart).join("/");
  const endpoint = `${RATE_LIMIT_REDIS_URL}/${path}`;
  const response = await fetch(endpoint, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${RATE_LIMIT_REDIS_TOKEN}`
    }
  });
  if (!response.ok) {
    const bodyText = await response.text();
    throw new Error(`Redis rate-limit command failed (${response.status}): ${bodyText.slice(0, 200)}`);
  }
  const payload = await response.json();
  return payload?.result;
}

async function consumeRateLimitRedis(key, limit) {
  const now = Date.now();
  const redisKey = `${RATE_LIMIT_REDIS_PREFIX}:${key}`;

  const countRaw = await redisRateLimitCommand(["INCR", redisKey]);
  const count = Number(countRaw);
  if (!Number.isFinite(count) || count <= 0) {
    throw new Error("Redis INCR returned invalid value.");
  }
  if (count === 1) {
    await redisRateLimitCommand(["PEXPIRE", redisKey, RATE_LIMIT_WINDOW_MS]);
  }

  const ttlRaw = await redisRateLimitCommand(["PTTL", redisKey]);
  let ttlMs = Number(ttlRaw);
  if (!Number.isFinite(ttlMs) || ttlMs < 0) {
    ttlMs = RATE_LIMIT_WINDOW_MS;
  }

  const allowed = count <= limit;
  const remaining = Math.max(0, limit - count);
  return {
    allowed,
    limit,
    remaining,
    resetAt: now + ttlMs
  };
}

async function consumeRateLimit(key, limit) {
  if (!RATE_LIMIT_REDIS_ENABLED) {
    return consumeRateLimitMemory(key, limit);
  }
  try {
    return await consumeRateLimitRedis(key, limit);
  } catch (error) {
    console.warn("⚠️ redis rate-limit unavailable, falling back to memory:", error?.message || "unknown");
    return consumeRateLimitMemory(key, limit);
  }
}

function cleanupFastpathCache(now) {
  for (const [key, entry] of FASTPATH_CACHE.entries()) {
    if (!entry || entry.expiresAt <= now) {
      FASTPATH_CACHE.delete(key);
    }
  }
}

function getFastpathCache(cacheKey) {
  if (!FASTPATH_CACHE_TTL_MS) return null;
  const now = Date.now();
  const entry = FASTPATH_CACHE.get(cacheKey);
  if (!entry) return null;
  if (entry.expiresAt <= now) {
    FASTPATH_CACHE.delete(cacheKey);
    return null;
  }
  entry.lastAccessAt = now;
  return entry.value;
}

function setFastpathCache(cacheKey, value) {
  if (!FASTPATH_CACHE_TTL_MS) return;
  const now = Date.now();
  cleanupFastpathCache(now);

  FASTPATH_CACHE.set(cacheKey, {
    value,
    expiresAt: now + FASTPATH_CACHE_TTL_MS,
    lastAccessAt: now
  });

  if (FASTPATH_CACHE.size <= FASTPATH_CACHE_MAX_ITEMS) return;
  const firstKey = FASTPATH_CACHE.keys().next().value;
  if (firstKey) {
    FASTPATH_CACHE.delete(firstKey);
  }
}

function recordPolishMetric(sample) {
  const cacheState = String(sample?.cache || "").toUpperCase();
  METRICS_HISTORY.push({
    ts: Date.now(),
    status: Number(sample?.status || 0),
    endpointMs: Number(sample?.endpointMs || 0),
    modelMs: Number(sample?.modelMs || 0),
    fallback: Boolean(sample?.fallback),
    cache: cacheState === "HIT" ? "HIT" : (cacheState === "BYPASS" ? "BYPASS" : "MISS"),
    mode: String(sample?.mode || "unknown"),
    auth: String(sample?.auth || "unknown"),
    plan: normalizePlan(sample?.plan || "free")
  });

  if (METRICS_HISTORY.length > METRICS_HISTORY_MAX) {
    METRICS_HISTORY.splice(0, METRICS_HISTORY.length - METRICS_HISTORY_MAX);
  }
}

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.max(0, Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

function summarizeMetricSeries(values) {
  const list = values.filter((v) => Number.isFinite(v) && v >= 0);
  if (!list.length) {
    return { count: 0, min: 0, max: 0, avg: 0, p50: 0, p90: 0, p95: 0, p99: 0 };
  }
  const sum = list.reduce((acc, value) => acc + value, 0);
  return {
    count: list.length,
    min: Math.round(Math.min(...list)),
    max: Math.round(Math.max(...list)),
    avg: Math.round(sum / list.length),
    p50: Math.round(percentile(list, 50)),
    p90: Math.round(percentile(list, 90)),
    p95: Math.round(percentile(list, 95)),
    p99: Math.round(percentile(list, 99))
  };
}

function summarizePolishMetrics() {
  const samples = METRICS_HISTORY.slice();
  const endpointSeries = summarizeMetricSeries(samples.map((entry) => entry.endpointMs));
  const modelSeries = summarizeMetricSeries(samples.map((entry) => entry.modelMs).filter((value) => value > 0));
  const successCount = samples.filter((entry) => entry.status >= 200 && entry.status < 300).length;
  const fallbackCount = samples.filter((entry) => entry.fallback).length;
  const cacheHitCount = samples.filter((entry) => entry.cache === "HIT").length;
  const cacheBypassCount = samples.filter((entry) => entry.cache === "BYPASS").length;
  const modeCounts = {};
  for (const entry of samples) {
    modeCounts[entry.mode] = (modeCounts[entry.mode] || 0) + 1;
  }
  const authCounts = {};
  for (const entry of samples) {
    authCounts[entry.auth] = (authCounts[entry.auth] || 0) + 1;
  }
  const planCounts = {};
  for (const entry of samples) {
    planCounts[entry.plan] = (planCounts[entry.plan] || 0) + 1;
  }

  const total = samples.length || 1;
  return {
    uptimeSec: Math.floor((Date.now() - STARTED_AT_MS) / 1000),
    samples: samples.length,
    endpointMs: endpointSeries,
    modelMs: modelSeries,
    successRate: Number((successCount / total).toFixed(4)),
    fallbackRate: Number((fallbackCount / total).toFixed(4)),
    cacheHitRate: Number((cacheHitCount / total).toFixed(4)),
    cacheBypassRate: Number((cacheBypassCount / total).toFixed(4)),
    byMode: modeCounts,
    byAuth: authCounts,
    byPlan: planCounts
  };
}

function summarizeDailyUsageMemory() {
  const dayKey = currentUsageDayKey();
  cleanupDailyUsageBuckets(dayKey);

  const buckets = [];
  for (const [key, bucket] of DAILY_USAGE_BUCKETS.entries()) {
    if (!key.startsWith(`${dayKey}:`) || !bucket) continue;
    buckets.push(bucket);
  }

  const byPlan = {};
  let totalRequests = 0;
  for (const bucket of buckets) {
    const plan = normalizePlan(bucket.plan || "free");
    const count = Number(bucket.count || 0);
    totalRequests += count;
    byPlan[plan] = (byPlan[plan] || 0) + count;
  }

  return {
    dayKey,
    activeUsers: buckets.length,
    totalRequests,
    byPlan
  };
}

async function summarizeDailyUsage() {
  if (!DAILY_USAGE_SUPABASE_ENABLED) {
    return summarizeDailyUsageMemory();
  }

  try {
    return await summarizeDailyUsageSupabase();
  } catch (error) {
    recordBackendError("daily_usage_summary_fallback", {
      storage: "memory",
      message: error?.message || "unknown"
    });
    return summarizeDailyUsageMemory();
  }
}

function buildFastpathCacheKey(body) {
  const normalized = {
    text: String(body?.text || "").trim(),
    mode: String(body?.mode || "generic"),
    style: String(body?.style || "clean"),
    targetLanguage: String(body?.targetLanguage || DEFAULT_TARGET_LANGUAGE),
    targetLanguageForced: body?.targetLanguageForced === true,
    bundleId: String(body?.bundleId || ""),
    appName: String(body?.appName || ""),
    axRole: String(body?.axRole || ""),
    axSubrole: String(body?.axSubrole || ""),
    axDescription: String(body?.axDescription || ""),
    axHelp: String(body?.axHelp || ""),
    axTitle: String(body?.axTitle || ""),
    axPlaceholder: String(body?.axPlaceholder || ""),
    fieldContext: String(body?.fieldContext || ""),
    browserURL: String(body?.browserURL || ""),
    glossary: Array.isArray(body?.glossary) ? body.glossary : [],
    replacements: Array.isArray(body?.replacements) ? body.replacements : []
  };

  return shortHash(JSON.stringify(normalized));
}

function shouldBypassFastpathCache(req, body) {
  const headerValue = String(req.headers?.["x-fastpath-bypass"] || "").trim().toLowerCase();
  if (headerValue === "1" || headerValue === "true" || headerValue === "yes") return true;
  return body?.cacheBypass === true;
}

function resolveAllowOrigin(req) {
  const requestOrigin = String(req.headers?.origin || "").trim();
  if (ALLOWED_ORIGINS.includes("*")) return "*";
  if (!requestOrigin) return ALLOWED_ORIGINS[0] || "";
  if (ALLOWED_ORIGINS.includes(requestOrigin)) return requestOrigin;
  return "";
}

function buildBaseResponseHeaders(req) {
  const allowOrigin = resolveAllowOrigin(req);
  const headers = {
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-FlowSpeak-Token, X-API-Key, Stripe-Signature",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store"
  };
  if (allowOrigin) {
    headers["Access-Control-Allow-Origin"] = allowOrigin;
    headers.Vary = "Origin";
  }
  return headers;
}

function escapeRegex(value) {
  return String(value || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function uniqueStrings(values) {
  const out = [];
  const seen = new Set();
  for (const value of values || []) {
    const normalized = String(value || "").replace(/\s+/g, " ").trim();
    if (!normalized) continue;
    const key = normalized.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(normalized);
  }
  return out;
}

function normalizeReplacement(raw) {
  if (!raw || typeof raw !== "object") return null;
  const from = String(raw.from || raw.source || "").replace(/\s+/g, " ").trim();
  const to = String(raw.to || raw.destination || "").replace(/\s+/g, " ").trim();
  if (!from || !to || from.toLowerCase() === to.toLowerCase()) return null;
  return { from, to };
}

function normalizeDictionary(input) {
  const terms = uniqueStrings(input?.terms || []);
  const replacements = [];
  const seen = new Set();
  for (const raw of input?.replacements || []) {
    const normalized = normalizeReplacement(raw);
    if (!normalized) continue;
    const key = `${normalized.from.toLowerCase()}->${normalized.to.toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    replacements.push(normalized);
  }
  return { terms, replacements };
}

function parseTermsEnv(raw) {
  if (!raw) return [];
  return uniqueStrings(
    String(raw)
      .split(/[,\n;]/)
      .map((part) => part.trim())
  );
}

function parseReplacementsEnv(raw) {
  if (!raw) return [];
  const items = [];
  for (const part of String(raw).split(/[,\n;]/)) {
    const trimmed = part.trim();
    if (!trimmed) continue;
    const [left, right] = trimmed.split("->").map((v) => String(v || "").trim());
    if (!left || !right) continue;
    items.push({ from: left, to: right });
  }
  return items;
}

function loadDictionaryFromFile(filePath) {
  try {
    if (!filePath || !fs.existsSync(filePath)) return { terms: [], replacements: [] };
    const raw = fs.readFileSync(filePath, "utf8");
    const parsed = JSON.parse(raw);
    return normalizeDictionary(parsed);
  } catch (error) {
    console.warn("⚠️ invalid dictionary file:", error?.message);
    return { terms: [], replacements: [] };
  }
}

function loadBaseDictionary() {
  const envTerms = parseTermsEnv(process.env.FLOWSPEAK_GLOSSARY || process.env.FLOWSPEAK_TERMS);
  const envReplacements = parseReplacementsEnv(process.env.FLOWSPEAK_REPLACEMENTS);
  const configuredPath = process.env.FLOWSPEAK_DICTIONARY_PATH
    ? path.resolve(process.env.FLOWSPEAK_DICTIONARY_PATH)
    : DEFAULT_DICTIONARY_PATH;
  const fileDict = loadDictionaryFromFile(configuredPath);
  const base = normalizeDictionary({
    terms: envTerms.concat(fileDict.terms),
    replacements: envReplacements.concat(fileDict.replacements),
  });
  if (base.terms.length || base.replacements.length) {
    console.log("📚 dictionary loaded:", configuredPath, "| terms:", base.terms.length, "| replacements:", base.replacements.length);
  }
  return base;
}

const BASE_DICTIONARY = loadBaseDictionary();

function getRequestDictionary(body) {
  const requestTerms = Array.isArray(body?.glossary) ? body.glossary : [];
  const requestReplacements = Array.isArray(body?.replacements) ? body.replacements : [];
  return normalizeDictionary({
    terms: BASE_DICTIONARY.terms.concat(requestTerms),
    replacements: BASE_DICTIONARY.replacements.concat(requestReplacements),
  });
}

function applyCasePattern(source, destination) {
  const src = String(source || "");
  const dst = String(destination || "");
  if (!src || !dst) return dst;
  if (src === src.toUpperCase()) return dst.toUpperCase();
  if (src[0] && src[0] === src[0].toUpperCase()) {
    return dst[0].toUpperCase() + dst.slice(1);
  }
  return dst;
}

function applyDictionaryReplacements(text, dictionary) {
  let out = String(text || "");
  if (!out || !dictionary?.replacements?.length) return out;

  const rules = [...dictionary.replacements].sort((a, b) => b.from.length - a.from.length);
  for (const rule of rules) {
    const escaped = escapeRegex(rule.from);
    if (!escaped) continue;
    const re = new RegExp(`(^|[^\\p{L}\\p{N}])(${escaped})(?=$|[^\\p{L}\\p{N}])`, "giu");
    out = out.replace(re, (_, lead, matched) => `${lead}${applyCasePattern(matched, rule.to)}`);
  }
  return out;
}

function buildDictionaryPromptClause(dictionary) {
  if (!dictionary) return "";
  const terms = uniqueStrings([
    ...(dictionary.terms || []),
    ...(dictionary.replacements || []).map((r) => r.to),
  ]).slice(0, 24);
  const replacements = (dictionary.replacements || []).slice(0, 12);

  let clause = "";
  if (terms.length) {
    clause += ` Prefer exact spelling for relevant terms: ${terms.join(", ")}.`;
  }
  if (replacements.length) {
    const pairs = replacements.map((r) => `"${r.from}" -> "${r.to}"`).join("; ");
    clause += ` If the spoken text clearly matches these, normalize using: ${pairs}.`;
  }
  return clause;
}

async function requestModelDraft({
  system,
  user,
  requestSignal,
  maxTokens = OPENAI_MAX_TOKENS_POLISH,
  wantsJsonOutput = true
}) {
  const attemptStats = [];
  let lastError = null;
  const overallStartedAt = Date.now();

  for (let attempt = 1; attempt <= OPENAI_RETRIES; attempt += 1) {
    if (requestSignal?.aborted) {
      const abortedErr = new Error("Request aborted by client");
      abortedErr.attempts = attemptStats;
      throw abortedErr;
    }

    const elapsedMs = Date.now() - overallStartedAt;
    const remainingBudget = OPENAI_MAX_MODEL_MS - elapsedMs;
    if (remainingBudget <= 120) break;

    const startedAt = Date.now();
    try {
      const controller = new AbortController();
      const attemptTimeoutMs = Math.max(200, Math.min(OPENAI_TIMEOUT_MS, remainingBudget));
      let timedOut = false;
      const timeout = setTimeout(() => {
        timedOut = true;
        controller.abort();
      }, attemptTimeoutMs);
      const onRequestAbort = () => controller.abort();
      if (requestSignal) {
        requestSignal.addEventListener("abort", onRequestAbort, { once: true });
      }
      let response;
      try {
        const payload = {
          model: MODEL,
          temperature: 0,
          max_tokens: Math.max(32, Math.min(Number(maxTokens || OPENAI_MAX_TOKENS_POLISH), 400)),
          messages: [
            { role: "system", content: system },
            { role: "user", content: user }
          ]
        };
        if (wantsJsonOutput) {
          payload.response_format = { type: "json_object" };
        }
        const http = await fetch(`${OPENAI_API_BASE_URL}/chat/completions`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${OPENAI_API_KEY}`,
          },
          body: JSON.stringify(payload),
          signal: controller.signal
        });
        const bodyText = await http.text();
        if (!http.ok) {
          throw new Error(`OpenAI HTTP ${http.status}: ${bodyText.slice(0, 240)}`);
        }
        try {
          response = JSON.parse(bodyText);
        } catch {
          throw new Error("OpenAI returned invalid JSON.");
        }
      } catch (error) {
        if (error?.name === "AbortError") {
          if (requestSignal?.aborted) {
            throw new Error("Request aborted by client");
          }
          if (timedOut) {
            throw new Error(`OpenAI timeout after ${attemptTimeoutMs}ms`);
          }
          throw new Error("OpenAI request aborted");
        }
        throw error;
      } finally {
        clearTimeout(timeout);
        if (requestSignal) {
          requestSignal.removeEventListener("abort", onRequestAbort);
        }
      }

      attemptStats.push({ attempt, ms: Date.now() - startedAt, ok: true });
      return { response, attempts: attemptStats };
    } catch (error) {
      lastError = error;
      attemptStats.push({ attempt, ms: Date.now() - startedAt, ok: false, error: error?.message || "unknown" });
      if (requestSignal?.aborted) {
        break;
      }
      if (attempt < OPENAI_RETRIES) {
        const soFar = Date.now() - overallStartedAt;
        if (soFar >= OPENAI_MAX_MODEL_MS - 120) {
          break;
        }
        await sleep(OPENAI_RETRY_BACKOFF_MS * attempt);
      }
    }
  }

  const err = new Error(lastError?.message || "OpenAI request failed");
  err.attempts = attemptStats;
  throw err;
}

const MODE_RULES = {
  email_subject: "Short email subject. No greeting, no period.",
  email_body:    "Email body. Keep short paragraphs with clear line breaks. If a full email is clearly intended and greeting/sign-off are missing, add neutral ones.",
  chat_message:  "Chat message. Concise and natural.",
  note:          "Note. Bullet points if helpful.",
  generic:       "Neutral style.",
};

const STYLE_RULES = {
  clean: "Style: clean. Rewrite only. Keep neutral tone. Correct grammar and punctuation, apply self-corrections, and remove filler words (e.g. uhm/ehm) without changing meaning."
};

const INTERPRETATION_RULES = {
  literal: "Interpretation: literal. Stay as close as possible to the spoken wording and order. Preserve phrasing, hesitations, and sentence structure unless something is clearly a recognition artifact.",
  balanced: "Interpretation: balanced. Clean up the text while staying close to what the user said.",
  meaning: "Interpretation: meaning. Prioritize the user's likely intent over literal wording. You may merge fragments, reorder ideas, smooth awkward phrasing, and turn rough speech into the clearest natural sentence or paragraph, but do not add new facts, commitments, or requests. If details are uncertain, keep them generic instead of guessing."
};

const POLISH_BASE_GUARDRAIL =
  "Task type is transcription polishing, not chat or Q&A. Never answer, agree/disagree, ask follow-up questions, or add assistant commentary. Rewrite only the dictated content.";
const POLISH_FACT_GUARDRAIL =
  "Preserve concrete details (names, dates, numbers, amounts, URLs, explicit yes/no intent) unless they are clearly recognition errors.";

function normalizeStyle(raw) {
  // Style selection is disabled in the app; keep backend behavior fixed to clean.
  return "clean";
}

function normalizeInterpretationLevel(raw) {
  const v = String(raw || "").trim().toLowerCase();
  if (v === "literal" || v === "balanced" || v === "meaning") return v;
  return "balanced";
}

function replaceLastMatch(text, pattern, replacement) {
  let last = null;
  for (const match of String(text || "").matchAll(pattern)) {
    last = match;
  }
  if (!last || typeof last.index !== "number") return String(text || "");
  const i = last.index;
  return String(text).slice(0, i) + replacement + String(text).slice(i + String(last[0]).length);
}

function isLikelyPersonNameToken(value) {
  const token = String(value || "").trim().toLowerCase();
  if (!token) return false;

  const blacklist = new Set([
    "kan", "kunne", "du", "jeg", "vi", "dere", "har", "hadde", "ha", "vil", "ville",
    "kommer", "kommet", "kom", "gå", "drar", "dra", "i", "på", "til", "fra", "at", "om",
    "how", "can", "could", "would", "will", "are", "is", "do", "did"
  ]);
  if (blacklist.has(token)) return false;
  return /^[a-zæøå][a-zæøå'\-]{1,29}$/i.test(token);
}

const WEEKDAY_TOKEN_PATTERN = "(?:mandag|tirsdag|onsdag|torsdag|fredag|lørdag|laurdag|søndag|monday|tuesday|wednesday|thursday|friday|saturday|sunday)";

function normalizeListItemToken(value) {
  let token = String(value || "")
    .toLowerCase()
    .replace(/\r\n/g, " ")
    .replace(/[ \t]+/g, " ")
    .trim();
  if (!token) return "";

  token = token
    .replace(/^[\-•*]\s*/, "")
    .replace(/^(?:og|and)\s+/i, "")
    .replace(/^(?:(?:jeg|vi)\s+skal\s+ha\s+(?:en|ei|et)?\s+)?(?:shopping\s*list|shoppinglist|grocery\s*list|hand(?:le)?list(?:e|en|a)|innkjøpsliste)\s*(?:[:\-]|\s+med)?\s*/i, "")
    .replace(/^(?:on\s+my\s+shopping\s+list|på\s+hand(?:le)?list(?:e|en|a))\s*[:,]?\s*/i, "")
    .replace(/^(?:det\s+vi\s+trenger\s+til\s+middag|what\s+we\s+need\s+for\s+dinner)\s*[:\-]?\s*/i, "")
    .replace(/^(?:for\s+(?:tomorrow|today|tonight)|today|tomorrow|tonight|i\s+morgen|i\s+dag|i\s+kveld|til\s+i\s+morgen|til\s+i\s+dag|til\s+i\s+kveld|for\s+i\s+morgen|for\s+i\s+dag|for\s+i\s+kveld)\s*[:\-]?\s*/i, "")
    .replace(/^(?:i\s+want|jeg\s+ønsker|jeg\s+vil\s+ha|jeg\s+trenger)\s+/i, "")
    .replace(/^(?:til\s+[a-zæøå][a-zæøå\-']{1,24})\s+(?:trenger|må\s+ha|need|we\s+need)\s+/i, "")
    .replace(/^(?:(?:jeg|vi)\s+)?(?:trenger|må\s+ha|skal\s+ha|må\s+kjøpe|kjøp|need|we\s+need|buy|get)\s+/i, "")
    .replace(/^med\s+/i, "")
    .replace(/[.,;:!?]+$/g, "")
    .trim();

  return token;
}

function isListHeadingInstructionFragment(value) {
  const raw = String(value || "").toLowerCase().replace(/[ \t]+/g, " ").trim();
  if (!raw) return false;
  return /^(?:shopping\s*list|shoppinglist|grocery\s*list|hand(?:le)?list(?:e|en|a)|innkjøpsliste)\s*[:\-]\s*(?:i\s+want|jeg\s+ønsker|jeg\s+vil\s+ha|vi\s+trenger|we\s+need)\b/.test(raw);
}

function normalizeListLookupKey(value) {
  let key = normalizeListItemToken(value);
  if (!key) return "";
  key = key
    .replace(/^(?:a|an|the|en|et|ei)\s+/i, "")
    .replace(/[ \t]+/g, " ")
    .trim();
  return key;
}

function extractNegatedListItemToken(value) {
  const token = String(value || "").trim();
  if (!token) return "";

  const negated = token.match(
    /^(?:men\s+)?(?:eh+|ehm+|øh+|øhm+|uh+|uhm+|um+|umm+)?\s*(?:(?:nei|no)\s+(?:(?:ikke|not)\s+)?)?(.+)$/i
  );
  if (!negated?.[1]) return "";

  const hasNegationCue = /^(?:men\s+)?(?:eh+|ehm+|øh+|øhm+|uh+|uhm+|um+|umm+)?\s*(?:nei|no)\b/i.test(token)
    || /^(?:ikke|not|uten|without)\b/i.test(token);
  if (!hasNegationCue) return "";

  return normalizeListItemToken(negated[1]);
}

function buildCorrectedListItems(content) {
  const rawItems = splitBulletItems(content);
  if (!rawItems.length) return [];

  const resolvedItems = [];
  const indexByKey = new Map();

  for (const rawItem of rawItems) {
    if (isListHeadingInstructionFragment(rawItem)) continue;
    const normalized = normalizeListItemToken(rawItem);
    if (!normalized) continue;

    const negatedTarget = extractNegatedListItemToken(normalized);
    if (negatedTarget) {
      const key = normalizeListLookupKey(negatedTarget);
      if (!key) continue;
      const existingIndex = indexByKey.get(key);
      if (typeof existingIndex === "number") {
        resolvedItems[existingIndex] = "";
        indexByKey.delete(key);
      }
      continue;
    }

    const key = normalizeListLookupKey(normalized);
    if (!key) continue;
    if (indexByKey.has(key)) continue;
    indexByKey.set(key, resolvedItems.length);
    resolvedItems.push(normalized);
  }

  return resolvedItems.filter(Boolean);
}

function applyListNegationCorrections(text) {
  let out = String(text || "");
  if (!out) return out;
  if (!/(?:nei|no)\s+(?:ikke|not)\b/i.test(out)) return out;

  const clauses = out.split(/\s*,\s*/);
  if (clauses.length < 2) return out;

  const kept = [...clauses];
  let changed = false;
  const negationPattern = /^(?:men\s+)?(?:eh+|ehm+|øh+|øhm+|uh+|uhm+|um+|umm+)?\s*(?:nei|no)\s+(?:ikke|not)\s+(.+)$/i;

  for (let i = 0; i < kept.length; i += 1) {
    const clause = String(kept[i] || "").trim();
    const match = clause.match(negationPattern);
    if (!match?.[1]) continue;

    const target = normalizeListItemToken(match[1]);
    if (!target) {
      kept[i] = "";
      changed = true;
      continue;
    }

    for (let j = i - 1; j >= 0; j -= 1) {
      if (normalizeListItemToken(kept[j]) === target) {
        kept[j] = "";
        changed = true;
        break;
      }
    }

    kept[i] = "";
    changed = true;
  }

  if (!changed) return out;

  out = kept
    .map((item) => String(item || "").trim())
    .filter(Boolean)
    .join(", ");

  out = out
    .replace(/\s+([,.;!?])/g, "$1")
    .replace(/([,;]){2,}/g, "$1")
    .replace(/[ \t]{2,}/g, " ")
    .trim();

  return out;
}

function applyInlineNoCorrections(text) {
  let out = String(text || "");
  if (!out) return out;

  // "klokken 8:00 nei klokken 9:00" -> "klokken 9:00"
  out = out.replace(
    /(\b(?:kl(?:okken)?\.?\s*)?\d{1,2}[.:]\d{2}\b)\s*(?:[,;.]?\s*)?(?:men\s+)?(?:nei|no)\s*(?:[,;.]?\s*)?(?:jeg mener|i mean)?\s*(?:at\s*)?((?:kl(?:okken)?\.?\s*)?\d{1,2}[.:]\d{2}\b)/ig,
    (_, __oldValue, newValue) => String(newValue).trim()
  );

  // "kl 7 nei kl 8" / "klokken 7 nei klokken 8" -> keep latest value
  out = out.replace(
    /(\b(?:kl(?:okken)?\.?\s*)?\d{1,2}(?:[.:]\d{2})?\b)\s*(?:[,;.]?\s*)?(?:men\s+)?(?:nei|no)\s*(?:[,;.]?\s*)?(?:jeg mener|i mean)?\s*(?:at\s*)?((?:kl(?:okken)?\.?\s*)?\d{1,2}(?:[.:]\d{2})?\b)/ig,
    (_, __oldValue, newValue) => String(newValue).trim()
  );

  // "5,4 millioner nei 5,3 millioner" -> "5,3 millioner"
  out = out.replace(
    /(\b\d+(?:[.,]\d+)?\s*(?:millioner?|milliarder?|kroner|kr|%)?\b)\s*(?:[,;.]?\s*)?(?:men\s+)?(?:nei|no)\s*(?:[,;.]?\s*)?(?:jeg mener|i mean)?\s*(\d+(?:[.,]\d+)?\s*(?:millioner?|milliarder?|kroner|kr|%)?\b)/ig,
    (_, __oldValue, newValue) => String(newValue).trim()
  );

  // "torsdag, ehh nei fredag" / "on thursday no friday" -> keep latest day value
  const weekdayCorrectionPattern = new RegExp(
    `(\\b(?:på\\s+|on\\s+)?${WEEKDAY_TOKEN_PATTERN}\\b)\\s*(?:[,;.]?\\s*)?(?:men\\s+)?(?:eh+|ehm+|øh+|øhm+|uh+|uhm+|um+|umm+)?\\s*(?:[,;.]?\\s*)?(?:nei|no)\\s*(?:[,;.]?\\s*)?(?:jeg\\s+mener|i\\s+mean)?\\s*((?:på\\s+|on\\s+)?${WEEKDAY_TOKEN_PATTERN}\\b)`,
    "ig"
  );
  out = out.replace(weekdayCorrectionPattern, (_, __oldValue, newValue) => String(newValue).trim());
  out = applyListNegationCorrections(out);

  return out;
}

function applySelfCorrections(text) {
  const out = applyInlineNoCorrections(String(text || "").replace(/\r\n/g, "\n").trim());
  if (!out) return out;

  const lower = out.toLowerCase();
  const cues = [
    "nei, jeg mener",
    "nei jeg mener",
    "eller nei",
    "rettere sagt",
    "no, i mean",
    "no i mean",
    "i mean"
  ];

  let cueIndex = -1;
  let cueText = "";
  for (const cue of cues) {
    const idx = lower.lastIndexOf(cue);
    if (idx > cueIndex) {
      cueIndex = idx;
      cueText = cue;
    }
  }
  if (cueIndex < 0) return out;

  const before = out.slice(0, cueIndex).trim().replace(/[,:;\-–—\s]+$/g, "").trim();
  let after = out.slice(cueIndex + cueText.length).trim();
  after = after.replace(/^[:;,.!?\-–—\s]+/g, "").trim();

  if (!before) return after || out;
  if (!after) return before;

  const timePattern = /\b(?:kl(?:okken)?\.?\s*)?\d{1,2}[.:]\d{2}\b/ig;
  const beforeTimes = [...before.matchAll(timePattern)];
  const afterTimes = [...after.matchAll(timePattern)];
  if (beforeTimes.length && afterTimes.length) {
    const replacement = String(afterTimes[afterTimes.length - 1][0]).trim();
    return replaceLastMatch(before, /\b(?:kl(?:okken)?\.?\s*)?\d{1,2}[.:]\d{2}\b/ig, replacement).trim();
  }

  const amountPattern = /\b\d+(?:[.,]\d+)?\s*(?:millioner?|milliarder?|kroner|kr|%)?\b/ig;
  const beforeAmounts = [...before.matchAll(amountPattern)];
  const afterAmounts = [...after.matchAll(amountPattern)];
  if (beforeAmounts.length && afterAmounts.length) {
    const replacement = String(afterAmounts[afterAmounts.length - 1][0]).trim();
    return replaceLastMatch(before, /\b\d+(?:[.,]\d+)?\s*(?:millioner?|milliarder?|kroner|kr|%)?\b/ig, replacement).trim();
  }

  const nameMatch = after.match(/^(?:til|for|to)?\s*([A-Za-zÆØÅæøå][A-Za-zÆØÅæøå'\-]{1,29})\b/);
  if (nameMatch) {
    const name = nameMatch[1];
    if (/^(Hei|Hi|Hello)\s+[^\n,!?]+/i.test(before)) {
      return before.replace(/^(Hei|Hi|Hello)\s+[^\n,!?]+/i, (_, g) => `${g} ${name}`).trim();
    }
  }

  return out;
}

function removeFillerWords(text) {
  let out = String(text || "").replace(/\r\n/g, "\n");
  if (!out) return out;

  const fillerPattern = /(^|[\s,.;:!?()\[\]{}"'`])(?:eh+|ehm+|øh+|øhm+|uh+|uhm+|um+|umm+|erm+|hmm+|mmm+)(?=$|[\s,.;:!?()\[\]{}"'`])/giu;
  for (let i = 0; i < 3; i += 1) {
    const next = out.replace(fillerPattern, (_, lead) => lead || "");
    if (next === out) break;
    out = next;
  }

  out = out
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\s+([,.;!?])/g, "$1")
    .replace(/([,.;!?]){2,}/g, "$1")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/\n{3,}/g, "\n\n");

  return out.trim();
}

function canonicalSignoffLine(line) {
  const key = String(line || "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .replace(/[,.;:!?]+$/g, "")
    .trim();

  switch (key) {
    case "med vennlig hilsen": return "Med vennlig hilsen,";
    case "vennlig hilsen": return "Vennlig hilsen,";
    case "hilsen": return "Hilsen,";
    case "mvh": return "Mvh,";
    case "best regards": return "Best regards,";
    case "regards": return "Regards,";
    case "best": return "Best,";
    case "sincerely": return "Sincerely,";
    default: return null;
  }
}

function isLikelyQuestionLine(line) {
  return /^(skal|kan|kunne|vil|har|hva|hvordan|hvor|hvem|hvilken|hvilke|when|what|why|how|can|could|would|will|do|did|are|is|should)\b/i.test(String(line || "").trim());
}

function isLikelyNameLine(line) {
  return /^[A-Za-zÆØÅæøå][A-Za-zÆØÅæøå'\- ]{0,40}$/.test(String(line || "").trim());
}

function capitalizeFirstLetter(line) {
  const value = String(line || "");
  return value.replace(/^([a-zæøå])/, (m) => m.toUpperCase());
}

function titleCaseWords(text) {
  return String(text || "")
    .split(/\s+/)
    .filter(Boolean)
    .map((token) => capitalizeFirstLetter(token.toLowerCase()))
    .join(" ");
}

function normalizeGreetingLine(line) {
  const trimmed = String(line || "").trim();
  const match = trimmed.match(/^(Hei|Hi|Hello|Dear)\s+([A-Za-zÆØÅæøå][A-Za-zÆØÅæøå'\-]*(?:\s+[A-Za-zÆØÅæøå][A-Za-zÆØÅæøå'\-]*){0,3}),?$/i);
  if (!match) return null;
  const greeting = capitalizeFirstLetter(String(match[1] || "").toLowerCase());
  const name = titleCaseWords(match[2] || "");
  if (!name) return null;
  return `${greeting} ${name},`;
}

function normalizeEmailLineCasingAndPunctuation(text) {
  const lines = String(text || "").replace(/\r\n/g, "\n").split("\n");
  const out = [];
  let previousLineWasSignoff = false;

  for (const rawLine of lines) {
    const trimmed = String(rawLine || "").trim();
    if (!trimmed) {
      out.push("");
      previousLineWasSignoff = false;
      continue;
    }

    const normalizedGreeting = normalizeGreetingLine(trimmed);
    if (normalizedGreeting) {
      out.push(normalizedGreeting);
      previousLineWasSignoff = false;
      continue;
    }

    const canonicalSignoff = canonicalSignoffLine(trimmed);
    if (canonicalSignoff) {
      out.push(canonicalSignoff);
      previousLineWasSignoff = true;
      continue;
    }

    if (previousLineWasSignoff) {
      const strippedNameCandidate = trimmed
        .replace(/^[,.;:!?\-–—\s]+/g, "")
        .trim();
      if (isLikelyNameLine(strippedNameCandidate)) {
        out.push(capitalizeFirstLetter(strippedNameCandidate.replace(/[,.;:!?]+$/g, "")));
        previousLineWasSignoff = false;
        continue;
      }
    }

    let normalized = capitalizeFirstLetter(trimmed);
    if (!/[.!?]$/.test(normalized) && isLikelyQuestionLine(normalized)) {
      normalized += "?";
    }

    out.push(normalized);
    previousLineWasSignoff = false;
  }

  return out.join("\n");
}

function normalizeEmailBody(text) {
  let out = String(text || "").replace(/\r\n/g, "\n").trim();
  if (!out) return out;

  out = out.replace(
    /^(Hei|Hi|Hello)\s+([^\n,!?]+?)(?:,)?\s+(?=[^\n])/i,
    (full, g, name) => {
      const maybeName = String(name).trim();
      const firstToken = maybeName.split(/\s+/)[0] || "";
      if (!isLikelyPersonNameToken(firstToken)) {
        return String(full);
      }
      return `${g} ${maybeName},\n\n`;
    }
  );

  out = out.replace(
    /\s+(Med vennlig hilsen|Vennlig hilsen|Hilsen|Mvh|Best regards|Regards|Best)\s*/i,
    "\n\n$1 "
  );

  out = out.replace(
    /\s+(Med vennlig hilsen|Vennlig hilsen|Hilsen|Mvh|Best regards|Regards|Best)\s*[.!?]?\s*$/i,
    "\n\n$1,"
  );

  out = out.replace(
    /\n\n(Med vennlig hilsen|Vennlig hilsen|Hilsen|Mvh|Best regards|Regards|Best)\s+([^\n]+)$/i,
    (_, signoff, name) => `\n\n${signoff},\n${String(name).trim().replace(/[.,;:!?]+$/, "")}`
  );

  out = out.replace(
    /\n\n(Med vennlig hilsen|Vennlig hilsen|Hilsen|Mvh|Best regards|Regards|Best)\s*[.!?]?\s*$/i,
    (_, signoff) => `\n\n${signoff},`
  );

  out = out.replace(
    /^(Hei|Hi|Hello)[^\n]*,\n(?!\n)/i,
    (m) => `${m}\n`
  );

  out = out
    .replace(/[ \t]+([,.;!?])/g, "$1")
    .replace(/([,.;!?])([^\s\n])/g, "$1 $2")
    .replace(/[ \t]+$/gm, "")
    .replace(/\n{3,}/g, "\n\n");

  out = out.replace(
    /\n\n(Med vennlig hilsen|Vennlig hilsen|Hilsen|Mvh|Best regards|Regards|Best)\s*,?\s*\n\s*([^\n]+)$/i,
    (_, signoff, name) => `\n\n${signoff},\n${String(name).trim().replace(/[.,;:!?]+$/, "")}`
  );

  out = normalizeEmailLineCasingAndPunctuation(out);

  return out.trim();
}

function basicPolish(text) {
  let out = String(text || "").replace(/\r\n/g, "\n").trim();
  if (!out) return out;

  out = out
    .replace(/[ \t]+/g, " ")
    .replace(/[ \t]+([,.;!?])/g, "$1")
    .replace(/([,.;!?])([^\s\n])/g, "$1 $2")
    .trim();

  if (/^[a-zæøå]/.test(out)) {
    out = out.charAt(0).toUpperCase() + out.slice(1);
  }
  if (!/[.!?]$/.test(out)) {
    out += ".";
  }
  return out;
}

function basicLiteralPolish(text) {
  return String(text || "")
    .replace(/\r\n/g, "\n")
    .replace(/[ \t]+([,.;!?])/g, "$1")
    .replace(/[ \t]+$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function localPolish(text, mode, interpretationLevel = "balanced") {
  if (interpretationLevel === "literal") {
    return basicLiteralPolish(text);
  }

  const corrected = applySelfCorrections(text);
  const withoutFillers = removeFillerWords(corrected);
  const clean = basicPolish(withoutFillers);
  if (!clean) return "";

  if (mode === "email_subject") {
    return clean.replace(/[.!?]+$/g, "");
  }

  if (mode === "email_body") {
    let out = clean;
    out = normalizeEmailBody(out);
    return out;
  }

  return clean;
}

function isGreetingLine(line) {
  return /^(Hei|Hi|Hello|Dear)\b/i.test(String(line || "").trim());
}

function isSignoffLine(line) {
  return /^(Med vennlig hilsen|Vennlig hilsen|Hilsen|Mvh|Best regards|Regards|Best|Sincerely),?$/i.test(String(line || "").trim());
}

function applyStyleHeuristics(text, style, mode) {
  let out = String(text || "").replace(/\r\n/g, "\n").trim();
  if (!out || style === "clean" || style === "formal") return out;

  if (mode === "email_subject") {
    if (style === "casual") {
      return out.replace(/[.!]+$/g, "");
    }
    if (style === "excited" && !/[!?]$/.test(out)) {
      return `${out}!`;
    }
    return out;
  }

  const lines = out.split("\n");

  if (style === "casual") {
    out = lines.map((line) => {
      const trimmed = line.trimEnd();
      if (!trimmed) return trimmed;
      if (trimmed.endsWith("?") || trimmed.endsWith("!")) return trimmed;
      if (isSignoffLine(trimmed)) return trimmed;
      return trimmed.replace(/\.$/, "");
    }).join("\n");
    return out.replace(/\n{3,}/g, "\n\n").trim();
  }

  if (style === "excited") {
    let boosted = false;
    out = lines.map((line) => {
      const trimmed = line.trimEnd();
      if (!trimmed) return trimmed;
      if (isGreetingLine(trimmed) || isSignoffLine(trimmed)) return trimmed;
      if (!boosted && /\.$/.test(trimmed)) {
        boosted = true;
        return trimmed.replace(/\.$/, "!");
      }
      if (!boosted && !/[!?]$/.test(trimmed) && /[A-Za-zÆØÅæøå]/.test(trimmed)) {
        boosted = true;
        return `${trimmed}!`;
      }
      return trimmed;
    }).join("\n");

    if (!boosted && !/[!?]$/.test(out) && mode !== "email_body") {
      out = `${out}!`;
    }
    return out.replace(/\n{3,}/g, "\n\n").trim();
  }

  return out;
}

function normalizePunctuationArtifacts(text) {
  return String(text || "")
    .replace(/\.!/g, "!")
    .replace(/!\./g, "!")
    .replace(/\?\./g, "?")
    .replace(/,\./g, ",")
    .replace(/[ \t]+$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

const BULLET_COMMAND_PREFIX_RE = /^\s*(?:(?:lag|skriv|sett\s+opp|gjør\s+om\s+til|formater|make|turn|format)\s+(?:dette\s+)?(?:som\s+)?(?:bullet(?:\s|-)?points?|bulletpoints?|punktliste|punkter|liste)|(?:bullet(?:\s|-)?points?|bulletpoints?|punktliste|punkter|liste))\s*[:,-]?\s*/i;
const BULLET_COMMAND_HINT_RE = /\b(?:lag|skriv|sett\s+opp|gjør\s+om\s+til|formater|make|turn|format)\b[\s\S]{0,48}\b(?:bullet(?:\s|-)?points?|bulletpoints?|punktliste|punkter|liste)\b/i;
const BULLET_IMPLICIT_LIST_TRIGGER_RE = /\b(?:trenger|må\s+ha|skal\s+ha|må\s+kjøpe|kjøp|hand(?:le)?list(?:e|en|a)|ingredienser|we\s+need|need|shopping\s+list|shoppinglist|buy|get)\b/i;
const BULLET_COMPACT_LIST_STRONG_TRIGGER_RE = /\b(?:on\s+my\s+shopping\s+list|shopping\s*list|shoppinglist|grocery\s*list|for\s+dinner|hand(?:le)?list(?:e|en|a)|innkjøpsliste|til\s+middag|ingredienser|ingredients)\b/i;
const LIST_HEADING_NO_RE = "Handleliste";
const LIST_HEADING_EN_RE = "Shopping list";
const DINNER_LIST_HEADING_NO_RE = "Det vi trenger til middag:";
const DINNER_LIST_HEADING_EN_RE = "What we need for dinner:";
const SHOPPING_LIST_HEADING_TRIGGER_RE = /\b(?:on\s+my\s+shopping\s+list|shopping\s*list|shoppinglist|grocery\s*list|for\s+dinner|hand(?:le)?list(?:e|en|a)|innkjøpsliste|til\s+middag|må\s+kjøpe|kjøp|buy|trenger\s+vi|vi\s+trenger|we\s+need|need)\b/i;
const POINT_MARKER_RE = /\b(?:punkt|point)\s*(?:\d+|en|ett|to|tre|fire|fem|seks|sju|syv|åtte|ni|ti|one|two|three|four|five|six|seven|eight|nine|ten)\s*[:.)-]?\s*/ig;
const PARENTHESIS_COMMAND_RE = /\b(?:åpen|open|start|venstre|left)\s+parentes\b|\b(?:lukk|lukk|slutt|close|høyre|right)\s+parentes\b|\b(?:i\s+parentes|in\s+parentheses)\b/i;
const SPOKEN_PUNCTUATION_HINT_RE = /\b(?:skråstrek|skraastrek|slash|slahs|slashtegn|backslash|bakoverstrek|komma|comma|punktum|period|full\s*stop|kolon|colon|semikolon|semicolon|utropstegn|exclamation\s*(?:mark|point)|spørsmålstegn|sporsmalstegn|question\s*mark|apostrof|apostrophe|anførselstegn|anforselstegn|sitattegn|quotation\s*mark|quote|bindestrek|hyphen|dash|en\s*dash|em\s*dash|ellipse|ellipsis|tre\s+prikker|three\s+dots|parentes|parenthesis|bracket|brace|krøllparentes|krollparentes)\b/i;
const SPOKEN_EMOJI_ALIASES = [
  { pattern: /\b(?:emoji\s+)?smilefjes\b/gi, emoji: "🙂" },
  { pattern: /\b(?:emoji\s+)?smiley\b/gi, emoji: "🙂" },
  { pattern: /\b(?:emoji\s+)?gladfjes\b/gi, emoji: "😀" },
  { pattern: /\b(?:emoji\s+)?winkefjes\b/gi, emoji: "😉" },
  { pattern: /\b(?:emoji\s+)?hjerte\b/gi, emoji: "❤️" },
  { pattern: /\b(?:emoji\s+)?tommel\s*opp\b/gi, emoji: "👍" },
  { pattern: /\b(?:emoji\s+)?tommel\s*ned\b/gi, emoji: "👎" },
  { pattern: /\b(?:emoji\s+)?latterfjes\b/gi, emoji: "😂" },
  { pattern: /\b(?:emoji\s+)?gråtefjes\b/gi, emoji: "😢" },
  { pattern: /\b(?:emoji\s+)?rakett\b/gi, emoji: "🚀" },
  { pattern: /\b(?:emoji\s+)?ild\b/gi, emoji: "🔥" },
  { pattern: /\b(?:emoji\s+)?hake\b/gi, emoji: "✅" }
];
const SPOKEN_PUNCTUATION_ALIASES = [
  { pattern: /\b(?:skråstrek|skraastrek|slash|slahs|slashtegn)\b/gi, mark: "/" },
  { pattern: /\b(?:backslash|bakoverstrek)\b/gi, mark: "\\" },
  { pattern: /\b(?:komma|comma)\b/gi, mark: "," },
  { pattern: /\b(?:punktum|period|full\s*stop)\b/gi, mark: "." },
  { pattern: /\b(?:kolon|colon)\b/gi, mark: ":" },
  { pattern: /\b(?:semikolon|semicolon)\b/gi, mark: ";" },
  { pattern: /\b(?:utropstegn|exclamation\s*(?:mark|point))\b/gi, mark: "!" },
  { pattern: /\b(?:spørsmålstegn|sporsmalstegn|question\s*mark)\b/gi, mark: "?" },
  { pattern: /\b(?:apostrof|apostrophe)\b/gi, mark: "'" },
  { pattern: /\b(?:anførselstegn|anforselstegn|sitattegn|quotation\s*mark|quote)\b/gi, mark: "\"" },
  { pattern: /\b(?:bindestrek|hyphen)\b/gi, mark: "-" },
  { pattern: /\b(?:dash|en\s*dash|em\s*dash)\b/gi, mark: " – " },
  { pattern: /\b(?:ellipse|ellipsis|tre\s+prikker|three\s+dots)\b/gi, mark: "…" },
  { pattern: /\b(?:åpen|open)\s+(?:square\s+)?bracket\b/gi, mark: "[" },
  { pattern: /\b(?:lukk|close)\s+(?:square\s+)?bracket\b/gi, mark: "]" },
  { pattern: /\b(?:åpen|open)\s+(?:curly\s+)?brace\b/gi, mark: "{" },
  { pattern: /\b(?:lukk|close)\s+(?:curly\s+)?brace\b/gi, mark: "}" }
];

function hasExplicitBulletCommand(text) {
  // List handling is intentionally disabled.
  return false;
}

function splitBulletItems(content) {
  const source = String(content || "").trim();
  if (!source) return [];

  let working = source
    .replace(/\r\n/g, "\n")
    .replace(POINT_MARKER_RE, "\n")
    .replace(/\s*\n+\s*/g, "\n")
    .trim();

  const headingPrefixMatch = working.match(
    /^(?:handleliste|innkjøpsliste|shopping\s*list|shoppinglist|grocery\s*list|det\s+vi\s+trenger\s+til\s+middag|what\s+we\s+need\s+for\s+dinner)\s*[:\-]\s*(.+)$/i
  );
  if (headingPrefixMatch?.[1]) {
    working = String(headingPrefixMatch[1]).trim();
  }

  let parts = [];
  if (working.includes("\n")) {
    parts = working.split(/\n+/);
  } else if (/[;,]/.test(working)) {
    parts = working.split(/\s*[;,]\s*/);
  } else if (/\b(?:og|and)\b/i.test(working)) {
    parts = working.split(/\s+\b(?:og|and)\b\s+/i);
  } else {
    parts = [working];
  }

  const expanded = [];
  for (const part of parts) {
    const andParts = String(part || "").split(/\s+\b(?:og|and)\b\s+/i);
    if (andParts.length > 1) {
      expanded.push(...andParts);
    } else {
      expanded.push(part);
    }
  }

  return expanded
    .map((item) => item.replace(/^[\-•*]\s*/, "").trim())
    .filter(Boolean);
}

function stripListLeadPhrases(text) {
  let out = String(text || "").trim();
  if (!out) return out;

  out = out.replace(
    /^\s*(?:shopping\s*list|shoppinglist|grocery\s*list|hand(?:le)?list(?:e|en|a)|innkjøpsliste)\s*[:\-]\s*(?:i\s+want|jeg\s+ønsker|jeg\s+vil\s+ha|vi\s+trenger|we\s+need)\s+[^,\n;]+(?:\s*[,;]\s*|$)/i,
    ""
  );
  out = out.replace(
    /^\s*(?:(?:jeg|vi)\s+skal\s+ha\s+(?:en|ei|et)?\s+)?(?:shopping\s*list|shoppinglist|grocery\s*list|hand(?:le)?list(?:e|en|a)|innkjøpsliste)\s*(?:[:,]|\s+med)?\s*/i,
    ""
  );
  out = out.replace(
    /^\s*(?:on\s+my\s+shopping\s+list|på\s+hand(?:le)?list(?:e|en|a))\s*[:,]?\s*/i,
    ""
  );
  out = out.replace(
    /^\s*(?:det\s+vi\s+trenger\s+til\s+middag|what\s+we\s+need\s+for\s+dinner)\s*[:\-]?\s*/i,
    ""
  );
  out = out.replace(
    /^\s*(?:(?:jeg|vi)\s+skal\s+ha\s+(?:en|ei|et)?\s+)?(?:til\s+[^\s,.;:!?]+(?:\s+[^\s,.;:!?]+){0,2}\s+)?(?:trenger\s+vi|vi\s+trenger|we\s+need|need|kjøp|buy|get|hand(?:le)?liste(?:n)?|ingredienser(?:\s+til\s+[^\s,.;:!?]+)?)\s*(?:med\s+)?/i,
    ""
  );
  out = out.replace(/^\s*med\s+/i, "");
  out = out.replace(/^\s*(?:vi\s+trenger|trenger\s+vi|we\s+need|need)\s+/i, "");
  out = out.replace(/^\s*(?:i\s+want|jeg\s+ønsker|jeg\s+vil\s+ha|jeg\s+trenger)\s+/i, "");
  return out.trim();
}

function isLikelySimpleListItem(text) {
  const value = String(text || "").trim().toLowerCase();
  if (!value) return false;

  const words = value.split(/\s+/).filter(Boolean);
  if (words.length < 1 || words.length > 4) return false;
  if (/^(?:å|to|ellers|if|hvis|fordi)\b/.test(value)) return false;
  if (/^(?:jeg|vi|du|dere|han|hun|de|it|we|you|they)\b/.test(value)) return false;
  if (/\b(?:er|blir|ble|skal|må|kan|kunne|vil|ville|har|hadde|får|fikk|is|are|was|were|be|being|have|has|had|will|would|should|could)\b/.test(value)) {
    return false;
  }
  return true;
}

function isListContextOnlyItem(text) {
  const value = String(text || "").trim().toLowerCase();
  if (!value) return false;
  return /^(?:for\s+(?:today|tomorrow|tonight)|today|tomorrow|tonight|i\s+dag|i\s+morgen|i\s+kveld|til\s+i\s+dag|til\s+i\s+morgen|til\s+i\s+kveld|for\s+i\s+dag|for\s+i\s+morgen|for\s+i\s+kveld)$/.test(value);
}

function resolveListHeadingLanguage(heading, outputText, preferredLanguage = "") {
  let out = String(heading || "").trim();
  if (!out) return out;

  const preferred = String(preferredLanguage || "").trim().toLowerCase();
  const wantsEnglish = preferred.startsWith("en");
  const wantsNorwegian = preferred.startsWith("nb") || preferred.startsWith("nn") || preferred.startsWith("no");
  const englishSignal = /\b(?:for|tomorrow|today|shopping|ingredients|we need|milk|eggs|bread)\b/i.test(String(outputText || ""));

  const shouldUseEnglish = wantsEnglish || (!wantsNorwegian && englishSignal);
  if (shouldUseEnglish) {
    if (out === LIST_HEADING_NO_RE) return LIST_HEADING_EN_RE;
    if (out === DINNER_LIST_HEADING_NO_RE) return DINNER_LIST_HEADING_EN_RE;
    return out;
  }

  if (wantsNorwegian) {
    if (out === LIST_HEADING_EN_RE) return LIST_HEADING_NO_RE;
    if (out === DINNER_LIST_HEADING_EN_RE) return DINNER_LIST_HEADING_NO_RE;
  }

  return out;
}

function applyListTimingQualifier(heading, sourceText, outputText, preferredLanguage = "") {
  const base = String(heading || "").trim();
  if (!base) return base;
  // Keep headings short and stable; timing phrases often belong in the body context.
  return base;
}

function stripLeadingListTimingQualifier(text) {
  return String(text || "")
    .replace(
      /^\s*(?:for\s+(?:tomorrow|today|tonight)|today|tomorrow|tonight|i\s+morgen|i\s+dag|i\s+kveld|til\s+i\s+morgen|til\s+i\s+dag|til\s+i\s+kveld|for\s+i\s+morgen|for\s+i\s+dag|for\s+i\s+kveld)\b[\s,:-]*/i,
      ""
    )
    .trim();
}

function buildCompactListItems(content) {
  let source = String(content || "").replace(/\r\n/g, " ").replace(/[ \t]+/g, " ").trim();
  if (!source) return [];
  if (/[;,]/.test(source) || /\b(?:og|and)\b/i.test(source) || source.includes("\n")) return [];

  source = stripLeadingListTimingQualifier(source);
  if (!source) return [];

  const ingredientMatch = source.match(/^(.*?\b(?:ingredients?|ingredienser)\b)\s+(.+)$/i);
  if (ingredientMatch?.[1] && ingredientMatch?.[2]) {
    const head = normalizeListItemToken(ingredientMatch[1]);
    const tailItems = ingredientMatch[2]
      .split(/\s+/)
      .map((token) => normalizeListItemToken(token))
      .filter((token) => token && !isListContextOnlyItem(token));
    const compact = [];
    if (head && !isListContextOnlyItem(head)) compact.push(head);
    compact.push(...tailItems);
    return compact;
  }

  const tokens = source
    .split(/\s+/)
    .map((token) => normalizeListItemToken(token))
    .filter((token) => token && !isListContextOnlyItem(token));
  if (tokens.length < 3 || tokens.length > 8) return [];
  if (!tokens.every((token) => isLikelySimpleListItem(token))) return [];
  return tokens;
}

function buildImplicitBulletList(text) {
  // List handling is intentionally disabled.
  return "";
}

function applyBulletFormattingCommand(text) {
  const source = String(text || "").replace(/\r\n/g, "\n").trim();
  // List handling is intentionally disabled.
  return source;
}

function applySpokenParenthesisCommands(text) {
  let out = String(text || "");
  if (!out) return out;

  out = out
    .replace(/\b(?:åpen|open|start|venstre|left)\s+(?:parentes|parenthesis)\b/gi, "(")
    .replace(/\b(?:lukk|slutt|close|høyre|right)\s+(?:parentes|parenthesis)\b/gi, ")")
    .replace(/\b(?:i\s+parentes|in\s+parentheses)\s*[:,]?\s*([^\n,.!?;]+)/gi, "($1)");

  out = out
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")")
    .replace(/([^\s(])\(/g, "$1 (")
    .replace(/\)([^\s.,!?;:\)\]])/g, ") $1")
    .replace(/[ \t]+([,.;!?])/g, "$1")
    .replace(/[ \t]{2,}/g, " ");

  return out;
}

function replaceSpokenEmojiAliases(text) {
  let out = String(text || "");
  if (!out) return out;

  for (const { pattern, emoji } of SPOKEN_EMOJI_ALIASES) {
    out = out.replace(pattern, emoji);
  }

  out = out
    .replace(/[ \t]+([,.;!?])/g, "$1")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  return out;
}

function replaceSpokenPunctuationAliases(text) {
  let out = String(text || "");
  if (!out) return out;

  for (const { pattern, mark } of SPOKEN_PUNCTUATION_ALIASES) {
    out = out.replace(pattern, mark);
  }

  out = out
    .replace(/([\p{L}\p{N}])\s*\/\s*([\p{L}\p{N}])/gu, "$1/$2")
    .replace(/([\p{L}\p{N}])\s*\\\s*([\p{L}\p{N}])/gu, "$1\\$2")
    .replace(/[ \t]+([,.;:!?])/g, "$1")
    .replace(/([,.;:!?])([^\s\n)\]}])/g, "$1 $2")
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  return out;
}

function applySpokenFormattingPostprocess(text) {
  let out = String(text || "");
  if (!out) return out;

  out = applySpokenParenthesisCommands(out);
  out = replaceSpokenPunctuationAliases(out);
  out = replaceSpokenEmojiAliases(out);
  return out;
}

function inferRequestedListHeading(sourceText) {
  const source = String(sourceText || "").trim();
  if (!source) return "";
  if (!SHOPPING_LIST_HEADING_TRIGGER_RE.test(source)) return "";
  if (/\bfor\s+dinner\b/i.test(source)) {
    return DINNER_LIST_HEADING_EN_RE;
  }
  if (/\btil\s+middag\b/i.test(source)) {
    return DINNER_LIST_HEADING_NO_RE;
  }
  if (/\b(?:shopping\s*list|shoppinglist|grocery\s*list|on\s+my\s+shopping\s+list)\b/i.test(source)) {
    return LIST_HEADING_EN_RE;
  }
  return LIST_HEADING_NO_RE;
}

function hasSpokenFormattingCommandHints(text) {
  const source = String(text || "").trim();
  if (!source) return false;
  if (hasExplicitBulletCommand(source)) return true;
  if (PARENTHESIS_COMMAND_RE.test(source)) return true;
  if (SPOKEN_PUNCTUATION_HINT_RE.test(source)) return true;
  return false;
}

function extractEmojis(text) {
  return String(text || "").match(/\p{Extended_Pictographic}/gu) || [];
}

function sourceAllowsEmojiInsertion(sourceText) {
  const source = String(sourceText || "").trim();
  if (!source) return false;
  if (extractEmojis(source).length) return true;

  // Emoji are allowed only when the user explicitly asked for them.
  return /\b(?:emoji|smilefjes|smiley|gladfjes|winkefjes|hjerte|tommel\s*opp|tommel\s*ned|latterfjes|gråtefjes|rakett|ild|hake)\b/i.test(source);
}

function stripUnrequestedEmojis(sourceText, outputText) {
  if (sourceAllowsEmojiInsertion(sourceText)) {
    return String(outputText || "").trim();
  }

  return String(outputText || "")
    .replace(/[\p{Extended_Pictographic}\uFE0F\u200D]/gu, "")
    .replace(/[ \t]+([,.;!?])/g, "$1")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function preserveRequestedEmojis(sourceText, outputText) {
  const requested = Array.from(new Set(extractEmojis(sourceText)));
  if (!requested.length) return String(outputText || "").trim();

  let out = String(outputText || "").trim();
  if (!out) {
    return requested.join(" ");
  }
  if (extractEmojis(out).length > 0) {
    return out;
  }

  for (const emoji of requested) {
    if (!out.includes(emoji)) {
      out = `${out} ${emoji}`.trim();
    }
  }
  return out;
}

function preserveRequestedBulletLayout(sourceText, outputText) {
  // List handling is intentionally disabled.
  return String(outputText || "").trim();
}

function preserveRequestedListHeading(sourceText, outputText, preferredLanguage = "") {
  // List handling is intentionally disabled.
  return String(outputText || "").trim();
}

function tidyBulletListOutput(text) {
  // List handling is intentionally disabled.
  const out = String(text || "").trim();
  if (!out) return out;

  const lines = out
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  if (!lines.length) return "";

  const listPrefixRe = /^(?:[-•*]\s+|\d+[.)]\s+)/;
  const listLikeCount = lines.filter((line) => listPrefixRe.test(line)).length;
  if (!listLikeCount) return out;

  const normalized = lines.map((line) => line.replace(listPrefixRe, "").trim()).filter(Boolean);
  if (!normalized.length) return "";

  return normalized.join("\n");
}

function extractFirstParentheticalSegment(text) {
  const match = String(text || "").match(/\(([^()]{1,180})\)/);
  return match ? String(match[1] || "").trim() : "";
}

function preserveRequestedParentheses(sourceText, outputText) {
  const source = String(sourceText || "").trim();
  let out = String(outputText || "").trim();
  if (!source || !out) return out;
  if (!source.includes("(") || !source.includes(")")) return out;
  if (/\([^()]+\)/.test(out)) return out;

  const parenthetical = extractFirstParentheticalSegment(source);
  if (!parenthetical) return out;

  const tokenPattern = new RegExp(`\\b${escapeRegExp(parenthetical)}\\b`, "i");
  if (tokenPattern.test(out)) {
    out = out.replace(tokenPattern, (segment) => `(${segment})`);
    return out;
  }

  return `(${parenthetical}) ${out}`.trim();
}

function normalizeTargetLanguage(raw) {
  const v = String(raw || "").trim();
  return v || DEFAULT_TARGET_LANGUAGE;
}

function canonicalTimeToken(token) {
  const normalized = String(token || "")
    .toLowerCase()
    .replace(/kl(?:okken)?\.?\s*/g, "")
    .trim();
  const match = normalized.match(/^(\d{1,2})(?:[.:](\d{2}))?$/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = match[2] ? Number(match[2]) : 0;
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function extractCanonicalTimes(text) {
  const matches = String(text || "").match(/\b(?:kl(?:okken)?\.?\s*)?\d{1,2}(?:[.:]\d{2})\b/ig) || [];
  return matches
    .map((value) => canonicalTimeToken(value))
    .filter(Boolean);
}

function hasCriticalTimeDrift(inputText, outputText) {
  const inputTimes = extractCanonicalTimes(inputText);
  if (!inputTimes.length) return false;
  const outputTimes = extractCanonicalTimes(outputText);
  if (!outputTimes.length) return false;
  const inputLatest = inputTimes[inputTimes.length - 1];
  const outputLatest = outputTimes[outputTimes.length - 1];
  return inputLatest !== outputLatest;
}

function isLikelyWrongForTarget(text, targetLanguage) {
  const t = String(text || "");
  const target = String(targetLanguage || "").toLowerCase();
  const lower = t.toLowerCase();
  const hasPolishChars = /[ąćęłńóśźż]/i.test(t);
  const hasPolishWords = /\b(cześć|czy|masz|ochotę|obiad|jutro|pozdrawiam|dzień)\b/i.test(lower);
  const hasPlaceholder = /\[[^\]]{1,32}\]/.test(t);

  if (target.startsWith("nb") || target.startsWith("nn") || target.startsWith("no")) {
    return hasPolishChars || hasPolishWords || hasPlaceholder;
  }

  if (target.startsWith("en")) {
    const hasNorwegianWords = /\b(hei|hilsen|vennlig|med vennlig hilsen|mvh|handleliste|innkjøpsliste|ingredienser|trenger|ikke|i\s+morgen|i\s+dag|i\s+kveld|til\s+middag)\b/i.test(lower);
    return hasPolishChars || hasPolishWords || hasNorwegianWords || hasPlaceholder;
  }

  return false;
}

function removeBracketPlaceholders(text) {
  return String(text || "")
    .replace(/\[(your|din|ditt)?\s*name\]/ig, "")
    .replace(/\[[^\]]{1,32}\]/g, "");
}

function collapseRepeatedTail(text) {
  const lines = String(text || "").replace(/\r\n/g, "\n").split("\n");
  const n = lines.length;
  for (let k = Math.floor(n / 2); k >= 2; k--) {
    const a = lines.slice(n - 2 * k, n - k).join("\n").trim();
    const b = lines.slice(n - k).join("\n").trim();
    if (a && b && a.toLowerCase() === b.toLowerCase()) {
      return lines.slice(0, n - k).join("\n").trim();
    }
  }
  return String(text || "").trim();
}

function preferTargetLanguageSection(text, targetLanguage) {
  let out = String(text || "").replace(/\r\n/g, "\n").trim();
  if (!out) return out;

  const target = String(targetLanguage || "").toLowerCase();
  const lines = out.split("\n");

  if (target.startsWith("en")) {
    const hasNorwegian = /\b(hei|hilsen|vennlig|med vennlig hilsen|mvh)\b/i.test(out);
    const englishStart = lines.findIndex((line) => /^\s*(hi|hello|dear)\b/i.test(line));
    if (hasNorwegian && englishStart > 0) {
      out = lines.slice(englishStart).join("\n").trim();
    }
  }

  if (target.startsWith("nb") || target.startsWith("nn") || target.startsWith("no")) {
    const hasEnglish = /\b(hi|hello|dear|best regards|regards)\b/i.test(out);
    const norwegianStart = lines.findIndex((line) => /^\s*hei\b/i.test(line));
    if (hasEnglish && norwegianStart > 0) {
      out = lines.slice(norwegianStart).join("\n").trim();
    }
  }

  return out;
}

function sanitizeModelOutput(text, mode, targetLanguage, interpretationLevel = "balanced") {
  let out = String(text || "").replace(/\r\n/g, "\n").trim();
  if (!out) return out;

  if (interpretationLevel !== "literal") {
    out = applySelfCorrections(out);
    out = removeFillerWords(out);
  }
  if (/\b(?:No|Nei)\.\s*$/i.test(out) && /[.!?]/.test(out.replace(/\b(?:No|Nei)\.\s*$/i, ""))) {
    out = out.replace(/\s*\b(?:No|Nei)\.\s*$/i, "").trim();
  }
  out = removeBracketPlaceholders(out);
  out = collapseRepeatedTail(out);
  out = preferTargetLanguageSection(out, targetLanguage);
  out = out.replace(/[ \t]+$/gm, "").replace(/\n{3,}/g, "\n\n").trim();

  if (mode === "email_body") {
    out = normalizeEmailBody(out);
  }
  return out;
}

function finalizePolishOutput(text, { style, mode, interpretationLevel }) {
  const locallyPolished = localPolish(text, mode, interpretationLevel);
  const styled = interpretationLevel === "literal"
    ? locallyPolished
    : applyStyleHeuristics(locallyPolished, style, mode);
  const withSpokenFormatting = applySpokenFormattingPostprocess(styled);
  return normalizePunctuationArtifacts(withSpokenFormatting);
}

function isBrowserBundle(bundleId) {
  return bundleId === "com.google.Chrome"
    || bundleId === "com.apple.Safari"
    || bundleId === "com.microsoft.edgemac"
    || bundleId === "company.thebrowser.Browser"
    || bundleId === "org.mozilla.firefox";
}

function looksLikeEmailBodyText(text) {
  const raw = String(text || "").replace(/\r\n/g, "\n").trim();
  if (!raw) return false;

  const normalized = raw.toLowerCase();
  const lines = raw
    .split("\n")
    .map((line) => String(line || "").trim())
    .filter(Boolean);
  if (!lines.length) return false;

  const firstLine = lines[0] || "";
  const firstTwo = lines.slice(0, 2).join("\n");
  const hasGreeting = /^(hei|hello|hi|dear|kjære)\b/i.test(firstLine) || /(^|\n)\s*(hei|hello|hi|dear|kjære)\b/i.test(firstTwo);
  const hasSignoff = /\b(med vennlig hilsen|vennlig hilsen|hilsen|mvh|best regards|kind regards|regards|sincerely)\b/i.test(normalized);
  const hasHeaderLine = lines.slice(0, 8).some((line) => /^(fra|from|til|to|emne|subject|cc|bcc)\s*:/i.test(line));
  const hasEmailAddress = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i.test(raw);
  const hasThreadSubject = /^(re|sv|fw|fwd)\s*:/i.test(firstLine);
  const paragraphCount = raw.split(/\n{2,}/).map((chunk) => chunk.trim()).filter(Boolean).length;

  if (hasSignoff) return true;
  if (hasHeaderLine && (hasEmailAddress || lines.length >= 3)) return true;
  if (hasGreeting && (paragraphCount >= 2 || hasEmailAddress || lines.length >= 3)) return true;
  if (hasThreadSubject && (hasEmailAddress || hasGreeting || hasSignoff)) return true;

  return false;
}

function inferMode(requestedMode, bundleId, url, ctx, fieldMeta, text) {
  const mode = String(requestedMode || "generic");
  const lowerBundle = String(bundleId || "").toLowerCase();
  const lowerUrl = String(url || "").toLowerCase();
  const lowerCtx = String(ctx || "").toLowerCase();
  const lowerMeta = String(fieldMeta || "").toLowerCase();
  const looksEmailByContent = looksLikeEmailBodyText(text);
  const blob = `${lowerBundle} ${lowerUrl} ${lowerCtx} ${lowerMeta}`;

  const subjectHints = ["subject", "emne", "tema", "betreff", "title"];
  const hasSubjectHint = subjectHints.some((hint) => blob.includes(hint));
  const strongEmailHints = [
    "gmail", "mail.google.com", "outlook",
    "compose", "message body", "new message", "skriv e-post",
    "email", "e-post", "mottaker", "mottakere", "recipient", "recipients"
  ];
  const hasStrongEmailHint = strongEmailHints.some((hint) => blob.includes(hint));
  const isMailUrl = lowerUrl.includes("mail.google.com")
    || lowerUrl.includes("outlook.live.com")
    || lowerUrl.includes("outlook.office.com");

  if (mode === "email_body" || mode === "email_subject") {
    // Safety net: if client misclassifies a browser field as email, downgrade to generic.
    if (isBrowserBundle(bundleId) && !isMailUrl && !hasStrongEmailHint && !looksEmailByContent) {
      return "generic";
    }
    return mode;
  }
  if (mode !== "generic") {
    if (looksEmailByContent) return "email_body";
    return mode;
  }

  if (looksEmailByContent) {
    return "email_body";
  }

  const emailHints = [
    "gmail", "mail.google.com", "outlook",
    "compose", "message body", "new message", "skriv e-post",
    "email", "e-post", "mottaker", "mottakere", "recipient", "recipients"
  ];
  const hasEmailHint = emailHints.some((hint) => blob.includes(hint));

  if (blob.includes("mail.google.com") || blob.includes("gmail")) {
    return hasSubjectHint ? "email_subject" : "email_body";
  }

  if (blob.includes("outlook.live.com") || blob.includes("outlook.office.com") || blob.includes("outlook")) {
    return hasSubjectHint ? "email_subject" : "email_body";
  }

  if (isBrowserBundle(bundleId) && hasEmailHint) {
    return hasSubjectHint ? "email_subject" : "email_body";
  }

  return mode;
}

function countWords(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return 0;
  return trimmed.split(/\s+/).length;
}

function resolvePolishMaxTokens(mode, text, targetLanguageForced, interpretationLevel) {
  const normalizedMode = String(mode || "generic").trim().toLowerCase();
  const normalizedInterpretationLevel = normalizeInterpretationLevel(interpretationLevel);
  const textLength = String(text || "").trim().length;

  // Short translations do not need the broader drafting token budget.
  if (targetLanguageForced && textLength <= 80) {
    const literalBudget = Math.max(32, Math.min(64, OPENAI_MAX_TOKENS_POLISH_TRANSLATE));
    return normalizedInterpretationLevel === "meaning"
      ? Math.max(literalBudget, 96)
      : literalBudget;
  }
  if (targetLanguageForced && textLength <= 220) {
    return normalizedInterpretationLevel === "meaning"
      ? Math.max(OPENAI_MAX_TOKENS_POLISH_TRANSLATE, 112)
      : OPENAI_MAX_TOKENS_POLISH_TRANSLATE;
  }

  if (normalizedInterpretationLevel === "meaning") {
    if (normalizedMode === "email_subject") {
      return Math.max(OPENAI_MAX_TOKENS_POLISH_SUBJECT, 72);
    }
    if (normalizedMode === "email_body") {
      return Math.max(OPENAI_MAX_TOKENS_POLISH_EMAIL_BODY, OPENAI_MAX_TOKENS_POLISH_MEANING);
    }
    return OPENAI_MAX_TOKENS_POLISH_MEANING;
  }

  if (normalizedMode === "email_subject") return OPENAI_MAX_TOKENS_POLISH_SUBJECT;
  if (normalizedMode === "email_body") return OPENAI_MAX_TOKENS_POLISH_EMAIL_BODY;

  if ((normalizedMode === "generic" || normalizedMode === "chat_message") && textLength <= POLISH_LOCAL_FASTPATH_MAX_CHARS) {
    return OPENAI_MAX_TOKENS_POLISH_SHORT;
  }
  return OPENAI_MAX_TOKENS_POLISH;
}

function buildPolishSystemPrompt({
  mode,
  style,
  lang,
  url,
  ctx,
  dictionaryRule,
  targetLanguageForced,
  interpretationLevel
}) {
  const selfCorrectionRule = "Self-correction precedence: if the user revises themselves (for example 'torsdag ... nei fredag', 'eh nei', 'nei, jeg mener', 'no, I mean', or 'melk, nei ikke melk'), keep only the latest corrected detail and remove negated items. Remove superseded alternatives, false starts, and correction cue words.";

  if (targetLanguageForced) {
    const translationRule = interpretationLevel === "literal"
      ? "Translate as literally as possible. Stay close to the source wording and structure unless a direct translation would be unclear."
      : interpretationLevel === "meaning"
        ? "Translate for intended meaning and the best possible phrasing. Resolve fragmented speech, implied punctuation, and rough wording into the clearest natural translation."
        : "Preserve meaning, names, numbers, and formatting.";

    const spokenFormattingRule = "If the dictated text includes explicit formatting commands, apply them naturally and remove command words from the final output. Convert spoken emoji words like 'smilefjes' to emoji only when those words are explicitly spoken. Never add emoji unless explicitly requested or already present in the input. Spoken punctuation words should become symbols (for example 'slash/slahs' -> '/', 'komma' -> ',', 'punktum' -> '.'). Spoken parenthesis commands ('åpen parentes', 'lukk parentes', 'i parentes') should be rendered with parentheses.";
    const uncertaintyRule = interpretationLevel === "meaning"
      ? "If key details are ambiguous, keep the wording general and do not guess specifics."
      : "";
    return `Translate the user's text into ${lang}. ${translationRule} ${POLISH_BASE_GUARDRAIL} ${POLISH_FACT_GUARDRAIL} ${selfCorrectionRule} ${uncertaintyRule} ${spokenFormattingRule} Do not add commentary, alternatives, or extra context. Return exactly one final translation only as plain text. ${dictionaryRule}`;
  }

  const langRule = `Output language must be ${lang}. Do not translate into any other language.`;
  const modeRule = MODE_RULES[mode] || MODE_RULES.generic;
  const styleRule = interpretationLevel === "literal"
    ? "Keep style changes to an absolute minimum."
    : (STYLE_RULES[style] || STYLE_RULES.clean);
  const interpretationRule = INTERPRETATION_RULES[interpretationLevel] || INTERPRETATION_RULES.balanced;

  let contextBlock = "";
  if (mode !== "generic") {
    if (url) contextBlock += `\nURL: ${url}`;
    if (ctx) contextBlock += `\nContext: ${ctx}`;
  }

  const noGreetingRule = mode === "email_body"
    ? ""
    : "No added greetings/sign-offs unless already present.";
  const singleDraftRule = "Return exactly one final draft only. Never include alternatives, translations, duplicate versions, or placeholders like [Your Name].";
  const correctionRule = selfCorrectionRule;
  const fidelityRule = interpretationLevel === "meaning"
    ? "You may infer the intended structure of fragmented speech, but do not invent new facts, topics, names, commitments, or questions that are not grounded in the input."
    : "Do not invent new facts, topics, requests, names, or questions. Rewrite only what is explicitly in the input.";
  const uncertaintyRule = interpretationLevel === "meaning"
    ? "If key details are missing or uncertain, keep them open-ended and avoid specific assumptions."
    : "";
  const recipientRule = mode === "email_body"
    ? "If multiple recipient names appear, keep the latest explicit recipient name and use it consistently."
    : "";
  const spokenFormattingRule = "If the dictated text contains explicit formatting commands, obey them and remove the command words from the final output. Convert spoken emoji words like 'smilefjes' to emoji only when those words are explicitly spoken. Never add emoji unless explicitly requested or already present in the input. Spoken punctuation words like 'slash/slahs', 'komma', 'punktum' -> '/', ',', '.'. Spoken parenthesis commands ('åpen parentes', 'lukk parentes', 'i parentes') -> proper parentheses.";

  return `Polish punctuation and phrasing, keep meaning. ${modeRule} ${styleRule} ${interpretationRule} ${langRule} ${POLISH_BASE_GUARDRAIL} ${POLISH_FACT_GUARDRAIL} ${noGreetingRule} ${singleDraftRule} ${correctionRule} ${fidelityRule} ${uncertaintyRule} ${recipientRule} ${spokenFormattingRule} ${dictionaryRule} Return JSON only: {"language":"...","text":"..."}${contextBlock}`;
}

function shouldUsePolishLocalFastpath({ mode, style, targetLanguageForced, targetLanguage, text, interpretationLevel }) {
  if (!POLISH_LOCAL_FASTPATH_ENABLED) return false;
  if (targetLanguageForced) return false;

  const normalizedInterpretationLevel = normalizeInterpretationLevel(interpretationLevel);
  if (normalizedInterpretationLevel === "meaning") return false;

  const normalizedMode = String(mode || "generic").trim().toLowerCase();
  if (normalizedMode !== "generic" && normalizedMode !== "chat_message" && normalizedMode !== "note") {
    return false;
  }
  if (
    normalizedInterpretationLevel !== "literal"
    && String(style || "clean").trim().toLowerCase() !== "clean"
  ) return false;

  const clean = String(text || "").trim();
  if (!clean) return false;
  if (hasSpokenFormattingCommandHints(clean)) return false;
  if (clean.length > POLISH_LOCAL_FASTPATH_MAX_CHARS) return false;
  if (countWords(clean) > POLISH_LOCAL_FASTPATH_MAX_WORDS) return false;
  if (/[\n\r]/.test(clean)) return false;
  if (/\b(oversett|translate)\b/i.test(clean)) return false;
  if (isLikelyWrongForTarget(clean, targetLanguage)) return false;

  return true;
}

const LANGUAGE_TARGET_ALIASES = [
  ["en-US", ["english", "engelsk"]],
  ["nb-NO", ["norwegian", "norsk", "bokmal", "bokmål"]],
  ["nn-NO", ["nynorsk"]],
  ["sv-SE", ["swedish", "svensk"]],
  ["da-DK", ["danish", "dansk"]],
  ["fi-FI", ["finnish", "finsk"]],
  ["is-IS", ["icelandic", "islandsk"]],
  ["de-DE", ["german", "tysk"]],
  ["nl-NL", ["dutch", "nederlands", "nederlandsk"]],
  ["fr-FR", ["french", "fransk"]],
  ["es-ES", ["spanish", "spansk"]],
  ["pt-PT", ["portuguese", "portugisisk"]],
  ["it-IT", ["italian", "italiensk"]],
  ["pl-PL", ["polish", "polsk"]],
  ["cs-CZ", ["czech", "tsjekkisk"]],
  ["sk-SK", ["slovak", "slovakisk"]],
  ["hu-HU", ["hungarian", "ungarsk"]],
  ["ro-RO", ["romanian", "rumensk"]],
  ["bg-BG", ["bulgarian", "bulgarsk"]],
  ["hr-HR", ["croatian", "kroatisk"]],
  ["sr-RS", ["serbian", "serbisk"]],
  ["sl-SI", ["slovenian", "slovensk", "slovensk språk"]],
  ["el-GR", ["greek", "gresk"]],
  ["uk-UA", ["ukrainian", "ukrainsk"]],
  ["ru-RU", ["russian", "russisk"]],
  ["tr-TR", ["turkish", "tyrkisk"]],
  ["ar", ["arabic", "arabisk"]],
  ["he-IL", ["hebrew", "hebraisk"]],
  ["fa-IR", ["persian", "farsi", "persisk"]],
  ["hi-IN", ["hindi"]],
  ["bn-BD", ["bengali", "bangla", "bengalsk"]],
  ["ur-PK", ["urdu"]],
  ["pa-IN", ["punjabi", "panjabi", "punjabi språk"]],
  ["gu-IN", ["gujarati", "gujarati språk"]],
  ["mr-IN", ["marathi"]],
  ["ta-IN", ["tamil"]],
  ["te-IN", ["telugu"]],
  ["ml-IN", ["malayalam"]],
  ["kn-IN", ["kannada"]],
  ["zh-CN", ["chinese", "mandarin", "kinesisk", "mandarin chinese"]],
  ["ja-JP", ["japanese", "japansk"]],
  ["ko-KR", ["korean", "koreansk"]],
  ["th-TH", ["thai", "thailandsk"]],
  ["vi-VN", ["vietnamese", "vietnamesisk"]],
  ["id-ID", ["indonesian", "indonesisk", "bahasa indonesia"]],
  ["ms-MY", ["malay", "malaysisk", "bahasa melayu"]],
  ["tl-PH", ["tagalog", "filipino"]],
  ["sw-KE", ["swahili"]],
  ["am-ET", ["amharic", "amharisk"]],
  ["zu-ZA", ["zulu"]],
  ["af-ZA", ["afrikaans"]],
  ["ca-ES", ["catalan", "katalansk"]],
  ["lt-LT", ["lithuanian", "litauisk"]],
  ["lv-LV", ["latvian", "latvisk"]],
  ["et-EE", ["estonian", "estisk"]]
];

const LANGUAGE_ALIAS_LOOKUP = new Map(
  LANGUAGE_TARGET_ALIASES.flatMap(([code, aliases]) =>
    aliases.map((alias) => [String(alias).toLowerCase(), code])
  )
);

const SORTED_LANGUAGE_ALIASES = [...LANGUAGE_ALIAS_LOOKUP.keys()]
  .sort((a, b) => b.length - a.length);

function instructionRequestsLanguageChange(instruction) {
  const normalized = String(instruction || "").trim().toLowerCase();
  if (!normalized) return false;

  if (inferExplicitTargetLanguageFromInstruction(normalized)) {
    return true;
  }

  const cues = [
    /\btranslate\b/,
    /\btranslation\b/,
    /\btranslate this\b/,
    /\btranslate it\b/,
    /\btranslate to\b/,
    /\boversett\b/,
    /\boversette\b/,
    /\boversett dette\b/,
    /\boversett til\b/,
    /\bpå engelsk\b/,
    /\btil engelsk\b/,
    /\bin english\b/,
    /\bto english\b/,
    /\bpå norsk\b/,
    /\btil norsk\b/,
    /\bin norwegian\b/,
    /\bto norwegian\b/
  ];

  return cues.some((pattern) => pattern.test(normalized));
}

function inferExplicitTargetLanguageFromInstruction(instruction) {
  const normalized = String(instruction || "")
    .toLowerCase()
    .replace(/[.,!?;:()[\]{}"']/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (!normalized) return null;

  const padded = ` ${normalized} `;
  const targetPrefixes = [" to ", " into ", " in ", " til ", " på "];
  const matches = new Set();

  for (const alias of SORTED_LANGUAGE_ALIASES) {
    const paddedAlias = ` ${alias} `;
    for (const prefix of targetPrefixes) {
      if (padded.includes(`${prefix}${alias} `)) {
        return LANGUAGE_ALIAS_LOOKUP.get(alias) || null;
      }
    }

    const pattern = new RegExp(`(^|\\s)${escapeRegExp(alias)}(?=\\s|$)`, "i");
    if (pattern.test(normalized)) {
      matches.add(LANGUAGE_ALIAS_LOOKUP.get(alias));
      if (padded.includes(paddedAlias)) {
        continue;
      }
    }
  }

  const compactMatches = [...matches].filter(Boolean);
  if (compactMatches.length === 1 && /\b(translate|translation|oversett|oversette)\b/i.test(normalized)) {
    const [singleMatch] = compactMatches;
    if (singleMatch) {
      return singleMatch;
    }
  }

  return null;
}

function normalizeReplyMemories(input) {
  if (!Array.isArray(input)) return [];

  return input
    .map((item) => {
      const title = String(item?.title || "").replace(/\s+/g, " ").trim();
      const triggers = String(item?.triggers || "").replace(/\s+/g, " ").trim();
      const sourceText = String(item?.sourceText || "").replace(/\s+/g, " ").trim();
      const guidance = String(item?.guidance || "").replace(/\s+/g, " ").trim();
      if (!title || !guidance) return null;
      return {
        title: title.slice(0, 80),
        triggers: triggers.slice(0, 160),
        sourceText: sourceText.slice(0, 500),
        guidance: guidance.slice(0, 320)
      };
    })
    .filter(Boolean)
    .slice(0, 3);
}

function classifyDraftReplyContext(text) {
  const raw = String(text || "");
  const normalized = raw
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();

  const looksLikeInvitation = /\b(bryllup|wedding|invitation|invite|rsvp|ceremony|ceremoni|feiring)\b/.test(normalized);
  const looksLikeSupport = /\b(bestilling|ordre|order|ordrenummer|tracking|shipment|delivery|levering|mottatt|received|refund|support|kundeservice|status|pakke)\b/.test(normalized);
  const looksLikeEmail = looksLikeEmailBodyText(raw) ||
    /\b(takk for at du handler|thank you for your order|we confirm that we have received your order)\b/.test(normalized);

  if (looksLikeSupport) {
    return {
      kind: "support",
      minTokens: 260,
      extraRule: "Write a complete customer-facing reply email. Acknowledge the message, clearly state the user's issue or request, and ask for a status update or next step when helpful. If the spoken instruction states a problem (for example not receiving an item), incorporate that problem into the reply as the main point."
    };
  }

  if (looksLikeInvitation) {
    return {
      kind: "invitation",
      minTokens: 240,
      extraRule: "Write a complete polite reply to the invitation. Thank the sender, state the user's answer clearly, and keep the tone warm, natural, and socially appropriate."
    };
  }

  if (looksLikeEmail) {
    return {
      kind: "email",
      minTokens: 240,
      extraRule: "Write a complete email-style reply. Include a natural greeting when appropriate, then the actual response the user wants to send, and keep it concise but complete."
    };
  }

  return {
    kind: "generic",
    minTokens: 220,
    extraRule: "Write a complete send-ready response, not a fragment. The final text should read like the actual message the user wants to send."
  };
}

function normalizeEmailReplySignoffMode(value) {
  const normalized = String(value || "").trim();
  if (normalized === "none" || normalized === "custom" || normalized === "autoName") {
    return normalized;
  }
  return "autoName";
}

function normalizeEmailReplyGreetingMode(value) {
  const normalized = String(value || "").trim();
  if (normalized === "firstName" || normalized === "fullName") {
    return normalized;
  }
  return "firstName";
}

function looksLikeEmailDisplayName(value) {
  const cleaned = String(value || "")
    .replace(/\s+/g, " ")
    .replace(/^['"]|['"]$/g, "")
    .trim();
  if (!cleaned || cleaned.length > 60 || /\d/.test(cleaned)) {
    return false;
  }

  const lower = cleaned.toLowerCase();
  const blockedTerms = [
    "send", "sende", "subject", "emne", "recipient", "mottaker", "compose",
    "new message", "ny melding", "inbox", "innboks", "cc", "bcc", "to",
    "til", "sans serif", "flowspeak",
    "bruk", "bruker", "bruk app i fokus", "use focused app", "focused app", "focus", "fokus"
  ];
  if (blockedTerms.some((term) => lower === term || lower.includes(term))) {
    return false;
  }

  const parts = cleaned.split(/\s+/).filter(Boolean);
  if (!parts.length || parts.length > 4) {
    return false;
  }

  const namePartPattern = /^[\p{L}'-]+$/u;
  const capitalizedParts = parts.filter((part) => namePartPattern.test(part) && /^[\p{Lu}]/u.test(part)).length;
  if (parts.length === 1) {
    return capitalizedParts === 1;
  }
  return capitalizedParts >= 2;
}

function extractEmailReplyMetadata(text) {
  const raw = String(text || "");
  const lines = raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const headerLines = lines.slice(0, 10);

  let senderDisplayName = "";
  for (const line of headerLines) {
    const directMatch = line.match(/^"?([^"<]{2,120}?)"?\s*<[^>]+>$/);
    if (directMatch?.[1]) {
      senderDisplayName = directMatch[1].trim();
      break;
    }

    const prefixedMatch = line.match(/^(?:from|fra):\s*"?([^"<]{2,120}?)"?\s*(?:<[^>]+>)?$/i);
    if (prefixedMatch?.[1]) {
      senderDisplayName = prefixedMatch[1].trim();
      break;
    }

    if (!senderDisplayName && looksLikeEmailDisplayName(line)) {
      senderDisplayName = line;
      break;
    }
  }

  const cleanedDisplayName = senderDisplayName
    .replace(/\s+/g, " ")
    .replace(/^['"]|['"]$/g, "")
    .trim();
  const nameParts = cleanedDisplayName.split(/\s+/).filter(Boolean);
  const greetingName = nameParts.length ? nameParts[0] : "";

  return {
    senderDisplayName: cleanedDisplayName,
    greetingName
  };
}

function normalizeDraftReplyInstruction(instruction) {
  const trimmed = String(instruction || "").replace(/\s+/g, " ").trim();
  if (!trimmed) return trimmed;

  // Treat short "summarize" commands as summarization tasks, not literal reply points.
  const summaryKeyword = /\b(oppsummer(?:ing)?|oppsumer(?:ing)?|summarize|summarise|summary|sum up|tl;dr|tldr)\b/i;
  const summaryFormattingHint = /\b(punkt|punkter|bullet|liste|list)\b/i;
  const veryShortSummaryHint = /\b(kort|kortfattet|short|brief|kjapt|raskt)\b/i;
  const summaryCommandOnly = /^(?:kan du\s+|please\s+)?(?:kort\s+)?(?:oppsummer(?:ing)?|oppsumer(?:ing)?|summarize|summarise|summary|sum up|tl;dr|tldr)(?:\s+i\s+(?:punkt(?:er)?|bullet(?: points?)?|liste|list))?\.?$/i;
  if (
    summaryKeyword.test(trimmed) &&
    (summaryCommandOnly.test(trimmed) || trimmed.split(/\s+/).filter(Boolean).length <= 4 || summaryFormattingHint.test(trimmed))
  ) {
    return veryShortSummaryHint.test(trimmed)
      ? "Write a clearly much shorter summary of the incoming message context in the same language. Keep only the most essential points, do not restate sentence-by-sentence, and do not add new facts. Output one short sentence when possible (max two short sentences)."
      : "Write a clearly shorter summary of the incoming message context in the same language. Keep only key points, avoid sentence-by-sentence restatement, and do not add new facts. Output 1-2 short sentences.";
  }

  const explicitPointMatch = trimmed.match(
    /^(?:reply|respond|write|draft|say|tell|answer|svar|svare|skriv|si)\b.*?\b(?:that|at)\b\s+(.+)$/i
  );
  if (explicitPointMatch?.[1]) {
    const point = explicitPointMatch[1].trim();
    if (point) {
      return `Write a complete polite reply that clearly communicates this point: ${point}`;
    }
  }

  const alreadyReplyLike = /\b(reply|respond|write|draft|answer|svar|svare|skriv|besvar)\b/i.test(trimmed);
  if (alreadyReplyLike) {
    return trimmed;
  }

  // Very short instructions (for example: "snart", "nei", "ja", "kan ikke") should be
  // treated as strict intent points, not as room for model elaboration.
  const shortWordCount = trimmed.split(/\s+/).filter(Boolean).length;
  if (shortWordCount <= 3 && trimmed.length <= 40) {
    return `Write a complete polite reply that communicates only this exact point and does not add extra facts: ${trimmed}`;
  }

  const standaloneMessagePoint = /\b(i\b|i'm|im\b|i’ve|i've|my\b|mine\b|jeg\b|min\b|mitt\b|har ikke|have not|haven't|did not|didn't|kan ikke|cannot|can't|won't|vil ikke|ikke fått|not received|still waiting|fortsatt ikke)\b/i.test(trimmed);
  if (standaloneMessagePoint) {
    return `Write a complete polite reply that clearly communicates this point: ${trimmed}`;
  }

  return trimmed;
}

function instructionRequestsEmailForm(instruction) {
  const normalized = String(instruction || "").toLowerCase().replace(/\s+/g, " ").trim();
  if (!normalized) return false;
  const hasEmailWord = /\b(e-?post|email|mail)\b/.test(normalized);
  const hasComposeWord = /\b(svar|svare|reply|respond|draft|skriv|write)\b/.test(normalized);
  return hasEmailWord && hasComposeWord;
}

function instructionRequestsSummary(instruction) {
  const normalized = String(instruction || "").toLowerCase().replace(/\s+/g, " ").trim();
  if (!normalized) return false;
  return /\b(oppsummer(?:ing)?|oppsumer(?:ing)?|summarize|summarise|summary|sum up|tl;dr|tldr)\b/.test(normalized);
}

function instructionRequestsVeryShortSummary(instruction) {
  const normalized = String(instruction || "").toLowerCase().replace(/\s+/g, " ").trim();
  if (!normalized || !instructionRequestsSummary(normalized)) return false;
  return /\b(kort|kortfattet|kortere|brief|short|concise|kjapt|raskt)\b/.test(normalized);
}

function instructionRequestsBulletSummary(instruction) {
  // List output is intentionally disabled.
  return false;
}

function instructionRequestsShorten(instruction) {
  const normalized = String(instruction || "").toLowerCase().replace(/\s+/g, " ").trim();
  if (!normalized) return false;
  return /\b(gjør\s+kortere|kortere|forkort|shorten|shorter|condense|compress|stram\s+opp)\b/.test(normalized);
}

function splitIntoSummaryUnits(text) {
  const source = String(text || "").replace(/\r\n/g, "\n").trim();
  if (!source) return [];

  const bulletLines = source
    .split(/\n+/)
    .map((line) => line.trim())
    .filter((line) => /^\s*[-•*]\s+/.test(line))
    .map((line) => line.replace(/^\s*[-•*]\s+/, "").trim())
    .filter(Boolean);
  if (bulletLines.length) return bulletLines;

  return source
    .split(/(?<=[.!?])\s+|\n+/)
    .map((part) => part.trim())
    .filter(Boolean);
}

function localSummarizeText(text, { bullets = false } = {}) {
  const units = splitIntoSummaryUnits(text);
  if (!units.length) return String(text || "").trim();

  const unique = [];
  const seen = new Set();
  for (const unit of units) {
    const key = unit.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(unit);
  }

  const picked = unique.slice(0, 4);
  if (!picked.length) return String(text || "").trim();

  if (bullets) {
    return picked.map((item) => `- ${item}`).join("\n");
  }

  return picked.slice(0, 2).join(" ");
}

function localShortenText(text) {
  const source = String(text || "").trim();
  if (!source) return source;

  const words = source.split(/\s+/).filter(Boolean);
  if (words.length <= 14) return source;

  const targetWordCount = Math.max(14, Math.min(80, Math.round(words.length * 0.6)));
  const units = splitIntoSummaryUnits(source);
  let kept = [];
  let usedWords = 0;

  for (const unit of units) {
    const unitWords = unit.split(/\s+/).filter(Boolean);
    if (!unitWords.length) continue;
    if (usedWords + unitWords.length > targetWordCount && kept.length) break;
    kept.push(unit);
    usedWords += unitWords.length;
    if (usedWords >= targetWordCount) break;
  }

  if (!kept.length) {
    kept = [words.slice(0, targetWordCount).join(" ")];
  }

  let out = kept.join(" ").trim();
  if (out.length < source.length) {
    out = out.replace(/[.,;:!?]*$/, "").trim();
    if (out && !/[.!?…]$/.test(out)) out = `${out}…`;
  }
  return out;
}

function wordCount(text) {
  return String(text || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .length;
}

function trimToWordLimit(text, maxWords) {
  const safeMax = Math.max(1, Math.floor(Number(maxWords) || 0));
  const words = String(text || "").trim().split(/\s+/).filter(Boolean);
  if (words.length <= safeMax) return String(text || "").trim();
  const trimmed = words.slice(0, safeMax).join(" ").replace(/[.,;:!?]*$/, "").trim();
  return trimmed ? `${trimmed}…` : "";
}

function enforceSummaryBrevity({ sourceText, summaryText, strict = false }) {
  const source = String(sourceText || "").trim();
  let summary = String(summaryText || "").trim();
  if (!source || !summary) return summary;

  const sourceWords = wordCount(source);
  const summaryWords = wordCount(summary);
  if (sourceWords < 10 || summaryWords === 0) return summary;

  let maxWordsByRatio = Math.max(
    strict ? 9 : 10,
    Math.floor(sourceWords * (strict ? 0.40 : 0.52))
  );
  // Avoid over-compressing short texts where key details can be dropped too easily.
  if (strict && sourceWords <= 24) {
    maxWordsByRatio = Math.max(maxWordsByRatio, Math.floor(sourceWords * 0.65));
  }
  const maxWords = strict
    ? Math.min(maxWordsByRatio, 26)
    : Math.min(maxWordsByRatio, 46);
  const currentRatio = summaryWords / Math.max(1, sourceWords);
  const needsCompaction = (
    summaryWords > maxWords
    || currentRatio > (strict ? 0.62 : 0.78)
  );
  if (!needsCompaction) return summary;

  const locallyShortened = localShortenText(summary).trim();
  if (wordCount(locallyShortened) < summaryWords) {
    summary = locallyShortened;
  }
  if (wordCount(summary) > maxWords) {
    summary = trimToWordLimit(summary, maxWords);
  }
  return summary.trim();
}

function buildLocalRewriteFallbackText({
  instruction,
  sourceText,
  rewriteMode,
  preferredLanguage
}) {
  const rewriteRawFormattingSource = `${instruction}\n${sourceText}`;
  const rewriteFormattedSource = applySpokenFormattingPostprocess(rewriteRawFormattingSource);
  let out = String(sourceText || "").trim();
  if (!out) return out;

  if (instructionRequestsSummary(instruction)) {
    out = localSummarizeText(out, { bullets: instructionRequestsBulletSummary(instruction) });
  } else if (instructionRequestsShorten(instruction)) {
    out = localShortenText(out);
  }

  out = normalizePunctuationArtifacts(applySpokenFormattingPostprocess(out));
  if (rewriteMode === "email_body") {
    out = normalizeEmailBody(out);
  }
  out = preserveRequestedBulletLayout(rewriteRawFormattingSource, out);
  out = preserveRequestedListHeading(rewriteRawFormattingSource, out, preferredLanguage);
  out = preserveRequestedParentheses(rewriteFormattedSource, out);
  out = preserveRequestedEmojis(rewriteFormattedSource, out);
  out = stripUnrequestedEmojis(rewriteFormattedSource, out);
  out = tidyBulletListOutput(out);
  return out.trim();
}

function escapeRegExp(value) {
  return String(value || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function handlePolish(body, requestSignal) {
  try {
    if (requestSignal?.aborted) {
      return { status: 499, json: { error: "Client closed request." } };
    }

    const requestStartedAt = Date.now();
    const timings = {
      preprocessMs: 0,
      modelMs: 0,
      postprocessMs: 0,
      totalMs: 0,
      modelAttempts: []
    };

    const text = String(body?.text || "").trim();
    if (!text) return { status: 400, json: { error: "Missing text." } };
    if (text.length > 8000) return { status: 413, json: { error: "Too long." } };

    const requestedMode = String(body?.mode || "generic");
    const style = "clean";
    const interpretationLevel = normalizeInterpretationLevel(body?.interpretationLevel);
    const bundleId = String(body?.bundleId || "");
    const appName = String(body?.appName || "");
    const lang = normalizeTargetLanguage(body?.targetLanguage);
    const targetLanguageForced = body?.targetLanguageForced === true;
    const ctx  = String(body?.fieldContext || "").trim().slice(-220);
    const url  = String(body?.browserURL || "").trim();
    const axDescription = String(body?.axDescription || "");
    const axHelp = String(body?.axHelp || "");
    const axTitle = String(body?.axTitle || "");
    const axPlaceholder = String(body?.axPlaceholder || "");
    const fieldMeta = [appName, axDescription, axHelp, axTitle, axPlaceholder].join(" ");
    const mode = inferMode(requestedMode, bundleId, url, ctx, fieldMeta, text);
    const dictionary = getRequestDictionary(body);
    const preparedInput = interpretationLevel === "literal"
      ? text
      : applySelfCorrections(text);
    const correctedInput = applyDictionaryReplacements(preparedInput, dictionary);
    const commandAwareInput = applySpokenFormattingPostprocess(correctedInput);

    console.log(
      "📨 mode:",
      requestedMode,
      "->",
      mode,
      "| style:",
      style,
      "| interpretation:",
      interpretationLevel,
      "| lang:",
      lang,
      "| urlHost:",
      safePreview(url ? (() => {
        try {
          return new URL(url).host || "";
        } catch {
          return "";
        }
      })() : ""),
      "| forcedLang:",
      targetLanguageForced,
      "| ctxChars:",
      ctx.length
    );
    if (dictionary.terms.length || dictionary.replacements.length) {
      console.log("📚 dictionary(active): terms", dictionary.terms.length, "| replacements", dictionary.replacements.length);
    }

    const dictionaryRule = buildDictionaryPromptClause(dictionary);
    const system = buildPolishSystemPrompt({
      mode,
      style,
      lang,
      url,
      ctx,
      dictionaryRule,
      targetLanguageForced,
      interpretationLevel
    });
    timings.preprocessMs = Date.now() - requestStartedAt;

    let language = lang;
    let finalText = finalizePolishOutput(commandAwareInput, {
      style,
      mode,
      interpretationLevel
    });
    let usedFallback = false;
    let usedLocalFastpath = false;

    if (shouldUsePolishLocalFastpath({
      mode,
      style,
      targetLanguageForced,
      targetLanguage: lang,
      text: correctedInput,
      interpretationLevel
    })) {
      usedLocalFastpath = true;
    } else if (!hasOpenAI) {
      usedFallback = true;
      console.warn("⚠️ OPENAI_API_KEY missing; using local fallback.");
    } else {
      const modelStartedAt = Date.now();
      try {
        const { response, attempts } = await requestModelDraft({
          system,
          user: commandAwareInput,
          requestSignal,
          maxTokens: resolvePolishMaxTokens(
            mode,
            commandAwareInput,
            targetLanguageForced,
            interpretationLevel
          ),
          wantsJsonOutput: !targetLanguageForced
        });
        timings.modelAttempts = attempts;
        timings.modelMs = Date.now() - modelStartedAt;
        const postprocessStartedAt = Date.now();

        const raw = response?.choices?.[0]?.message?.content || "";
        const modelText = targetLanguageForced
          ? String(raw || "").trim()
          : (() => {
              let parsed;
              try { parsed = JSON.parse(raw); }
              catch { parsed = { language: "unknown", text: raw }; }
              return String(parsed.text || "").trim();
            })();
        if (!modelText) {
          usedFallback = true;
        } else {
          const modelOut = sanitizeModelOutput(
            modelText,
            mode,
            lang,
            interpretationLevel
          );
          const normalizedModelOut = finalizePolishOutput(
            applyDictionaryReplacements(modelOut, dictionary),
            {
              style,
              mode,
              interpretationLevel
            }
          );

          if (hasCriticalTimeDrift(commandAwareInput, normalizedModelOut)) {
            usedFallback = true;
            console.warn("⚠️ model changed corrected time; using local fallback.");
          } else if (isLikelyWrongForTarget(normalizedModelOut, lang)) {
            usedFallback = true;
            console.warn("⚠️ language mismatch from model; using local fallback.");
          } else {
            language = lang;
            finalText = normalizedModelOut;
          }
        }
        timings.postprocessMs = Date.now() - postprocessStartedAt;
      } catch (modelErr) {
        if (requestSignal?.aborted) {
          return { status: 499, json: { error: "Client closed request." } };
        }
        usedFallback = true;
        timings.modelMs = Date.now() - modelStartedAt;
        if (Array.isArray(modelErr?.attempts)) {
          timings.modelAttempts = modelErr.attempts;
        }
        console.error("POLISH MODEL ERROR:", modelErr?.message);
      }
    }

    finalText = preserveRequestedBulletLayout(correctedInput, finalText);
    finalText = preserveRequestedListHeading(correctedInput, finalText, lang);
    finalText = preserveRequestedParentheses(commandAwareInput, finalText);
    finalText = preserveRequestedEmojis(commandAwareInput, finalText);
    finalText = stripUnrequestedEmojis(commandAwareInput, finalText);
    finalText = tidyBulletListOutput(finalText);
    timings.totalMs = Date.now() - requestStartedAt;
    const retryCount = Math.max(0, (timings.modelAttempts?.length || 0) - 1);
    console.log(
      "✅ ut:",
      safePreview(finalText, 80),
      usedLocalFastpath ? "[local-fastpath]" : (usedFallback ? "[fallback]" : ""),
      "| chars:",
      finalText.length
    );
    console.log("⏱️ timings:", JSON.stringify({
      preprocessMs: timings.preprocessMs,
      modelMs: timings.modelMs,
      postprocessMs: timings.postprocessMs,
      totalMs: timings.totalMs,
      retries: retryCount
    }));

    return {
      status: 200,
      json: {
        language,
        text: finalText,
        appliedMode: mode,
        appliedStyle: style,
        fallback: usedFallback,
        localFastpath: usedLocalFastpath,
        timings: {
          preprocessMs: timings.preprocessMs,
          modelMs: timings.modelMs,
          postprocessMs: timings.postprocessMs,
          totalMs: timings.totalMs,
          retries: retryCount
        }
      }
    };
  } catch (err) {
    console.error("POLISH ERROR:", err?.message);
    return { status: 500, json: { error: "Server error.", details: err?.message } };
  }
}

async function handleRewrite(body, requestSignal) {
  const requestStartedAt = Date.now();
  const timings = {
    preprocessMs: 0,
    modelMs: 0,
    postprocessMs: 0,
    totalMs: 0,
    modelAttempts: []
  };
  let instruction = "";
  let lang = DEFAULT_TARGET_LANGUAGE;
  let style = "clean";
  let correctedInput = "";
  let effectiveOutputLanguage = DEFAULT_TARGET_LANGUAGE;
  let allowsLanguageChange = false;
  let draftReplyFromContext = false;
  let replyMemories = [];
  let requestedRewriteMode = "generic";
  let effectiveRewriteMode = "generic";
  let emailReplyGreetingMode = "firstName";
  let emailReplySignoffMode = "autoName";
  let emailReplySignoffText = "";
  let emailRecipientHint = "";
  let explicitTargetLanguage = null;
  let usedFallback = false;

  try {
    if (requestSignal?.aborted) {
      return { status: 499, json: { error: "Client closed request." } };
    }

    const text = String(body?.text || "").trim();
    if (!text) return { status: 400, json: { error: "Missing text." } };
    if (text.length > 10_000) return { status: 413, json: { error: "Too long." } };

    instruction = String(body?.instruction || "").replace(/\s+/g, " ").trim();
    if (!instruction) return { status: 400, json: { error: "Missing instruction." } };
    if (instruction.length > 320) return { status: 413, json: { error: "Instruction too long." } };

    if (!hasOpenAI) {
      return { status: 503, json: { error: "Rewrite requires OPENAI_API_KEY." } };
    }

    lang = normalizeTargetLanguage(body?.targetLanguage);
    style = "clean";
    draftReplyFromContext = body?.draftReplyFromContext === true;
    replyMemories = normalizeReplyMemories(body?.replyMemories);
    requestedRewriteMode = String(body?.mode || "generic").trim().toLowerCase();
    emailReplyGreetingMode = normalizeEmailReplyGreetingMode(body?.emailReplyGreetingMode);
    emailReplySignoffMode = normalizeEmailReplySignoffMode(body?.emailReplySignoffMode);
    emailReplySignoffText = String(body?.emailReplySignoffText || "").trim();
    emailRecipientHint = String(body?.emailRecipientHint || "").trim();
    const dictionary = getRequestDictionary(body);
    correctedInput = applyDictionaryReplacements(applySelfCorrections(text), dictionary);
    effectiveRewriteMode = (
      requestedRewriteMode === "email_body" || requestedRewriteMode === "email_subject"
    )
      ? requestedRewriteMode
      : (
          looksLikeEmailBodyText(correctedInput) || instructionRequestsEmailForm(instruction)
            ? "email_body"
            : requestedRewriteMode
        );
    if (draftReplyFromContext) {
      instruction = normalizeDraftReplyInstruction(instruction);
    }
    explicitTargetLanguage = inferExplicitTargetLanguageFromInstruction(instruction);
    allowsLanguageChange = explicitTargetLanguage !== null || instructionRequestsLanguageChange(instruction);
    effectiveOutputLanguage = explicitTargetLanguage || lang;
    const replyContextProfile = draftReplyFromContext
      ? classifyDraftReplyContext(correctedInput)
      : null;

    const langRule = explicitTargetLanguage
      ? `The instruction explicitly requests a language change. Output language must be ${explicitTargetLanguage}. Translate only because the instruction asks for it.`
      : allowsLanguageChange
        ? "Preserve the original text language by default. Only change the language if the instruction explicitly asks for translation or clearly names another target language. If the user asks to translate without naming a target language, infer the intended target from the instruction language and context."
        : `Output language must stay ${lang}. Keep the same language as the original text. Do not translate into any other language unless the instruction explicitly requests translation.`;
    const styleRule = STYLE_RULES[style] || STYLE_RULES.clean;
    const dictionaryRule = buildDictionaryPromptClause(dictionary);
    const baseSafetyRule = "Keep names, dates, numbers, and factual content unless the instruction explicitly requests changing them.";
    const noAssumptionRule = draftReplyFromContext
      ? "Use only facts explicitly present in the incoming message context or spoken instruction. Do not invent status updates, percentages, timelines, confirmations, attachments, progress estimates, future plans, or expectations."
      : "";
    const instructionWordCount = String(instruction || "").trim().split(/\s+/).filter(Boolean).length;
    const concisePointRule = draftReplyFromContext && instructionWordCount <= 3
      ? "The spoken instruction is very brief. Keep the reply concise and express only that point without elaboration."
      : "";
    const singleDraftRule = "Return exactly one final draft only. Never include alternatives, notes, prefixes, or placeholders.";
    const spokenFormattingRule = "Respect explicit formatting instructions and spoken formatting words. Convert spoken emoji words like 'smilefjes' to emoji only when those words are explicitly spoken. Never add emoji unless explicitly requested or already present in the source text. Convert spoken punctuation words (for example slash/slahs, comma/komma, punktum/period) into punctuation symbols. Apply requested parentheses and remove command words once formatting is applied.";
    const memoryRule = replyMemories.length
      ? "If any reply memory is relevant, treat it as the user's standing preference for how to answer. If a memory includes saved incoming message context, use it as background for drafting a complete reply. Use the memory to shape the final reply naturally, but do not quote it word-for-word unless that is clearly the best response."
      : "";
    const isEmailReplyMode = effectiveRewriteMode === "email_body" || effectiveRewriteMode === "email_subject";
    const baseEmailReplyMeta = (draftReplyFromContext || isEmailReplyMode)
      ? extractEmailReplyMetadata(correctedInput)
      : { senderDisplayName: "", greetingName: "" };
    const fallbackEmailReplyMeta = emailRecipientHint
      ? extractEmailReplyMetadata(emailRecipientHint)
      : { senderDisplayName: "", greetingName: "" };
    const emailReplyMeta = baseEmailReplyMeta.greetingName
      ? baseEmailReplyMeta
      : fallbackEmailReplyMeta.greetingName
        ? fallbackEmailReplyMeta
        : baseEmailReplyMeta;
    const preferredGreetingName = emailReplyGreetingMode === "fullName"
      ? (emailReplyMeta.senderDisplayName || emailReplyMeta.greetingName)
      : emailReplyMeta.greetingName;
    const greetingRule = isEmailReplyMode && preferredGreetingName
      ? `Start the email with a natural direct greeting to the sender: "Hei ${preferredGreetingName}," unless the user explicitly asks for another style.`
      : isEmailReplyMode
        ? "Start the email with a natural greeting when appropriate."
        : "";
    const signoffRule = isEmailReplyMode
      ? (() => {
          if (emailReplySignoffMode === "none") {
            return "Do not add a closing sign-off unless the user explicitly asks for one.";
          }
          if (emailReplySignoffText) {
            return `End the email with this exact sign-off block, preserving line breaks:\n${emailReplySignoffText}`;
          }
          return "End the email with a short, natural sign-off only if it clearly improves the reply.";
        })()
      : "";
    const summaryRequested = instructionRequestsSummary(instruction);
    const veryShortSummaryRequested = summaryRequested && instructionRequestsVeryShortSummary(instruction);
    const summaryRule = veryShortSummaryRequested
      ? "If the instruction asks for a short summary, compress aggressively: keep only essential points and make the output clearly much shorter than the source (usually around 20-45% of source length). Prefer one short sentence (max two short sentences only if needed)."
      : summaryRequested
        ? "If the instruction asks for a summary, compress aggressively: keep only the essential points and make the output substantially shorter than the source (usually around 30-60% of source length). Prefer 1-2 short sentences."
        : "";
    const taskRule = draftReplyFromContext
      ? `Draft a complete send-ready reply to the provided incoming message context. The provided text is the message being answered, not the draft to rewrite. Use the incoming message plus the spoken instruction to write the full response the user should send. ${replyContextProfile?.extraRule || ""} ${isEmailReplyMode ? `The user is writing inside an email field, so format the output as an actual email reply body, not a chat reply. ${greetingRule} ${signoffRule}` : ""} Be polite, context-aware, and useful. Do not simply restate the spoken instruction, and do not return only a short fragment.`
      : isEmailReplyMode
        ? `Apply the user instruction to the provided text and keep the result in clear email format (not chat format). ${greetingRule} ${signoffRule}`
        : "Apply the user instruction to the provided text.";
    const rewriteMaxTokensBase = draftReplyFromContext
      ? Math.max(OPENAI_MAX_TOKENS_REWRITE, replyContextProfile?.minTokens || 220)
      : OPENAI_MAX_TOKENS_REWRITE;
    const rewriteMaxTokens = (
      summaryRequested && !draftReplyFromContext
        ? Math.max(80, Math.min(rewriteMaxTokensBase, veryShortSummaryRequested ? 128 : 180))
        : rewriteMaxTokensBase
    );
    const system = `${taskRule} ${summaryRule} ${styleRule} ${langRule} ${baseSafetyRule} ${noAssumptionRule} ${concisePointRule} ${singleDraftRule} ${spokenFormattingRule} ${dictionaryRule} ${memoryRule} Return JSON only: {"language":"...","text":"..."}`;
    const memorySection = replyMemories.length
      ? `\n\nRelevant reply memories:\n${replyMemories.map((memory) => {
        const triggerPart = memory.triggers ? ` (triggers: ${memory.triggers})` : "";
        const sourcePart = memory.sourceText ? `\n  Saved incoming context: ${memory.sourceText}` : "";
        return `- ${memory.title}${triggerPart}: ${memory.guidance}${sourcePart}`;
      }).join("\n")}`
      : "";
    timings.preprocessMs = Date.now() - requestStartedAt;

    const modelStartedAt = Date.now();
    const { response, attempts } = await requestModelDraft({
      system,
      user: `Instruction:\n${instruction}\n\n${draftReplyFromContext ? "Incoming message context" : "Text"}:\n${correctedInput}${memorySection}`,
      requestSignal,
      maxTokens: rewriteMaxTokens
    });
    timings.modelAttempts = attempts;
    timings.modelMs = Date.now() - modelStartedAt;

    const postprocessStartedAt = Date.now();
    const raw = response?.choices?.[0]?.message?.content || "";
    let parsed;
    try { parsed = JSON.parse(raw); }
    catch { parsed = { language: "unknown", text: raw }; }

    const modelText = String(parsed.text || "").trim();
    if (!modelText) {
      return { status: 502, json: { error: "Model returned empty text." } };
    }

    const sanitizeMode = isEmailReplyMode ? "email_body" : "generic";
    let finalText = sanitizeModelOutput(
      modelText,
      sanitizeMode,
      explicitTargetLanguage ? effectiveOutputLanguage : (allowsLanguageChange ? "" : lang)
    );
    const preferredLanguageForOutput = explicitTargetLanguage ? effectiveOutputLanguage : (allowsLanguageChange ? "" : lang);
    finalText = normalizePunctuationArtifacts(
      applySpokenFormattingPostprocess(
        applyDictionaryReplacements(finalText, dictionary)
      )
    ).trim();
    const rewriteRawFormattingSource = `${instruction}\n${correctedInput}`;
    const rewriteFormattedSource = applySpokenFormattingPostprocess(rewriteRawFormattingSource);
    finalText = preserveRequestedBulletLayout(rewriteRawFormattingSource, finalText);
    finalText = preserveRequestedListHeading(
      rewriteRawFormattingSource,
      finalText,
      preferredLanguageForOutput
    );
    finalText = preserveRequestedParentheses(rewriteFormattedSource, finalText);
    finalText = preserveRequestedEmojis(rewriteFormattedSource, finalText).trim();
    finalText = stripUnrequestedEmojis(rewriteFormattedSource, finalText).trim();
    if (summaryRequested) {
      finalText = enforceSummaryBrevity({
        sourceText: correctedInput,
        summaryText: finalText,
        strict: veryShortSummaryRequested
      });
    }
    finalText = tidyBulletListOutput(finalText);
    const languageMismatchDetected = (
      (!allowsLanguageChange && isLikelyWrongForTarget(finalText, lang))
      || (explicitTargetLanguage && isLikelyWrongForTarget(finalText, effectiveOutputLanguage))
    );
    if (languageMismatchDetected) {
      usedFallback = true;
      console.warn("⚠️ rewrite language mismatch; using local fallback.");
      finalText = buildLocalRewriteFallbackText({
        instruction,
        sourceText: correctedInput,
        rewriteMode: effectiveRewriteMode,
        preferredLanguage: preferredLanguageForOutput
      });
    }
    if (!finalText) {
      return { status: 502, json: { error: "Model returned empty text." } };
    }

    timings.postprocessMs = Date.now() - postprocessStartedAt;
    timings.totalMs = Date.now() - requestStartedAt;
    const retryCount = Math.max(0, (timings.modelAttempts?.length || 0) - 1);
    console.log("✏️ rewrite:", safePreview(finalText, 80), "| chars:", finalText.length, "| retries:", retryCount);

    return {
      status: 200,
      json: {
        language: effectiveOutputLanguage,
        text: finalText,
        appliedMode: effectiveRewriteMode,
        appliedStyle: style,
        instruction,
        fallback: usedFallback,
        timings: {
          preprocessMs: timings.preprocessMs,
          modelMs: timings.modelMs,
          postprocessMs: timings.postprocessMs,
          totalMs: timings.totalMs,
          retries: retryCount
        }
      }
    };
  } catch (err) {
    if (requestSignal?.aborted) {
      return { status: 499, json: { error: "Client closed request." } };
    }

    if (correctedInput && !allowsLanguageChange) {
      const retryCount = Math.max(0, (Array.isArray(err?.attempts) ? err.attempts.length : timings.modelAttempts.length) - 1);
      timings.totalMs = Date.now() - requestStartedAt;
      console.warn("⚠️ rewrite fallback:", err?.message || "unknown", "| retries:", retryCount);
      const preferredLanguageForOutput = explicitTargetLanguage ? effectiveOutputLanguage : (allowsLanguageChange ? "" : lang);
      return {
        status: 200,
        json: {
          language: effectiveOutputLanguage,
          text: buildLocalRewriteFallbackText({
            instruction,
            sourceText: correctedInput,
            rewriteMode: effectiveRewriteMode,
            preferredLanguage: preferredLanguageForOutput
          }),
          appliedMode: effectiveRewriteMode,
          appliedStyle: style,
          instruction,
          fallback: true,
          timings: {
            preprocessMs: timings.preprocessMs,
            modelMs: timings.modelMs,
            postprocessMs: timings.postprocessMs,
            totalMs: timings.totalMs,
            retries: retryCount
          }
        }
      };
    }

    if (Array.isArray(err?.attempts)) {
      const attempts = err.attempts;
      const retryCount = Math.max(0, attempts.length - 1);
      console.error("REWRITE MODEL ERROR:", err?.message, "| retries:", retryCount);
    } else {
      console.error("REWRITE ERROR:", err?.message);
    }
    return { status: 500, json: { error: "Server error.", details: err?.message } };
  }
}

function sendJson(req, res, statusCode, payload, extraHeaders = {}) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    ...buildBaseResponseHeaders(req),
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    ...extraHeaders
  });
  res.end(body);
}

function readJsonBody(req) {
  return new Promise((resolve) => {
    let finished = false;
    let size = 0;
    let raw = "";

    function done(result) {
      if (finished) return;
      finished = true;
      resolve(result);
    }

    req.on("data", (chunk) => {
      if (finished) return;
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        done({ ok: false, status: 413, error: "Too long." });
        req.destroy();
        return;
      }
      raw += chunk.toString("utf8");
    });

    req.on("end", () => {
      if (finished) return;
      if (!raw.trim()) {
        done({ ok: true, body: {} });
        return;
      }
      try {
        done({ ok: true, body: JSON.parse(raw) });
      } catch {
        done({ ok: false, status: 400, error: "Invalid JSON." });
      }
    });

    req.on("error", (error) => {
      done({ ok: false, status: 400, error: `Bad request: ${error?.message || "unknown"}` });
    });
  });
}

function readRawBody(req, maxBytes = MAX_BODY_BYTES) {
  return new Promise((resolve) => {
    let finished = false;
    let size = 0;
    const chunks = [];

    function done(result) {
      if (finished) return;
      finished = true;
      resolve(result);
    }

    req.on("data", (chunk) => {
      if (finished) return;
      const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      size += buffer.length;
      if (size > maxBytes) {
        done({ ok: false, status: 413, error: "Too long." });
        req.destroy();
        return;
      }
      chunks.push(buffer);
    });

    req.on("end", () => {
      if (finished) return;
      const rawBuffer = Buffer.concat(chunks);
      done({
        ok: true,
        rawBuffer,
        rawText: rawBuffer.toString("utf8")
      });
    });

    req.on("error", (error) => {
      done({ ok: false, status: 400, error: `Bad request: ${error?.message || "unknown"}` });
    });
  });
}

function parseStripeSignatureHeader(headerValue) {
  const data = {
    timestamp: 0,
    signatures: []
  };
  const parts = String(headerValue || "").split(",");
  for (const part of parts) {
    const [key, value] = part.split("=");
    if (!key || !value) continue;
    if (key.trim() === "t") {
      data.timestamp = Number(value.trim());
    }
    if (key.trim() === "v1") {
      data.signatures.push(value.trim());
    }
  }
  return data;
}

function verifyStripeWebhookSignature(rawBody, signatureHeader, secret) {
  if (!secret) return false;
  const parsed = parseStripeSignatureHeader(signatureHeader);
  if (!Number.isFinite(parsed.timestamp) || parsed.timestamp <= 0 || parsed.signatures.length === 0) {
    return false;
  }

  const ageSec = Math.abs(Math.floor(Date.now() / 1000) - Math.floor(parsed.timestamp));
  if (STRIPE_WEBHOOK_TOLERANCE_SEC > 0 && ageSec > STRIPE_WEBHOOK_TOLERANCE_SEC) {
    return false;
  }

  const payload = `${parsed.timestamp}.${String(rawBody || "")}`;
  const expected = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  return parsed.signatures.some((candidate) => safeEqualString(expected, String(candidate || "")));
}

function toIsoFromUnixSeconds(value) {
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds <= 0) return null;
  return new Date(seconds * 1000).toISOString();
}

function cleanupRecentWebhookEvents(now) {
  for (const [eventId, expiresAt] of RECENT_WEBHOOK_EVENT_IDS.entries()) {
    if (!expiresAt || expiresAt <= now) {
      RECENT_WEBHOOK_EVENT_IDS.delete(eventId);
    }
  }
}

function markWebhookEventInMemory(eventId) {
  const now = Date.now();
  cleanupRecentWebhookEvents(now);
  if (RECENT_WEBHOOK_EVENT_IDS.has(eventId)) {
    return { duplicate: true, source: "memory" };
  }
  RECENT_WEBHOOK_EVENT_IDS.set(eventId, now + WEBHOOK_DEDUP_TTL_MS);
  return { duplicate: false, source: "memory" };
}

async function markWebhookEventAsProcessed(event) {
  const eventId = claimString(event?.id);
  const eventType = claimString(event?.type);
  if (!eventId) {
    return { duplicate: false, source: "none" };
  }

  const memoryState = markWebhookEventInMemory(eventId);
  if (memoryState.duplicate) {
    return memoryState;
  }

  if (!SUPABASE_BILLING_SYNC_ENABLED) {
    return { duplicate: false, source: "memory_only" };
  }

  try {
    const endpoint = `${SUPABASE_REST_URL}/${encodeURIComponent("billing_webhook_events")}?on_conflict=${encodeURIComponent("event_id")}`;
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
        Prefer: "resolution=ignore-duplicates,return=representation"
      },
      body: JSON.stringify([{
        event_id: eventId,
        event_type: eventType || null
      }])
    });

    if (!response.ok) {
      const bodyText = await response.text();
      throw new Error(`Webhook idempotency write failed (${response.status}): ${bodyText.slice(0, 240)}`);
    }

    let rows = [];
    try {
      rows = await response.json();
    } catch {
      rows = [];
    }
    if (Array.isArray(rows) && rows.length === 0) {
      return { duplicate: true, source: "supabase" };
    }
  } catch (error) {
    console.warn("⚠️ webhook idempotency fallback to memory:", error?.message || "unknown");
    return { duplicate: false, source: "memory_fallback" };
  }

  return { duplicate: false, source: "supabase" };
}

function extractStripePriceId(subscription) {
  return claimString(
    subscription?.items?.data?.[0]?.price?.id
    || subscription?.plan?.id
  );
}

function mapPlanFromStripe(priceId, status) {
  const mapped = STRIPE_PRICE_PLAN_MAP[String(priceId || "")];
  if (mapped) {
    return normalizePlan(mapped);
  }
  const normalizedStatus = claimString(status).toLowerCase();
  if (["active", "trialing", "past_due"].includes(normalizedStatus)) return "pro";
  return "free";
}

function extractStripeUserId(source) {
  return claimString(
    source?.metadata?.supabase_user_id
    || source?.metadata?.user_id
    || source?.metadata?.userId
    || source?.client_reference_id
    || source?.customer_details?.metadata?.supabase_user_id
  );
}

async function fetchStripeSubscription(subscriptionId) {
  const cleanId = claimString(subscriptionId);
  if (!cleanId || !STRIPE_SECRET_KEY) return null;

  const endpoint = `https://api.stripe.com/v1/subscriptions/${encodeURIComponent(cleanId)}?expand[]=items.data.price`;
  try {
    const response = await fetch(endpoint, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${STRIPE_SECRET_KEY}`
      }
    });
    if (!response.ok) {
      const bodyText = await response.text();
      console.warn("⚠️ stripe subscription fetch failed:", response.status, bodyText.slice(0, 200));
      return null;
    }
    return await response.json();
  } catch (error) {
    console.warn("⚠️ stripe subscription fetch error:", error?.message || "unknown");
    return null;
  }
}

async function upsertSupabaseBillingRecord(record) {
  if (!SUPABASE_BILLING_SYNC_ENABLED) {
    return { ok: false, skipped: "disabled" };
  }

  async function resolveUserIdByCustomerId(customerId) {
    const cleanCustomerId = claimString(customerId);
    if (!cleanCustomerId) return null;

    const endpoint = `${SUPABASE_REST_URL}/${encodeURIComponent(SUPABASE_BILLING_TABLE)}?select=${encodeURIComponent(SUPABASE_USER_COLUMN)}&${encodeURIComponent(SUPABASE_STRIPE_CUSTOMER_COLUMN)}=eq.${encodeURIComponent(cleanCustomerId)}&limit=1`;
    try {
      const response = await fetch(endpoint, {
        method: "GET",
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json"
        }
      });
      if (!response.ok) return null;
      const rows = await response.json();
      if (!Array.isArray(rows) || rows.length === 0) return null;
      return claimString(rows[0]?.[SUPABASE_USER_COLUMN]) || null;
    } catch {
      return null;
    }
  }

  let resolvedUserId = claimString(record?.userId) || null;
  const resolvedCustomerId = claimString(record?.customerId) || null;
  if (!resolvedUserId && resolvedCustomerId) {
    resolvedUserId = await resolveUserIdByCustomerId(resolvedCustomerId);
  }

  const row = {};
  row[SUPABASE_USER_COLUMN] = resolvedUserId;
  row[SUPABASE_STRIPE_CUSTOMER_COLUMN] = resolvedCustomerId;
  row.stripe_subscription_id = claimString(record?.subscriptionId) || null;
  row.plan = normalizePlan(record?.plan || "free");
  row.subscription_status = claimString(record?.status) || null;
  row.current_period_end = claimString(record?.currentPeriodEnd) || null;
  row.updated_at = new Date().toISOString();

  const hasCustomerKey = !!row[SUPABASE_STRIPE_CUSTOMER_COLUMN];
  const hasUserKey = !!row[SUPABASE_USER_COLUMN];
  if (!hasCustomerKey && !hasUserKey) {
    return { ok: false, skipped: "missing_identity" };
  }
  if (!hasUserKey) {
    return { ok: false, skipped: "missing_user_id" };
  }

  const conflictColumn = hasCustomerKey ? SUPABASE_STRIPE_CUSTOMER_COLUMN : SUPABASE_USER_COLUMN;
  if (!hasCustomerKey) {
    console.warn("⚠️ billing upsert: no stripe_customer_id, falling back to user_id conflict key for user:", resolvedUserId);
  }
  const endpoint = `${SUPABASE_REST_URL}/${encodeURIComponent(SUPABASE_BILLING_TABLE)}?on_conflict=${encodeURIComponent(conflictColumn)}`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=minimal"
    },
    body: JSON.stringify([row])
  });

  if (!response.ok) {
    const bodyText = await response.text();
    throw new Error(`Supabase billing upsert failed (${response.status}): ${bodyText.slice(0, 240)}`);
  }

  return { ok: true, conflictColumn };
}

async function handleStripeWebhookEvent(event) {
  const type = claimString(event?.type);
  const object = event?.data?.object || {};

  if (type === "checkout.session.completed") {
    const record = {
      userId: extractStripeUserId(object),
      customerId: claimString(object.customer),
      subscriptionId: claimString(object.subscription),
      status: claimString(object.status || object.payment_status || "checkout_completed"),
      plan: normalizePlan(object?.metadata?.plan || "pro"),
      currentPeriodEnd: null
    };

    if (record.subscriptionId) {
      const subscription = await fetchStripeSubscription(record.subscriptionId);
      if (subscription) {
        const subUserId = extractStripeUserId(subscription);
        if (subUserId) record.userId = subUserId;
        if (!record.customerId) record.customerId = claimString(subscription.customer);
        record.status = claimString(subscription.status) || record.status;
        record.plan = mapPlanFromStripe(extractStripePriceId(subscription), record.status);
        record.currentPeriodEnd = toIsoFromUnixSeconds(subscription.current_period_end);
      }
    }

    const synced = await upsertSupabaseBillingRecord(record);
    return { type, synced };
  }

  if (type === "customer.subscription.created" || type === "customer.subscription.updated" || type === "customer.subscription.deleted") {
    const status = claimString(object.status || (type === "customer.subscription.deleted" ? "canceled" : ""));
    const record = {
      userId: extractStripeUserId(object),
      customerId: claimString(object.customer),
      subscriptionId: claimString(object.id),
      status,
      plan: type === "customer.subscription.deleted" ? "free" : mapPlanFromStripe(extractStripePriceId(object), status),
      currentPeriodEnd: toIsoFromUnixSeconds(object.current_period_end)
    };
    const synced = await upsertSupabaseBillingRecord(record);
    return { type, synced };
  }

  return { type, ignored: true };
}

async function createStripeCheckoutSession({ userId, priceId, successUrl, cancelUrl }) {
  const params = new URLSearchParams();
  params.append("mode", "subscription");
  params.append("line_items[0][price]", priceId);
  params.append("line_items[0][quantity]", "1");
  params.append("metadata[supabase_user_id]", userId);
  params.append("client_reference_id", userId);
  if (successUrl) params.append("success_url", successUrl);
  if (cancelUrl) params.append("cancel_url", cancelUrl);

  const response = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: params.toString()
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Stripe checkout session failed (${response.status}): ${text.slice(0, 240)}`);
  }

  return await response.json();
}

const server = createServer(async (req, res) => {
  const method = String(req.method || "GET").toUpperCase();
  const url = new URL(req.url || "/", "http://localhost");

  if (method === "OPTIONS") {
    res.writeHead(204, {
      ...buildBaseResponseHeaders(req)
    });
    res.end();
    return;
  }

  if (method === "POST" && url.pathname === "/stripe/webhook") {
    if (!STRIPE_WEBHOOK_ENABLED) {
      sendJson(req, res, 503, { error: "Stripe webhook is not configured." });
      return;
    }

    const parsedRaw = await readRawBody(req, 2_000_000);
    if (!parsedRaw.ok) {
      sendJson(req, res, parsedRaw.status, { error: parsedRaw.error });
      return;
    }

    const signatureHeader = req.headers?.["stripe-signature"];
    const signatureValid = verifyStripeWebhookSignature(parsedRaw.rawText, signatureHeader, STRIPE_WEBHOOK_SECRET);
    if (!signatureValid) {
      sendJson(req, res, 400, { error: "Invalid Stripe signature." });
      return;
    }

    let event;
    try {
      event = JSON.parse(parsedRaw.rawText || "{}");
    } catch {
      sendJson(req, res, 400, { error: "Invalid webhook JSON." });
      return;
    }

    try {
      const dedupe = await markWebhookEventAsProcessed(event);
      if (dedupe.duplicate) {
        sendJson(req, res, 200, {
          received: true,
          type: event?.type || null,
          ignored: true,
          duplicate: true,
          dedupe: dedupe.source
        });
        return;
      }

      const result = await handleStripeWebhookEvent(event);
      sendJson(req, res, 200, { received: true, type: result?.type || null, ignored: !!result?.ignored });
    } catch (error) {
      console.error("STRIPE WEBHOOK ERROR:", error?.message || "unknown");
      sendJson(req, res, 500, { error: "Webhook processing failed." });
    }
    return;
  }

  if (method === "GET" && url.pathname === "/health") {
    const readiness = buildReadinessReport();
    sendJson(req, res, 200, {
      ok: true,
      ready: readiness.ready,
      readinessIssues: readiness.issues,
      authRequired: AUTH_REQUIRED,
      hasModelKey: hasOpenAI,
      jwtEnabled: JWT_ENABLED,
      supabaseJwtEnabled: SUPABASE_JWT_ENABLED,
      stripeWebhookEnabled: STRIPE_WEBHOOK_ENABLED,
      stripeCheckoutEnabled: STRIPE_CHECKOUT_ENABLED,
      supabaseBillingSyncEnabled: SUPABASE_BILLING_SYNC_ENABLED
    });
    return;
  }

  if (method === "GET" && url.pathname === "/ready") {
    const report = buildReadinessReport();
    sendJson(req, res, report.ready ? 200 : 503, {
      ok: report.ready,
      tag: BACKEND_TAG,
      issues: report.issues
    });
    return;
  }

  if (method === "GET" && url.pathname === "/dictionary") {
    sendJson(req, res, 200, {
      terms: BASE_DICTIONARY.terms,
      replacements: BASE_DICTIONARY.replacements
    });
    return;
  }

  if (method === "GET" && url.pathname === "/version") {
    const auth = await verifyToken(req);
    if (!auth.ok) {
      sendJson(req, res, auth.status, { error: auth.error });
      return;
    }
    sendJson(req, res, 200, {
      tag: BACKEND_TAG,
      model: MODEL,
      host: HOST,
      authRequired: AUTH_REQUIRED,
      auth: {
        staticTokens: AUTH_TOKEN_HASHES.size,
        jwtEnabled: JWT_ENABLED,
        jwtSecrets: JWT_SECRETS.length,
        jwtAudienceChecks: JWT_ACCEPTED_AUDIENCES.length,
        jwtIssuerChecks: JWT_ACCEPTED_ISSUERS.length,
        supabaseJwtEnabled: SUPABASE_JWT_ENABLED,
        supabaseIssuer: SUPABASE_JWT_ISSUER || null,
        supabaseAudiences: SUPABASE_JWT_AUDIENCES
      },
      rateLimit: {
        windowMs: RATE_LIMIT_WINDOW_MS,
        maxAuth: RATE_LIMIT_MAX_AUTH,
        maxPublic: RATE_LIMIT_MAX_PUBLIC,
        redisEnabled: RATE_LIMIT_REDIS_ENABLED,
        maxAuthByPlan: {
          free: RATE_LIMIT_MAX_AUTH_FREE,
          pro: RATE_LIMIT_MAX_AUTH_PRO,
          team: RATE_LIMIT_MAX_AUTH_TEAM,
          enterprise: RATE_LIMIT_MAX_AUTH_ENTERPRISE
        },
        dailyAuthByPlan: {
          free: DAILY_USAGE_MAX_AUTH_FREE,
          pro: DAILY_USAGE_MAX_AUTH_PRO,
          team: DAILY_USAGE_MAX_AUTH_TEAM,
          enterprise: DAILY_USAGE_MAX_AUTH_ENTERPRISE
        },
        dailyUsageStorage: dailyUsageStorageMode()
      },
      fastpathCache: {
        enabled: FASTPATH_CACHE_TTL_MS > 0,
        ttlMs: FASTPATH_CACHE_TTL_MS,
        maxItems: FASTPATH_CACHE_MAX_ITEMS
      },
      billing: {
        stripeWebhookEnabled: STRIPE_WEBHOOK_ENABLED,
        supabaseBillingSyncEnabled: SUPABASE_BILLING_SYNC_ENABLED,
        supabaseBillingTable: SUPABASE_BILLING_TABLE,
        stripePricePlanMapCount: Object.keys(STRIPE_PRICE_PLAN_MAP).length
      }
    });
    return;
  }

  if (method === "GET" && url.pathname === "/metrics") {
    const auth = await verifyToken(req);
    if (!auth.ok) {
      recordBackendError("metrics_auth_failed", {
        path: url.pathname,
        status: auth.status,
        message: auth.error
      });
      sendJson(req, res, auth.status, { error: auth.error });
      return;
    }
    const currentUserUsage = auth.authenticated
      ? await peekDailyUsage(auth.tokenHash, auth.plan)
      : null;
    sendJson(req, res, 200, {
      tag: BACKEND_TAG,
      ...summarizePolishMetrics(),
      dailyUsage: {
        storage: dailyUsageStorageMode(),
        global: await summarizeDailyUsage(),
        currentUser: currentUserUsage
      },
      recentErrors: recentBackendErrors()
    });
    return;
  }

  if (method === "POST" && url.pathname === "/polish") {
    const endpointStartedAt = Date.now();
    const auth = await verifyToken(req);
    if (!auth.ok) {
      recordBackendError("polish_auth_failed", {
        path: url.pathname,
        status: auth.status,
        message: auth.error
      });
      recordPolishMetric({
        status: auth.status,
        endpointMs: Date.now() - endpointStartedAt,
        cache: "MISS",
        mode: "auth_failed",
        auth: "none",
        plan: "free"
      });
      sendJson(req, res, auth.status, { error: auth.error });
      return;
    }

    const limitKey = auth.authenticated
      ? `token:${auth.tokenHash}`
      : `ip:${requestIP(req)}`;
    const limit = auth.authenticated
      ? resolveAuthenticatedRateLimit(auth.plan)
      : RATE_LIMIT_MAX_PUBLIC;
    const rate = await consumeRateLimit(limitKey, limit);
    if (!rate.allowed) {
      const retryAfter = Math.max(1, Math.ceil((rate.resetAt - Date.now()) / 1000));
      recordPolishMetric({
        status: 429,
        endpointMs: Date.now() - endpointStartedAt,
        cache: "MISS",
        mode: "rate_limited",
        auth: auth.authType,
        plan: auth.plan
      });
      sendJson(req, res, 429, { error: "Rate limit exceeded." }, {
        "Retry-After": String(retryAfter),
        "X-RateLimit-Limit": String(rate.limit),
        "X-RateLimit-Remaining": "0",
        "X-RateLimit-Reset": String(Math.floor(rate.resetAt / 1000)),
        "X-Auth-Plan": normalizePlan(auth.plan)
      });
      return;
    }

    const requestAbortController = new AbortController();
    req.on("aborted", () => requestAbortController.abort());
    res.on("close", () => {
      if (!res.writableEnded) {
        requestAbortController.abort();
      }
    });

    const parsed = await readJsonBody(req);
    if (!parsed.ok) {
      if (requestAbortController.signal.aborted || res.writableEnded || res.destroyed) return;
      recordBackendError("polish_bad_request", {
        path: url.pathname,
        status: parsed.status,
        auth: auth.authType,
        plan: auth.plan,
        message: parsed.error
      });
      recordPolishMetric({
        status: parsed.status,
        endpointMs: Date.now() - endpointStartedAt,
        cache: "MISS",
        mode: "bad_request",
        auth: auth.authType,
        plan: auth.plan
      });
      sendJson(req, res, parsed.status, { error: parsed.error }, {
        "X-RateLimit-Limit": String(rate.limit),
        "X-RateLimit-Remaining": String(rate.remaining),
        "X-RateLimit-Reset": String(Math.floor(rate.resetAt / 1000)),
        "X-Auth-Plan": normalizePlan(auth.plan)
      });
      return;
    }

    const dailyUsage = auth.authenticated
      ? await consumeDailyUsage(auth.tokenHash, auth.plan)
      : null;
    if (dailyUsage && !dailyUsage.allowed) {
      recordPolishMetric({
        status: 429,
        endpointMs: Date.now() - endpointStartedAt,
        cache: "MISS",
        mode: "daily_capped",
        auth: auth.authType,
        plan: auth.plan
      });
      sendJson(req, res, 429, {
        error: "Daily usage limit reached.",
        dailyUsage: {
          dayKey: dailyUsage.dayKey,
          limit: dailyUsage.limit,
          used: dailyUsage.used,
          remaining: 0
        }
      }, {
        "X-RateLimit-Limit": String(rate.limit),
        "X-RateLimit-Remaining": String(rate.remaining),
        "X-RateLimit-Reset": String(Math.floor(rate.resetAt / 1000)),
        "X-Auth-Plan": normalizePlan(auth.plan)
      });
      return;
    }

    const cacheBypass = shouldBypassFastpathCache(req, parsed.body);
    const cacheKey = buildFastpathCacheKey(parsed.body);
    const cached = cacheBypass ? null : getFastpathCache(cacheKey);
    if (cached) {
      recordPolishMetric({
        status: cached.status,
        endpointMs: Date.now() - endpointStartedAt,
        modelMs: 0,
        fallback: Boolean(cached?.json?.fallback),
        cache: "HIT",
        mode: String(cached?.json?.appliedMode || "unknown"),
        auth: auth.authType,
        plan: auth.plan
      });
      sendJson(req, res, cached.status, cached.json, {
        "X-RateLimit-Limit": String(rate.limit),
        "X-RateLimit-Remaining": String(rate.remaining),
        "X-RateLimit-Reset": String(Math.floor(rate.resetAt / 1000)),
        "X-Auth-Plan": normalizePlan(auth.plan),
        "X-Fastpath-Cache": "HIT"
      });
      return;
    }

    const result = await handlePolish(parsed.body, requestAbortController.signal);
    if (requestAbortController.signal.aborted || res.writableEnded || res.destroyed) return;
    if (result.status === 499) return;
    if (result.status >= 500) {
      recordBackendError("polish_failed", {
        path: url.pathname,
        status: result.status,
        auth: auth.authType,
        plan: auth.plan,
        message: String(result?.json?.error || "Unknown polish failure")
      });
    }
    const endpointMs = Date.now() - endpointStartedAt;
    if (!cacheBypass && result.status >= 200 && result.status < 300) {
      setFastpathCache(cacheKey, {
        status: result.status,
        json: result.json
      });
    }
    recordPolishMetric({
      status: result.status,
      endpointMs,
      modelMs: Number(result?.json?.timings?.modelMs || 0),
      fallback: Boolean(result?.json?.fallback),
      cache: cacheBypass ? "BYPASS" : "MISS",
      mode: String(result?.json?.appliedMode || "unknown"),
      auth: auth.authType,
      plan: auth.plan
    });
    sendJson(req, res, result.status, result.json, {
      "X-RateLimit-Limit": String(rate.limit),
      "X-RateLimit-Remaining": String(rate.remaining),
      "X-RateLimit-Reset": String(Math.floor(rate.resetAt / 1000)),
      "X-Auth-Plan": normalizePlan(auth.plan),
      "X-Fastpath-Cache": cacheBypass ? "BYPASS" : "MISS"
    });
    return;
  }

  if (method === "POST" && url.pathname === "/rewrite") {
    const auth = await verifyToken(req);
    if (!auth.ok) {
      recordBackendError("rewrite_auth_failed", {
        path: url.pathname,
        status: auth.status,
        message: auth.error
      });
      sendJson(req, res, auth.status, { error: auth.error });
      return;
    }

    const limitKey = auth.authenticated
      ? `token:${auth.tokenHash}`
      : `ip:${requestIP(req)}`;
    const limit = auth.authenticated
      ? resolveAuthenticatedRateLimit(auth.plan)
      : RATE_LIMIT_MAX_PUBLIC;
    const rate = await consumeRateLimit(limitKey, limit);
    if (!rate.allowed) {
      const retryAfter = Math.max(1, Math.ceil((rate.resetAt - Date.now()) / 1000));
      sendJson(req, res, 429, { error: "Rate limit exceeded." }, {
        "Retry-After": String(retryAfter),
        "X-RateLimit-Limit": String(rate.limit),
        "X-RateLimit-Remaining": "0",
        "X-RateLimit-Reset": String(Math.floor(rate.resetAt / 1000)),
        "X-Auth-Plan": normalizePlan(auth.plan)
      });
      return;
    }

    const requestAbortController = new AbortController();
    req.on("aborted", () => requestAbortController.abort());
    res.on("close", () => {
      if (!res.writableEnded) {
        requestAbortController.abort();
      }
    });

    const parsed = await readJsonBody(req);
    if (!parsed.ok) {
      if (requestAbortController.signal.aborted || res.writableEnded || res.destroyed) return;
      recordBackendError("rewrite_bad_request", {
        path: url.pathname,
        status: parsed.status,
        auth: auth.authType,
        plan: auth.plan,
        message: parsed.error
      });
      sendJson(req, res, parsed.status, { error: parsed.error }, {
        "X-RateLimit-Limit": String(rate.limit),
        "X-RateLimit-Remaining": String(rate.remaining),
        "X-RateLimit-Reset": String(Math.floor(rate.resetAt / 1000)),
        "X-Auth-Plan": normalizePlan(auth.plan)
      });
      return;
    }

    const dailyUsage = auth.authenticated
      ? await consumeDailyUsage(auth.tokenHash, auth.plan)
      : null;
    if (dailyUsage && !dailyUsage.allowed) {
      sendJson(req, res, 429, {
        error: "Daily usage limit reached.",
        dailyUsage: {
          dayKey: dailyUsage.dayKey,
          limit: dailyUsage.limit,
          used: dailyUsage.used,
          remaining: 0
        }
      }, {
        "X-RateLimit-Limit": String(rate.limit),
        "X-RateLimit-Remaining": String(rate.remaining),
        "X-RateLimit-Reset": String(Math.floor(rate.resetAt / 1000)),
        "X-Auth-Plan": normalizePlan(auth.plan)
      });
      return;
    }

    const result = await handleRewrite(parsed.body, requestAbortController.signal);
    if (requestAbortController.signal.aborted || res.writableEnded || res.destroyed) return;
    if (result.status === 499) return;
    if (result.status >= 500) {
      recordBackendError("rewrite_failed", {
        path: url.pathname,
        status: result.status,
        auth: auth.authType,
        plan: auth.plan,
        message: String(result?.json?.error || "Unknown rewrite failure")
      });
    }
    sendJson(req, res, result.status, result.json, {
      "X-RateLimit-Limit": String(rate.limit),
      "X-RateLimit-Remaining": String(rate.remaining),
      "X-RateLimit-Reset": String(Math.floor(rate.resetAt / 1000)),
      "X-Auth-Plan": normalizePlan(auth.plan)
    });
    return;
  }

  if (method === "POST" && url.pathname === "/checkout") {
    if (!STRIPE_CHECKOUT_ENABLED) {
      sendJson(req, res, 503, { error: "Checkout is not configured." });
      return;
    }

    const auth = await verifyToken(req);
    if (!auth.ok) {
      sendJson(req, res, auth.status, { error: auth.error });
      return;
    }
    if (!auth.authenticated) {
      sendJson(req, res, 401, { error: "Authentication required for checkout." });
      return;
    }

    try {
      const session = await createStripeCheckoutSession({
        userId: auth.principal,
        priceId: STRIPE_CHECKOUT_PRICE_ID,
        successUrl: STRIPE_CHECKOUT_SUCCESS_URL || undefined,
        cancelUrl: STRIPE_CHECKOUT_CANCEL_URL || undefined
      });
      console.log("🛒 checkout session created for user:", auth.principal, "session:", session.id);
      sendJson(req, res, 200, { url: session.url, sessionId: session.id });
    } catch (error) {
      console.error("CHECKOUT ERROR:", error?.message);
      sendJson(req, res, 500, { error: "Failed to create checkout session." });
    }
    return;
  }

  sendJson(req, res, 404, { error: "Not found." });
});

server.listen(PORT, HOST, () => {
  const authSummary = AUTH_REQUIRED
    ? `tokens:${AUTH_TOKEN_HASHES.size}|jwt:${JWT_SECRETS.length}|supabase:${SUPABASE_JWT_ENABLED ? 1 : 0}`
    : "disabled";
  const billingSummary = `stripeWebhook:${STRIPE_WEBHOOK_ENABLED ? 1 : 0}|supabaseSync:${SUPABASE_BILLING_SYNC_ENABLED ? 1 : 0}`;
  console.log(`FlowLite backend on http://${HOST}:${PORT} [${BACKEND_TAG}] auth=${authSummary} billing=${billingSummary}`);
});

function shutdown(signal) {
  console.log(`\n${signal} received, shutting down backend...`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5_000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
