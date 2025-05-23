set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.is_allowed_host(url text, allowed_hosts text[])
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE STRICT
 SET search_path TO ''
AS $function$
declare
  raw_host text;
  host text;
  pattern text;
  regex_pattern text;
begin
  if url !~ '^https?://' then
    return false;
  end if;

  raw_host := substring(url from '^https?://([^/]+)');
  raw_host := regexp_replace(raw_host, '^[^@]+@', '');
  host := regexp_replace(raw_host, ':\d+$', '');

  foreach pattern in array allowed_hosts loop
    regex_pattern := '^' || replace(pattern, '*', '.*') || '$';
    if host ~ regex_pattern then
      return true;
    end if;
  end loop;

  return false;
end;
$function$
;

alter table "public"."users" add constraint "users_avatar_check" CHECK (((avatar IS NULL) OR is_allowed_host(avatar, ARRAY['localhost'::text, '127.0.0.1'::text, 'avatars.steamstatic.com'::text, '*.supabase.co'::text]))) not valid;

alter table "public"."users" validate constraint "users_avatar_check";

alter table "public"."users" add constraint "users_background_check" CHECK (((background IS NULL) OR is_allowed_host(background, ARRAY['localhost'::text, '127.0.0.1'::text, '*.supabase.co'::text]))) not valid;

alter table "public"."users" validate constraint "users_background_check";

