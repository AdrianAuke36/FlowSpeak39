import crypto from "node:crypto";

function toBase64Url(value) {
  return Buffer.from(value)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function signHs256(input, secret) {
  return toBase64Url(crypto.createHmac("sha256", secret).update(input).digest());
}

const secret = process.env.FLOWSPEAK_JWT_SECRET || process.env.JWT_SECRET || "";
if (!secret) {
  console.error("Missing FLOWSPEAK_JWT_SECRET or JWT_SECRET");
  process.exit(1);
}

const sub = process.argv[2] || `user_${Date.now()}`;
const plan = process.argv[3] || "pro";
const ttlSecRaw = Number(process.argv[4] || 2_592_000);
const ttlSec = Number.isFinite(ttlSecRaw) && ttlSecRaw > 0 ? Math.floor(ttlSecRaw) : 2_592_000;

const now = Math.floor(Date.now() / 1000);
const payload = {
  sub,
  plan,
  iat: now,
  nbf: now - 5,
  exp: now + ttlSec
};

const aud = String(process.env.FLOWSPEAK_JWT_AUDIENCE || "").trim();
const iss = String(process.env.FLOWSPEAK_JWT_ISSUER || "").trim();
if (aud) payload.aud = aud;
if (iss) payload.iss = iss;

const header = { alg: "HS256", typ: "JWT" };
const headerPart = toBase64Url(JSON.stringify(header));
const payloadPart = toBase64Url(JSON.stringify(payload));
const signingInput = `${headerPart}.${payloadPart}`;
const signature = signHs256(signingInput, secret);

process.stdout.write(`${signingInput}.${signature}\n`);
