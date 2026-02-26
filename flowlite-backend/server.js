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
const TRUSTED_PROXY_IPS = parseListEnv(process.env.TRUSTED_PROXY_IPS || "");
const RATE_LIMIT_BUCKETS = new Map();
const RATE_LIMIT_REDIS_URL = String(process.env.RATE_LIMIT_REDIS_URL || process.env.UPSTASH_REDIS_REST_URL || "").trim().replace(/\/+$/, "");
const RATE_LIMIT_REDIS_TOKEN = String(process.env.RATE_LIMIT_REDIS_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN || "").trim();
const RATE_LIMIT_REDIS_PREFIX = String(process.env.RATE_LIMIT_REDIS_PREFIX || "flowspeak:rl").trim() || "flowspeak:rl";
const RATE_LIMIT_REDIS_ENABLED = RATE_LIMIT_REDIS_URL.length > 0 && RATE_LIMIT_REDIS_TOKEN.length > 0;
const FASTPATH_CACHE_TTL_MS = Math.max(0, Number(process.env.FASTPATH_CACHE_TTL_MS || 10_000));
const FASTPATH_CACHE_MAX_ITEMS = Math.max(10, Number(process.env.FASTPATH_CACHE_MAX_ITEMS || 1_500));
const FASTPATH_CACHE = new Map();
const METRICS_HISTORY_MAX = Math.max(100, Number(process.env.METRICS_HISTORY_MAX || 2_000));
const METRICS_HISTORY = [];
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

