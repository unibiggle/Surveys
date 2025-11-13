-- Create private bucket for attachments
-- Prefer inserting into storage.buckets for maximum compatibility
do $$ begin
  if not exists (select 1 from storage.buckets where id = 'attachments') then
    insert into storage.buckets (id, name, public)
    values ('attachments', 'attachments', false);
  end if;
end $$;

-- Storage policies for attachments bucket
-- Folder convention: attachments/{team_id}/{survey_id}/{filename}

-- Allow team members to read objects under their team/survey folders
drop policy if exists "attachments_select" on storage.objects;
create policy "attachments_select" on storage.objects
for select to authenticated using (
  bucket_id = 'attachments'
  and exists (
    select 1 from public.memberships m
    join public.surveys s on s.team_id = m.team_id
    where m.user_id = auth.uid()
      and split_part(name, '/', 1) = m.team_id::text
      and split_part(name, '/', 2) = s.id::text
  )
);

-- Allow team members to upload into their team/survey folders
drop policy if exists "attachments_insert" on storage.objects;
create policy "attachments_insert" on storage.objects
for insert to authenticated with check (
  bucket_id = 'attachments'
  and exists (
    select 1 from public.memberships m
    join public.surveys s on s.team_id = m.team_id
    where m.user_id = auth.uid()
      and split_part(name, '/', 1) = m.team_id::text
      and split_part(name, '/', 2) = s.id::text
  )
);

-- Allow owners/admins to delete objects under their team
drop policy if exists "attachments_delete" on storage.objects;
create policy "attachments_delete" on storage.objects
for delete to authenticated using (
  bucket_id = 'attachments'
  and exists (
    select 1 from public.memberships m
    join public.surveys s on s.team_id = m.team_id
    where m.user_id = auth.uid() and m.role in ('owner','admin')
      and split_part(name, '/', 1) = m.team_id::text
      and split_part(name, '/', 2) = s.id::text
  )
);
