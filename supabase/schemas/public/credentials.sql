-- Create credentials table
create table credentials (
  user_id uuid primary key references users(id) on delete cascade,
  encrypted_data text not null,
  iv text not null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table credentials is 'Encrypted user credentials';

-- Add date management triggers
create trigger credentials_update_dates
before update on credentials
for each row
execute function update_dates();

create trigger credentials_insert_dates
before insert on credentials
for each row
execute function insert_dates();

-- Enable RLS
alter table credentials enable row level security;

-- Allow read access for own credentials only
create policy credentials_select on credentials
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Allow creation of own credentials only
create policy credentials_insert on credentials
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Disallow updates for all users
-- Disallow deletion for all users