function buildFastpathCacheKey(body) {
  const normalized = {
    text: String(body?.text || "").trim(),
    mode: String(body?.mode || "generic"),
    style: String(body?.style || "clean"),
    targetLanguage: String(body?.targetLanguage || DEFAULT_TARGET_LANGUAGE),
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

async function requestModelDraft({ system, user, requestSignal }) {
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
        const http = await fetch(`${OPENAI_API_BASE_URL}/chat/completions`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${OPENAI_API_KEY}`,
          },
          body: JSON.stringify({
            model: MODEL,
            temperature: 0,
            max_tokens: 120,
            messages: [
              { role: "system", content: system },
              { role: "user", content: user }
            ],
            response_format: {
              type: "json_schema",
              json_schema: {
                name: "draft_result",
                schema: {
                  type: "object",
                  additionalProperties: false,
                  properties: {
                    language: { type: "string" },
                    text: { type: "string" }
                  },
                  required: ["language", "text"]
                }
              }
            }
          }),
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
  email_body:    "Email body. Add greeting/sign-off if missing. Keep short paragraphs with clear line breaks.",
  chat_message:  "Chat message. Concise and natural.",
  note:          "Note. Bullet points if helpful.",
  generic:       "Neutral style.",
};

const STYLE_RULES = {
  clean: "Style: clean. Rewrite only. Keep neutral tone. Correct grammar and punctuation, apply self-corrections, and remove filler words (e.g. uhm/ehm) without changing meaning.",
  formal: "Style: formal. Use clear capitalization and proper punctuation.",
  casual: "Style: casual. Keep it friendly and concise. Use slightly lighter punctuation while preserving readability.",
  excited: "Style: excited. Keep it positive and energetic with occasional exclamation marks, but do not overdo it."
};

function normalizeStyle(raw) {
  const v = String(raw || "").trim().toLowerCase();
  if (v === "clean" || v === "formal" || v === "casual" || v === "excited") return v;
  return "clean";
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

    if (previousLineWasSignoff && isLikelyNameLine(trimmed)) {
      out.push(capitalizeFirstLetter(trimmed.replace(/[,.;:!?]+$/g, "")));
      previousLineWasSignoff = false;
      continue;
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

function localPolish(text, mode) {
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
    const hasNorwegianWords = /\b(hei|hilsen|vennlig|med vennlig hilsen|mvh)\b/i.test(lower);
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

function sanitizeModelOutput(text, mode, targetLanguage) {
  let out = String(text || "").replace(/\r\n/g, "\n").trim();
  if (!out) return out;

  out = applySelfCorrections(out);
  out = removeFillerWords(out);
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

function isBrowserBundle(bundleId) {
  return bundleId === "com.google.Chrome"
    || bundleId === "com.apple.Safari"
    || bundleId === "com.microsoft.edgemac"
    || bundleId === "company.thebrowser.Browser"
    || bundleId === "org.mozilla.firefox";
}

function inferMode(requestedMode, bundleId, url, ctx, fieldMeta) {
  const mode = String(requestedMode || "generic");
  const lowerBundle = String(bundleId || "").toLowerCase();
  const lowerUrl = String(url || "").toLowerCase();
  const lowerCtx = String(ctx || "").toLowerCase();
  const lowerMeta = String(fieldMeta || "").toLowerCase();
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
    if (isBrowserBundle(bundleId) && !isMailUrl && !hasStrongEmailHint) {
      return "generic";
    }
    return mode;
  }
  if (mode !== "generic") return mode;

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
    const style = normalizeStyle(body?.style);
    const bundleId = String(body?.bundleId || "");
    const appName = String(body?.appName || "");
    const lang = normalizeTargetLanguage(body?.targetLanguage);
    const ctx  = String(body?.fieldContext || "").trim().slice(-220);
    const url  = String(body?.browserURL || "").trim();
    const axDescription = String(body?.axDescription || "");
    const axHelp = String(body?.axHelp || "");
    const axTitle = String(body?.axTitle || "");
    const axPlaceholder = String(body?.axPlaceholder || "");
    const fieldMeta = [appName, axDescription, axHelp, axTitle, axPlaceholder].join(" ");
    const mode = inferMode(requestedMode, bundleId, url, ctx, fieldMeta);
    const dictionary = getRequestDictionary(body);
    const correctedInput = applyDictionaryReplacements(applySelfCorrections(text), dictionary);

    console.log(
      "📨 mode:",
      requestedMode,
      "->",
      mode,
      "| style:",
      style,
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
      "| ctxChars:",
      ctx.length
    );
    if (dictionary.terms.length || dictionary.replacements.length) {
      console.log("📚 dictionary(active): terms", dictionary.terms.length, "| replacements", dictionary.replacements.length);
    }

    const langRule = `Output language must be ${lang}. Do not translate into any other language.`;
    const modeRule = MODE_RULES[mode] || MODE_RULES.generic;
    const styleRule = STYLE_RULES[style] || STYLE_RULES.clean;
    const dictionaryRule = buildDictionaryPromptClause(dictionary);

    let contextBlock = "";
    if (mode !== "generic") {
      if (url) contextBlock += `\nURL: ${url}`;
      if (ctx) contextBlock += `\nContext: ${ctx}`;
    }

    const noGreetingRule = mode === "email_body"
      ? ""
      : "No added greetings/sign-offs unless already present.";
    const singleDraftRule = "Return exactly one final draft only. Never include alternatives, translations, duplicate versions, or placeholders like [Your Name].";
    const correctionRule = "If user self-corrects (e.g. 'nei, jeg mener', 'eller nei', 'no, I mean'), keep only the final corrected detail and remove superseded earlier versions.";
    const fidelityRule = "Do not invent new facts, topics, requests, names, or questions. Rewrite only what is explicitly in the input.";
    const recipientRule = mode === "email_body"
      ? "If multiple recipient names appear, keep the latest explicit recipient name and use it consistently."
      : "";
    const system = `Polish punctuation and phrasing, keep meaning. ${modeRule} ${styleRule} ${langRule} ${noGreetingRule} ${singleDraftRule} ${correctionRule} ${fidelityRule} ${recipientRule} ${dictionaryRule} Return JSON only: {"language":"...","text":"..."}${contextBlock}`;
    timings.preprocessMs = Date.now() - requestStartedAt;

    let language = lang;
    let finalText = normalizePunctuationArtifacts(
      applyStyleHeuristics(localPolish(correctedInput, mode), style, mode)
    );
    let usedFallback = false;

    if (!hasOpenAI) {
      usedFallback = true;
      console.warn("⚠️ OPENAI_API_KEY missing; using local fallback.");
    } else {
      const modelStartedAt = Date.now();
      try {
        const { response, attempts } = await requestModelDraft({
          system,
          user: correctedInput,
          requestSignal
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
          usedFallback = true;
        } else {
          const modelOut = sanitizeModelOutput(modelText, mode, lang);
          const normalizedModelOut = normalizePunctuationArtifacts(
            applyStyleHeuristics(localPolish(
              applyDictionaryReplacements(modelOut, dictionary),
              mode
            ), style, mode)
          );

          if (hasCriticalTimeDrift(correctedInput, normalizedModelOut)) {
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

    timings.totalMs = Date.now() - requestStartedAt;
    const retryCount = Math.max(0, (timings.modelAttempts?.length || 0) - 1);
    console.log("✅ ut:", safePreview(finalText, 80), usedFallback ? "[fallback]" : "", "| chars:", finalText.length);
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
    if (text.length > 10_000) return { status: 413, json: { error: "Too long." } };

    const instruction = String(body?.instruction || "").replace(/\s+/g, " ").trim();
    if (!instruction) return { status: 400, json: { error: "Missing instruction." } };
    if (instruction.length > 320) return { status: 413, json: { error: "Instruction too long." } };

    if (!hasOpenAI) {
      return { status: 503, json: { error: "Rewrite requires OPENAI_API_KEY." } };
    }

    const lang = normalizeTargetLanguage(body?.targetLanguage);
    const style = normalizeStyle(body?.style);
    const dictionary = getRequestDictionary(body);
    const correctedInput = applyDictionaryReplacements(applySelfCorrections(text), dictionary);

    const langRule = `Output language must be ${lang}. Do not translate into any other language.`;
    const styleRule = STYLE_RULES[style] || STYLE_RULES.clean;
    const dictionaryRule = buildDictionaryPromptClause(dictionary);
    const safetyRule = "Keep names, dates, numbers, and factual content unless the instruction explicitly requests changing them.";
    const singleDraftRule = "Return exactly one final draft only. Never include alternatives, notes, prefixes, or placeholders.";
    const system = `Apply the user instruction to the provided text. ${styleRule} ${langRule} ${safetyRule} ${singleDraftRule} ${dictionaryRule} Return JSON only: {"language":"...","text":"..."}`;
    timings.preprocessMs = Date.now() - requestStartedAt;

    const modelStartedAt = Date.now();
    const { response, attempts } = await requestModelDraft({
      system,
      user: `Instruction:\n${instruction}\n\nText:\n${correctedInput}`,
      requestSignal
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

    let finalText = sanitizeModelOutput(modelText, "generic", lang);
    finalText = normalizePunctuationArtifacts(
      applyDictionaryReplacements(finalText, dictionary)
    ).trim();
    if (!finalText) {
      return { status: 502, json: { error: "Model returned empty text." } };
    }
    if (isLikelyWrongForTarget(finalText, lang)) {
      return { status: 502, json: { error: "Model output language mismatch." } };
    }

    timings.postprocessMs = Date.now() - postprocessStartedAt;
    timings.totalMs = Date.now() - requestStartedAt;
    const retryCount = Math.max(0, (timings.modelAttempts?.length || 0) - 1);
    console.log("✏️ rewrite:", safePreview(finalText, 80), "| chars:", finalText.length, "| retries:", retryCount);

    return {
      status: 200,
      json: {
        language: lang,
        text: finalText,
        appliedStyle: style,
        instruction,
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
        }
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
      sendJson(req, res, auth.status, { error: auth.error });
      return;
    }
    sendJson(req, res, 200, {
      tag: BACKEND_TAG,
      ...summarizePolishMetrics()
    });
    return;
  }

  if (method === "POST" && url.pathname === "/polish") {
    const endpointStartedAt = Date.now();
    const auth = await verifyToken(req);
    if (!auth.ok) {
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
      sendJson(req, res, parsed.status, { error: parsed.error }, {
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
