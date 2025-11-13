Supabase Setup (Teams, Templates, Surveys, Sync)

Overview
- Project: Create a Supabase project (Auth + Postgres + Storage).
- Schema: Teams, memberships, templates, surveys, responses, attachments.
- RLS: Team‑scoped access (members see their team’s data).
- Storage: Private bucket for photos/sketches with team/survey folder policy.
- Realtime: Publish tables for live updates.

Steps
1) Create Project
- Go to supabase.com → New project.
- Choose a password and region. Wait for provisioning.

2) Enable Auth (Email)
- In Dashboard → Authentication → Providers → Email: enable Email (magic link or password, your choice).
- In Authentication → URL Configuration: set Site URL to your app’s callback domain (can be temporary during development).

3) Run Schema + Policies
- Open Dashboard → SQL Editor.
- Run `schema.sql` first, then `storage_policies.sql`.
  - This creates tables, triggers, RLS policies, storage bucket, and realtime publication.
  - If you already ran the earlier version, re-run `schema.sql` to apply the new memberships policies and the new `team_admins` table + triggers.

4) Realtime
- The SQL adds your tables to the `supabase_realtime` publication. Nothing else is needed.

5) Get Keys
- Dashboard → Project Settings → API: copy `Project URL` and `anon` public key.
- Put them in a new `.env` at repo root:
  - `SUPABASE_URL=...`
  - `SUPABASE_ANON_KEY=...`

6) First User + Team
- Sign up from your app (later), or temporarily create a user in Auth → Users.
- Create a team row setting `created_by` to that user’s UUID. Trigger auto‑adds owner membership.

7) App Integration (Flutter)
- The app already initializes Supabase from `.env` in `lib/services/supabase_service.dart`.
- After adding auth UI, the signed‑in user will see only their team’s data via RLS.

Notes
- “Everyone can see completed surveys” is interpreted as “everyone in the team”. Data is not public.
- Storage folder convention: `attachments/{team_id}/{survey_id}/{filename}`. Policies enforce this.

Admin Membership Management
- RLS on `memberships` no longer self-references the table (avoids recursion).
- A helper table `team_admins` mirrors members with `role in ('owner','admin')` via triggers.
- Policies now allow team creators or any current admin/owner to manage memberships.
- Use the RPCs from your app:
  - `add_team_member(team_id uuid, user_id uuid, role user_role = 'member')`
  - `remove_team_member(team_id uuid, user_id uuid)`
  Examples (JavaScript/Flutter):
  - JS: `supabase.rpc('add_team_member', { p_team_id: '...', p_user_id: '...', p_role: 'admin' })`
  - Flutter: `supabase.rpc('add_team_member', params: { 'p_team_id': teamId, 'p_user_id': userId, 'p_role': 'admin' })`

Safeguards
- RLS still applies inside the RPCs. Only team creators or current admins can mutate memberships.
- The initial owner membership is auto-created by a trigger on `teams` and then mirrored into `team_admins`.
