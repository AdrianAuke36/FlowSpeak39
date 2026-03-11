# BlueSpeak Gamification V1 Plan

## Goal
Create a simple Duolingo-style motivation loop that increases daily retention without adding friction to core dictation speed.

## V1 Product Loop
1. User dictates/translates/rewrites.
2. User earns XP immediately.
3. Daily mission progress updates in Home + Sidebar.
4. Streak updates once per day.
5. Milestone badge appears (level up, streak milestones).

## Scoring Rules (V1)
- Dictate: `+1 XP` per word.
- Translate: `+1 XP` per word + `+10 XP` action bonus.
- Rewrite: `+1 XP` per word + `+8 XP` action bonus.
- Daily mission complete: `+50 XP`.
- Streak bonus (days 3, 7, 14, 30): `+25 / +50 / +100 / +250 XP`.

## Daily Missions (V1)
- Mission 1: Dictate `>= 120 words`.
- Mission 2: Complete `>= 3` dictations.
- Mission 3: Complete `>= 1` translate or rewrite action.
- Mission is complete when all 3 are done.

## Level Formula
- `level = floor(sqrt(xp / 120) + 1)`
- `xpToNextLevel = ((level)^2 * 120) - xp`

## Data Model (Supabase)
SQL file: [gamification.sql](/Users/adrianauke/Documents/FlowSpeak/flowlite-backend/supabase/gamification.sql)

Main tables:
- `public.gamification_profiles`
  - Current XP/level/streak snapshot per `principal_key`
- `public.gamification_daily_progress`
  - Daily counters (words/actions/challenges/xp)
- `public.gamification_events`
  - Append-only event log for analytics/debug

Main SQL function:
- `public.gamification_record_event(...)`
  - Inserts event
  - Upserts daily progress
  - Updates streak, level and profile snapshot

## Backend Integration (Server)
Recommended implementation order in `/flowlite-backend/server.js`:
1. Add env toggle:
   - `GAMIFICATION_ENABLED=true|false`
2. After successful `/polish` and `/rewrite` responses:
   - Call `gamification_record_event` with:
     - `principal_key = auth.tokenHash`
     - `plan = auth.plan`
     - `event_type = dictate|translate|rewrite`
     - `words_count = output word count`
     - `xp_delta = calculated XP`
3. Add `GET /gamification`:
   - Returns profile + today progress + mission status for current user.
4. Add `GET /gamification/leaderboard` (optional later):
   - Global top XP (anonymized principal key).

## UI Integration (App)
Main file targets:
- [HomeView.swift](/Users/adrianauke/Documents/FlowSpeak/BlueSpeak/HomeView.swift)
- [SettingsView.swift](/Users/adrianauke/Documents/FlowSpeak/BlueSpeak/SettingsView.swift)

V1 UI surfaces:
1. Home top cards:
   - `Level`
   - `Streak`
   - `Time saved today` (already exists)
2. Home section:
   - `Daily mission` progress (3 checklist rows)
3. Sidebar:
   - Small streak chip (`🔥 4 days`)
   - Daily mission progress bar
4. Level-up feedback:
   - Reuse lightweight popup style (same animation language as existing save popup).

## Rollout Plan
1. **Phase 1 (safe)**: Local UI from existing history data only.
2. **Phase 2**: Write gamification events to Supabase from backend.
3. **Phase 3**: Read `/gamification` in app and replace local approximation.
4. **Phase 4**: A/B test reward tuning (XP weights and mission thresholds).

## KPIs to Track
- D1/D7 retention
- Dictations per active user/day
- Words per active user/day
- % users completing daily mission
- Median session count/user/day

## Guardrails
- No blocking UX: dictation must always work if gamification storage fails.
- Gamification writes must be async/non-blocking.
- If Supabase fails, keep local fallback counters and log warning only.
- Keep UI minimal: motivation cues, no noisy interruptions.

