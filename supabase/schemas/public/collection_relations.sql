-- Create collection_relations table
create table collection_relations (
  collection_id text not null references collections(id) on delete cascade,
  parent_id text not null references collections(id) on delete cascade,
  primary key (collection_id, parent_id),
  check (collection_id != parent_id)
);

-- Add table comment
comment on table collection_relations is 'Many-to-many relationships between collections';

-- Add indexes
create index collection_relations_parent_id_idx on public.collection_relations using btree (parent_id);

-- Enable RLS
alter table collection_relations enable row level security;

-- Allow read for public collections and own collections
create policy collection_relations_select on collection_relations
for select
to authenticated, anon
using (
  exists (select 1 from collections c where c.id = collection_id and (not c.private or c.user_id = (select auth.uid())))
  and
  exists (select 1 from collections p where p.id = parent_id and (not p.private or p.user_id = (select auth.uid())))
);

-- Allow creation when user owns the parent collection and child is public
create policy collection_relations_insert on collection_relations
for insert
to authenticated
with check (
  (
    select user_id from collections
    where id = parent_id
  ) = (select auth.uid()
  )
  and
  exists (
    select 1 from collections
    where id = collection_id and not private
  )
);

-- Allow update when user owns the parent collection and new child is public
create policy collection_relations_update on collection_relations
for update
to authenticated
using (
  (
    select user_id from collections
    where id = parent_id
  ) = (select auth.uid())
)
with check (
  (
    select user_id from collections
    where id = parent_id
  ) = (select auth.uid())
  and exists (
    select 1 from collections
    where id = collection_id and not private
  )
);

-- Allow deletion when user owns the parent collection
create policy collection_relations_delete on collection_relations
for delete
to authenticated
using (
  (
    select user_id from collections
    where id = parent_id
  ) = (select auth.uid()
  )
);

-- Create trigger function to prevent adding parents to master collections
create or replace function prevent_master_collection_parent()
returns trigger
set search_path = ''
as $$
begin
  if exists (select 1 from public.collections where id = new.collection_id and master = true) then
    raise exception 'Cannot add parent to a master collection';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger prevent_master_collection_parent_trigger
before insert or update on collection_relations
for each row
execute function prevent_master_collection_parent();