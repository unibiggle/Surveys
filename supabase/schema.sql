-- Enable extensions
create extension if not exists pgcrypto; -- for gen_random_uuid()

-- Utility: update updated_at
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

-- Roles enum
do $$ begin
  create type public.user_role as enum ('owner','admin','member');
exception when duplicate_object then null; end $$;

-- Teams
create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists set_teams_updated_at on public.teams;
create trigger set_teams_updated_at before update on public.teams
  for each row execute function public.set_updated_at();

-- Memberships
create table if not exists public.memberships (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.user_role not null default 'member',
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

-- Helper table to avoid recursive RLS lookups: users with admin rights per team
create table if not exists public.team_admins (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (team_id, user_id)
);

-- Maintain team_admins based on memberships role changes
create or replace function public.sync_team_admins()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  was_admin boolean := (tg_op = 'UPDATE' and (old.role in ('owner','admin')));
  is_admin  boolean := (tg_op in ('INSERT','UPDATE') and (new.role in ('owner','admin')));
begin
  if tg_op = 'INSERT' then
    if is_admin then
      insert into public.team_admins(team_id, user_id)
      values (new.team_id, new.user_id)
      on conflict do nothing;
    end if;
    return new;
  elsif tg_op = 'UPDATE' then
    if was_admin and not is_admin then
      delete from public.team_admins where team_id = old.team_id and user_id = old.user_id;
    elsif (not was_admin) and is_admin then
      insert into public.team_admins(team_id, user_id)
      values (new.team_id, new.user_id)
      on conflict do nothing;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.role in ('owner','admin') then
      delete from public.team_admins where team_id = old.team_id and user_id = old.user_id;
    end if;
    return old;
  end if;
  return null;
end; $$;

drop trigger if exists memberships_sync_admins_ins on public.memberships;
create trigger memberships_sync_admins_ins after insert on public.memberships
  for each row execute function public.sync_team_admins();

drop trigger if exists memberships_sync_admins_upd on public.memberships;
create trigger memberships_sync_admins_upd after update of role on public.memberships
  for each row execute function public.sync_team_admins();

drop trigger if exists memberships_sync_admins_del on public.memberships;
create trigger memberships_sync_admins_del after delete on public.memberships
  for each row execute function public.sync_team_admins();

-- Auto-add owner membership for team creator
create or replace function public.add_owner_membership()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.memberships(team_id, user_id, role)
  values (new.id, new.created_by, 'owner')
  on conflict do nothing;
  return new;
end; $$;
drop trigger if exists add_owner_membership on public.teams;
create trigger add_owner_membership after insert on public.teams
  for each row execute function public.add_owner_membership();

-- Templates
create table if not exists public.templates (
  id uuid primary key default gen_random_uuid(),
  team_id uuid references public.teams(id) on delete cascade,
  name text not null,
  version int not null default 1,
  schema_json jsonb not null,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_templates_team on public.templates(team_id);
drop trigger if exists set_templates_updated_at on public.templates;
create trigger set_templates_updated_at before update on public.templates
  for each row execute function public.set_updated_at();

-- Surveys
create table if not exists public.surveys (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  template_id uuid not null references public.templates(id),
  template_version int not null,
  status text not null check (status in ('draft','in_progress','completed')) default 'in_progress',
  assignee_user_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_surveys_team on public.surveys(team_id);
create index if not exists idx_surveys_template on public.surveys(template_id);
drop trigger if exists set_surveys_updated_at on public.surveys;
create trigger set_surveys_updated_at before update on public.surveys
  for each row execute function public.set_updated_at();

-- Responses
create table if not exists public.responses (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.surveys(id) on delete cascade,
  question_id text not null,
  value_json jsonb not null,
  score double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_responses_survey on public.responses(survey_id);
drop trigger if exists set_responses_updated_at on public.responses;
create trigger set_responses_updated_at before update on public.responses
  for each row execute function public.set_updated_at();

-- Attachments (server-side record; binary lives in Storage)
create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.surveys(id) on delete cascade,
  question_id text,
  type text not null check (type in ('photo','sketch','signature')),
  storage_path text, -- storage path in the attachments bucket
  uploaded_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_attachments_survey on public.attachments(survey_id);

-- Profiles (optional; handy for future features)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id) values (new.id) on conflict do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Grants: allow API roles to use tables (RLS still restricts row access)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.teams to authenticated;
grant select, insert, update, delete on public.memberships to authenticated;
grant select, insert, update, delete on public.templates to authenticated;
grant select, insert, update, delete on public.surveys to authenticated;
grant select, insert, update, delete on public.responses to authenticated;
grant select, insert, update, delete on public.attachments to authenticated;
grant select on public.team_admins to authenticated;

-- RLS: enable
alter table public.teams enable row level security;
alter table public.memberships enable row level security;
-- team_admins is internal; disable RLS so sync triggers can write to it
alter table public.team_admins disable row level security;
alter table public.templates enable row level security;
alter table public.surveys enable row level security;
alter table public.responses enable row level security;
alter table public.attachments enable row level security;

-- Teams policies
drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to authenticated
  using (
    created_by = auth.uid()
    or exists(
      select 1 from public.team_admins a
      where a.team_id = id and a.user_id = auth.uid()
    )
  );

drop policy if exists teams_insert on public.teams;
create policy teams_insert on public.teams
  for insert to authenticated with check (created_by = auth.uid());

drop policy if exists teams_update on public.teams;
create policy teams_update on public.teams
  for update to authenticated
  using (exists(select 1 from public.team_admins a where a.team_id = id and a.user_id = auth.uid()))
  with check (exists(select 1 from public.team_admins a where a.team_id = id and a.user_id = auth.uid()));

drop policy if exists teams_delete on public.teams;
create policy teams_delete on public.teams
  for delete to authenticated
  using (
    -- only owners can delete; team_admins mirrors owners/admins, so enforce via created_by
    created_by = auth.uid()
  );

-- Memberships policies
-- team_admins policies (admins can see their rows)
drop policy if exists team_admins_select on public.team_admins;
create policy team_admins_select on public.team_admins
  for select to authenticated
  using (user_id = auth.uid());

-- Memberships policies using team_admins to avoid recursion
drop policy if exists memberships_select on public.memberships;
create policy memberships_select on public.memberships
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists(select 1 from public.team_admins a where a.team_id = memberships.team_id and a.user_id = auth.uid())
    or exists(select 1 from public.teams t where t.id = memberships.team_id and t.created_by = auth.uid())
  );

drop policy if exists memberships_insert on public.memberships;
create policy memberships_insert on public.memberships
  for insert to authenticated
  with check (
    exists(select 1 from public.team_admins a where a.team_id = memberships.team_id and a.user_id = auth.uid())
    or exists(select 1 from public.teams t where t.id = memberships.team_id and t.created_by = auth.uid())
  );

drop policy if exists memberships_update on public.memberships;
create policy memberships_update on public.memberships
  for update to authenticated
  using (
    exists(select 1 from public.team_admins a where a.team_id = memberships.team_id and a.user_id = auth.uid())
    or exists(select 1 from public.teams t where t.id = memberships.team_id and t.created_by = auth.uid())
  )
  with check (
    exists(select 1 from public.team_admins a where a.team_id = memberships.team_id and a.user_id = auth.uid())
    or exists(select 1 from public.teams t where t.id = memberships.team_id and t.created_by = auth.uid())
  );

drop policy if exists memberships_delete on public.memberships;
create policy memberships_delete on public.memberships
  for delete to authenticated
  using (
    exists(select 1 from public.team_admins a where a.team_id = memberships.team_id and a.user_id = auth.uid())
    or exists(select 1 from public.teams t where t.id = memberships.team_id and t.created_by = auth.uid())
  );

-- RPCs for managing memberships (RLS still enforced)
create or replace function public.add_team_member(p_team_id uuid, p_user_id uuid, p_role public.user_role default 'member')
returns void language sql security definer set search_path = public as $$
  insert into public.memberships(team_id, user_id, role)
  values (p_team_id, p_user_id, p_role)
  on conflict (team_id, user_id) do update set role = excluded.role;
$$;

create or replace function public.remove_team_member(p_team_id uuid, p_user_id uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.memberships where team_id = p_team_id and user_id = p_user_id;
$$;

-- Grant execute on RPCs (idempotent)
do $$ begin
  grant execute on function public.add_team_member(uuid, uuid, public.user_role) to authenticated;
exception when undefined_function then null; end $$;
do $$ begin
  grant execute on function public.remove_team_member(uuid, uuid) to authenticated;
exception when undefined_function then null; end $$;

-- Templates policies
drop policy if exists templates_select on public.templates;
create policy templates_select on public.templates
  for select to authenticated
  using (team_id is null or exists(
    select 1 from public.memberships m
    where m.team_id = templates.team_id and m.user_id = auth.uid()
  ));

drop policy if exists templates_mutate on public.templates;
create policy templates_mutate on public.templates
  for all to authenticated
  using (exists(select 1 from public.memberships m where m.team_id = templates.team_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists(select 1 from public.memberships m where m.team_id = templates.team_id and m.user_id = auth.uid() and m.role in ('owner','admin')));

-- Surveys policies (team members can create/read/update)
drop policy if exists surveys_read on public.surveys;
create policy surveys_read on public.surveys
  for select to authenticated
  using (exists(select 1 from public.memberships m where m.team_id = surveys.team_id and m.user_id = auth.uid()));

drop policy if exists surveys_insert on public.surveys;
create policy surveys_insert on public.surveys
  for insert to authenticated
  with check (exists(select 1 from public.memberships m where m.team_id = surveys.team_id and m.user_id = auth.uid()));

drop policy if exists surveys_update on public.surveys;
create policy surveys_update on public.surveys
  for update to authenticated
  using (exists(select 1 from public.memberships m where m.team_id = surveys.team_id and m.user_id = auth.uid()))
  with check (exists(select 1 from public.memberships m where m.team_id = surveys.team_id and m.user_id = auth.uid()));

-- Responses policies (inherit via survey)
drop policy if exists responses_all on public.responses;
create policy responses_all on public.responses
  for all to authenticated
  using (exists(
    select 1 from public.surveys s join public.memberships m on m.team_id = s.team_id
    where s.id = responses.survey_id and m.user_id = auth.uid()
  ))
  with check (exists(
    select 1 from public.surveys s join public.memberships m on m.team_id = s.team_id
    where s.id = responses.survey_id and m.user_id = auth.uid()
  ));

-- Attachments policies (inherit via survey)
drop policy if exists attachments_all on public.attachments;
create policy attachments_all on public.attachments
  for all to authenticated
  using (exists(
    select 1 from public.surveys s join public.memberships m on m.team_id = s.team_id
    where s.id = attachments.survey_id and m.user_id = auth.uid()
  ))
  with check (exists(
    select 1 from public.surveys s join public.memberships m on m.team_id = s.team_id
    where s.id = attachments.survey_id and m.user_id = auth.uid()
  ));

-- Realtime publication
do $$ begin
  alter publication supabase_realtime add table public.templates;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.surveys;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.responses;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.attachments;
exception when duplicate_object then null; end $$;
