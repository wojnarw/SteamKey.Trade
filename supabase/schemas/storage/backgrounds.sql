-- Create the 'backgrounds' bucket
insert into storage.buckets (id, name, public)
values ('backgrounds', 'backgrounds', true);

-- Allow read access for all users
create policy backgrounds_select on storage.objects
for select
to authenticated, anon
using (bucket_id = 'backgrounds');

-- Allow creation for authenticated users (upload their own backgrounds)
create policy backgrounds_insert on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'backgrounds' and owner_id = (select auth.uid()::text)
);

-- Allow update for own backgrounds only
create policy backgrounds_update on storage.objects
for update
to authenticated
using (
  bucket_id = 'backgrounds' and owner_id = (select auth.uid()::text)
)
with check (
  bucket_id = 'backgrounds' and owner_id = (select auth.uid()::text)
);

-- Allow deletion for own backgrounds only
create policy backgrounds_delete on storage.objects
for delete
to authenticated
using (
  bucket_id = 'backgrounds' and owner_id = (select auth.uid()::text)
);