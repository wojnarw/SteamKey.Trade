-- Create reviews table
create table reviews (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references users(id) on delete cascade check (subject_id != user_id),
  user_id uuid not null references users(id) on delete cascade check (user_id != subject_id),
  body text default null check (body is null or (length(body) between 1 and 5000)),
  speed integer not null check (speed between 1 and 5),
  communication integer not null check (communication between 1 and 5),
  helpfulness integer not null check (helpfulness between 1 and 5),
  fairness integer not null check (fairness between 1 and 5),
  updated_at timestamptz default null,
  created_at timestamptz default now(),
  unique (subject_id, user_id)
);

-- Add table comment
comment on table reviews is 'User reviews from trading partners';

-- Create trigger function to prevent changing subject_id
create or replace function reviews_prevent_subject_id_change()
returns trigger
set search_path = ''
as $$
begin
  if old.subject_id != new.subject_id then
    raise exception 'Cannot change subject_id in reviews';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger reviews_prevent_subject_id_change_trigger
before update on reviews
for each row
execute function reviews_prevent_subject_id_change();

-- Add date management triggers
create trigger reviews_update_dates
before update on reviews
for each row
execute function update_dates();

create trigger reviews_insert_dates
before insert on reviews
for each row
execute function insert_dates();

-- Enable RLS
alter table reviews enable row level security;

-- Allow read access for all users
create policy reviews_select on reviews
for select
to authenticated, anon
using (true);

-- Allow creation with multiple conditions:
-- 1. Reviewer must be the authenticated user
-- 2. Cannot review self
-- 3. Must have completed a trade with the user
create policy reviews_insert on reviews
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and user_id != subject_id
  and exists (
    select 1 from trades
    where
      status = 'completed'
      and (
        (sender_id = user_id and receiver_id = subject_id)
        or
        (sender_id = subject_id and receiver_id = user_id)
      )
  )
);

-- Allow update for own reviews only
create policy reviews_update on reviews
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Allow deletion for own reviews only
create policy reviews_delete on reviews
for delete
to authenticated
using ((select auth.uid()) = user_id);