-- Create collection_tags table
create table collection_tags (
  collection_id text not null references collections(id) on delete cascade,
  app_id integer not null references apps(id) on delete cascade,
  tag_id integer not null references tags(id) on delete cascade,
  body text default null,
  primary key (collection_id, app_id, tag_id)
);

-- Add table comment
comment on table collection_tags is 'Tags associated with apps in collections';

-- Create trigger
create trigger collection_tags_ensure_app_exists
before insert on collection_tags
for each row
execute function ensure_app_exists();

-- Enable RLS
alter table collection_tags enable row level security;

-- Allow read access for public collections and own collections
create policy collection_tags_select on collection_tags
for select
to authenticated, anon
using (
  exists (
    select 1 from collections
    where
      id = collection_id
      and (
        not private
        or user_id = (select auth.uid())
      )
  )
);

-- Allow creation for own collections only
create policy collection_tags_insert on collection_tags
for insert
to authenticated
with check (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
);

-- Allow update for own collections only
create policy collection_tags_update on collection_tags
for update
to authenticated
using (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
);

-- Allow deletion for own collections only
create policy collection_tags_delete on collection_tags
for delete
to authenticated
using (
  exists (
    select 1 from collections
    where
      id = collection_id
      and user_id = (select auth.uid())
  )
);