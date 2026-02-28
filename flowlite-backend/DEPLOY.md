# FlowSpeak Backend Deploy (Supabase + Stripe)

## 1) Configure environment
Copy `.env.example` and set at minimum:

- `OPENAI_API_KEY`
- `REQUIRE_AUTH=true`
- `HOST=0.0.0.0`
- `ALLOWED_ORIGINS`

For production, you can start from:
- `env.production.template`

Auth options:
- static token(s): `FLOWSPEAK_API_TOKENS`
- self-signed HS256 JWT: `FLOWSPEAK_JWT_SECRET` / `FLOWSPEAK_JWT_SECRETS`
- Supabase JWT (recommended): `SUPABASE_URL` (or `SUPABASE_JWKS_URL` + `SUPABASE_JWT_ISSUER`)

## 2) Supabase billing schema + claim hook
Apply:
- `supabase/billing.sql`

This creates:
- `public.billing_subscriptions`
- helper function `public.current_user_plan()`
- custom access token hook function `public.custom_access_token_hook(event jsonb)`

Then in Supabase dashboard, set Auth Hook `custom_access_token` to this function.

## 3) Stripe webhook + Supabase sync
Set these env vars on backend:
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_SECRET_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `STRIPE_PRICE_PLAN_MAP` (JSON map from Stripe price IDs to plans)

Webhook endpoint:
- `POST /stripe/webhook`
  - verified with `Stripe-Signature` + `STRIPE_WEBHOOK_SECRET`

Expected event types:
- `checkout.session.completed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`

Stripe CLI test:
```bash
stripe listen --forward-to http://127.0.0.1:3000/stripe/webhook
```

## 4) Run
```bash
npm ci
npm run start:prod
```

Container:
```bash
docker build -t flowspeak-backend .
docker run --rm -p 3000:3000 --env-file .env flowspeak-backend
```

### Temporary public beta (no auth)
Use only for short external testing while auth is not finished:

- Start from `env.public-beta.template`
- Or deploy with `fly.public-beta.toml`
- This runs with `REQUIRE_AUTH=false`

Example local beta run:
```bash
cp env.public-beta.template .env
npm run start:prod
```

## 5) Endpoints
- `GET /health`
- `GET /ready` (returns `503` until required launch dependencies are configured)
- `GET /version`
- `GET /metrics`
- `POST /polish`
- `POST /rewrite`
- `POST /stripe/webhook`

## 6) Auth + rate limit behavior
Headers accepted:
- `Authorization: Bearer <token>`
- `X-FlowSpeak-Token: <token>`

Plan claim:
- `plan`: `free|pro|team|enterprise`

Rate limit headers:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`
- `X-Auth-Plan`

For multi-instance/global limits configure:
- `RATE_LIMIT_REDIS_URL`
- `RATE_LIMIT_REDIS_TOKEN`
- `RATE_LIMIT_REDIS_PREFIX` (optional)

## 7) Latency checks (700ms target)
Useful tuning knobs:
- `POLISH_LOCAL_FASTPATH_ENABLED=true` (skip model for short generic clean dictation)
- `POLISH_LOCAL_FASTPATH_MAX_CHARS=90`
- `POLISH_LOCAL_FASTPATH_MAX_WORDS=18`
- `OPENAI_MAX_TOKENS_POLISH_SHORT=96`
- `OPENAI_MAX_TOKENS_POLISH=120`
- `OPENAI_MAX_TOKENS_POLISH_EMAIL_BODY=180`
- `OPENAI_MAX_TOKENS_REWRITE=180`

Warm path:
```bash
npm run latency:smoke -- --url http://127.0.0.1:3000 --n 50 --c 10 --budget 700 --mode email_body --lang nb-NO
```

Cold path (cache bypass):
```bash
FLOWSPEAK_BENCH_TOKEN='token-or-jwt' npm run latency:smoke -- --url https://api.your-domain.com --n 80 --c 15 --budget 700 --cache-bypass true --unique-text true
```

Mixed profile:
```bash
FLOWSPEAK_BENCH_TOKEN='token-or-jwt' npm run latency:profile -- --url https://api.your-domain.com --n 30 --c 8 --budget 700 --cache-bypass true --strict-scenario true
```

## 8) Fly.io starter (multi-region)
```bash
fly launch --no-deploy
fly secrets set OPENAI_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... STRIPE_WEBHOOK_SECRET=... STRIPE_SECRET_KEY=...
fly deploy
```

Start with at least two regions close to user base.

Public beta variant:
```bash
fly launch --no-deploy --copy-config --config fly.public-beta.toml
fly secrets set OPENAI_API_KEY=...
fly deploy --config fly.public-beta.toml
```

## 8b) Render starter (recommended permanent baseline)
This repo includes a root-level `render.yaml` configured for:

- service name: `flowspeak-backend`
- runtime: Docker
- plan: `starter`
- health check: `/ready`
- Supabase JWT auth enabled

Render setup:
1. Push the repo to GitHub.
2. In Render, create a new Blueprint service from the repo root.
3. Render will detect `render.yaml`.
4. Set the required secret:
   - `OPENAI_API_KEY`
5. Deploy.

After first deploy, your backend will be available at a Render URL based on the service name in `render.yaml`, for example:
- `https://flowspeak-backend.onrender.com`

If the name is already taken, change the service name in the root `render.yaml` before creating the Blueprint.

If you later add a custom domain, point your app to:
- `https://api.your-domain.com`

Optional production envs to add in Render after initial deploy:
- `SUPABASE_SERVICE_ROLE_KEY` (only if billing sync is enabled)
- `STRIPE_SECRET_KEY` (only if Pro billing is enabled)
- `STRIPE_WEBHOOK_SECRET` (only if Pro billing is enabled)
- `STRIPE_PRICE_PLAN_MAP` (only if Pro billing is enabled)

## 9) Launch verification (public URL)
After deploy, run:
```bash
FLOWSPEAK_BENCH_TOKEN='<jwt-or-token>' npm run launch:check -- --url https://api.your-domain.com --origin https://flow-speak-direct.lovable.app --timeout 2500
```

- `--token` (or `FLOWSPEAK_BENCH_TOKEN`) validates auth endpoints (`/version`, `/metrics`, `/polish`, `/rewrite`).
- `--origin` validates CORS preflight.
