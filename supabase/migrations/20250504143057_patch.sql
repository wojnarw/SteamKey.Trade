CREATE UNIQUE INDEX updater_queue_type_value_key ON public.updater_queue USING btree (type, value);

alter table "public"."updater_queue" add constraint "updater_queue_type_value_key" UNIQUE using index "updater_queue_type_value_key";

create policy "updater_queue_insert"
on "public"."updater_queue"
as permissive
for insert
to authenticated
with check (((type = 'app_update'::updater_queue_type) AND (EXISTS ( SELECT 1
   FROM apps
  WHERE ((apps.id = (updater_queue.value)::integer) AND ((apps.updated_at IS NULL) OR (apps.updated_at < (now() - '24:00:00'::interval))))))));



