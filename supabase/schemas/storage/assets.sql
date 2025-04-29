-- Create the 'assets' bucket
insert into storage.buckets (id, name, public)
values ('assets', 'assets', true);

-- Allow read access for all users
create policy assets_select on storage.objects
for select
to authenticated, anon
using (bucket_id = 'assets');

-- Disallow creation for all users
-- Disallow updates for all users
-- Disallow deletion for all users