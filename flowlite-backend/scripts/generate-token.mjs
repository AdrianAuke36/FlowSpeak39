import crypto from "node:crypto";

const bytes = Number(process.argv[2] || 24);
if (!Number.isFinite(bytes) || bytes < 16 || bytes > 64) {
  console.error("Usage: node scripts/generate-token.mjs [16-64]");
  process.exit(1);
}

const token = `fs_${crypto.randomBytes(bytes).toString("base64url")}`;
const fingerprint = crypto.createHash("sha256").update(token).digest("hex").slice(0, 16);

console.log("token:", token);
console.log("fingerprint:", fingerprint);
console.log("example env append:");
console.log(`FLOWSPEAK_API_TOKENS=...,${token}`);

