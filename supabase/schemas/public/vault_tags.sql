-- Create vault_tags table
create table vault_tags (
  vault_entry_id uuid not null references vault_entries(id) on delete cascade,
  tag_id integer not null references tags(id) on delete cascade,
  body text default null,
  created_at timestamptz default now(),
  primary key (vault_entry_id, tag_id)
);

-- Add table comment
comment on table vault_tags is 'Tags associated with vault entries';

-- Add date management triggers
create trigger vault_tags_update_dates
before update on vault_tags
for each row
execute function update_dates();

create trigger vault_tags_insert_dates
before insert on vault_tags
for each row
execute function insert_dates();

-- Enable RLS
alter table vault_tags enable row level security;

-- Allow read access for own vault tags only
create policy vault_tags_select on vault_tags
for select
to authenticated
using (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- Allow creation for own vault tags only
create policy vault_tags_insert on vault_tags
for insert
to authenticated
with check (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- Allow update for own vault tags only
create policy vault_tags_update on vault_tags
for update
to authenticated
using (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);

-- Allow deletion for own vault tags only
create policy vault_tags_delete on vault_tags
for delete
to authenticated
using (
  exists (
    select 1 from vault_entries
    where
      id = vault_entry_id
      and user_id = (select auth.uid())
  )
);