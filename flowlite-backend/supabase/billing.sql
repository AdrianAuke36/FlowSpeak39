-- FlowSpeak: Supabase billing table + JWT plan claim hook
-- Apply in Supabase SQL editor, then enable custom_access_token hook to call
-- public.custom_access_token_hook(event jsonb)

create table if not exists public.billing_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null default 'free' check (plan in ('free', 'pro', 'team', 'enterprise')),
  subscription_status text check (subscription_status in ('active', 'trialing', 'past_due', 'canceled', 'incomplete', 'incomplete_expired', 'unpaid', 'checkout_completed')),
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  current_period_end timestamptz,
  updated_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists billing_subscriptions_plan_idx
  on public.billing_subscriptions(plan);

create index if not exists billing_subscriptions_updated_at_idx
  on public.billing_subscriptions(updated_at desc);

create table if not exists public.billing_webhook_events (
  event_id text primary key,
  event_type text,
  received_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists billing_webhook_events_received_at_idx
  on public.billing_webhook_events(received_at desc);

alter table public.billing_subscriptions enable row level security;
alter table public.billing_webhook_events enable row level security;

-- Users can read only own subscription row.
drop policy if exists "Users can read own billing subscription" on public.billing_subscriptions;
create policy "Users can read own billing subscription"
  on public.billing_subscriptions
  for select
  using (auth.uid() = user_id);

-- Service role writes subscription state (Stripe webhook sync).
drop policy if exists "Service role can insert billing subscriptions" on public.billing_subscriptions;
create policy "Service role can insert billing subscriptions"
  on public.billing_subscriptions
  for insert
  with check (auth.role() = 'service_role');

drop policy if exists "Service role can update billing subscriptions" on public.billing_subscriptions;
create policy "Service role can update billing subscriptions"
  on public.billing_subscriptions
  for update
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

drop policy if exists "Service role can delete billing subscriptions" on public.billing_subscriptions;
create policy "Service role can delete billing subscriptions"
  on public.billing_subscriptions
  for delete
  using (auth.role() = 'service_role');

drop policy if exists "Service role can insert billing webhook events" on public.billing_webhook_events;
create policy "Service role can insert billing webhook events"
  on public.billing_webhook_events
  for insert
  with check (auth.role() = 'service_role');

drop policy if exists "Service role can read billing webhook events" on public.billing_webhook_events;
create policy "Service role can read billing webhook events"
  on public.billing_webhook_events
  for select
  using (auth.role() = 'service_role');

create or replace function public.current_user_plan()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select b.plan from public.billing_subscriptions b where b.user_id = auth.uid()),
    'free'
  );
$$;

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  claims jsonb;
  user_plan text;
  uid uuid;
begin
  uid := nullif(event->>'user_id', '')::uuid;

  claims := coalesce(event->'claims', '{}'::jsonb);

  if uid is null then
    claims := jsonb_set(claims, '{plan}', to_jsonb('free'::text), true);
    return jsonb_set(event, '{claims}', claims, true);
  end if;

  select coalesce(b.plan, 'free')
    into user_plan
    from public.billing_subscriptions b
   where b.user_id = uid;

  if user_plan is null then
    user_plan := 'free';
  end if;

  claims := jsonb_set(claims, '{plan}', to_jsonb(user_plan), true);
  return jsonb_set(event, '{claims}', claims, true);
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant select on table public.billing_subscriptions to supabase_auth_admin;
grant select on table public.billing_webhook_events to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public;
