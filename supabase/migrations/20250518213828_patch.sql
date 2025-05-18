alter table "public"."vault_values" add constraint "vault_values_value_check" CHECK ((char_length(value) <= 1024)) not valid;

alter table "public"."vault_values" validate constraint "vault_values_value_check";


