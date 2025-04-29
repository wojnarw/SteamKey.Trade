-- Create the 'avatars' bucket
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true);

-- Allow read access for all users
create policy avatars_select on storage.objects
for select
to authenticated, anon
using (bucket_id = 'avatars');

-- Allow creation for authenticated users (upload their own avatars)
create policy avatars_insert on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars' and owner_id = (select auth.uid()::text)
);

-- Allow update for own avatars only
create policy avatars_update on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars' and owner_id = (select auth.uid()::text)
)
with check (
  bucket_id = 'avatars' and owner_id = (select auth.uid()::text)
);

-- Allow deletion for own avatars only
create policy avatars_delete on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars' and owner_id = (select auth.uid()::text)
);