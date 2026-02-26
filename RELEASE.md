# FlowSpeak macOS Release Checklist

## 1) Build
- Build Release app from `FlowSpeak.xcodeproj` (`FlowSpeak` scheme).
- Verify `CFBundleIdentifier`, version, and build number.

## 2) Sign (Developer ID)
- Use Apple Developer ID Application certificate.
- Sign app:
```bash
codesign --deep --force --options runtime --sign "Developer ID Application: <Team Name> (<TEAM_ID>)" "FlowSpeak.app"
```
- Verify signature:
```bash
codesign --verify --deep --strict --verbose=2 "FlowSpeak.app"
spctl --assess --type execute --verbose "FlowSpeak.app"
```

## 3) Notarize
- Zip app:
```bash
ditto -c -k --keepParent "FlowSpeak.app" "FlowSpeak.zip"
```
- Submit and wait:
```bash
xcrun notarytool submit "FlowSpeak.zip" --keychain-profile "<NOTARY_PROFILE>" --wait
```
- Staple ticket:
```bash
xcrun stapler staple "FlowSpeak.app"
```

## 4) Backend Production Gate
- `REQUIRE_AUTH=true`
- Supabase JWT configured (`SUPABASE_URL` / JWKS)
- CORS allowlist configured (`ALLOWED_ORIGINS`)
- `/ready` returns `200`
- Stripe webhook secret + billing sync validated
- CI smoke test green (`npm test`)

## 5) Rollout
- Start with staged rollout (5-10% users), monitor:
  - `GET /metrics`
  - backend 5xx rates
  - latency (`modelMs`, `totalMs`)
- Roll to 100% after stability window (24-48h).
