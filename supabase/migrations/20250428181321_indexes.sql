create extension if not exists "hypopg" with schema "extensions";

create extension if not exists "index_advisor" with schema "extensions";


CREATE INDEX collection_apps_collection_id_idx ON public.collection_apps USING btree (collection_id);

CREATE INDEX collection_relations_parent_id_idx ON public.collection_relations USING btree (parent_id);

CREATE INDEX collections_private_idx ON public.collections USING btree (private);

CREATE INDEX collections_title_idx ON public.collections USING btree (title);
