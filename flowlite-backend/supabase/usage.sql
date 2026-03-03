-- FlowSpeak: persistent daily usage counters for per-user caps
-- Apply in Supabase SQL editor after billing.sql if you want daily usage caps
-- to survive deploys and restarts.

create table if not exists public.daily_usage_counters (
  day_key date not null,
  principal_key text not null,
  plan text not null default 'free' check (plan in ('free', 'pro', 'team', 'enterprise')),
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  primary key (day_key, principal_key)
);

create index if not exists daily_usage_counters_day_idx
  on public.daily_usage_counters(day_key desc);

create index if not exists daily_usage_counters_plan_idx
  on public.daily_usage_counters(day_key desc, plan);

alter table public.daily_usage_counters enable row level security;

drop policy if exists "Service role can read daily usage counters" on public.daily_usage_counters;
create policy "Service role can read daily usage counters"
  on public.daily_usage_counters
  for select
  using (auth.role() = 'service_role');

drop policy if exists "Service role can insert daily usage counters" on public.daily_usage_counters;
create policy "Service role can insert daily usage counters"
  on public.daily_usage_counters
  for insert
  with check (auth.role() = 'service_role');

drop policy if exists "Service role can update daily usage counters" on public.daily_usage_counters;
create policy "Service role can update daily usage counters"
  on public.daily_usage_counters
  for update
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

drop policy if exists "Service role can delete daily usage counters" on public.daily_usage_counters;
create policy "Service role can delete daily usage counters"
  on public.daily_usage_counters
  for delete
  using (auth.role() = 'service_role');
