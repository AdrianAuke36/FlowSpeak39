# FlowSpeak Backend Deploy (Supabase + Stripe)

## 1) Configure environment
Copy `.env.example` and set at minimum:

- `OPENAI_API_KEY`
- `REQUIRE_AUTH=true`
- `HOST=0.0.0.0`
- `ALLOWED_ORIGINS`

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
