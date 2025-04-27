# SteamKey.Trade

SteamKey.Trade is a platform for Steam product key trading. It features a secure vault for managing Steam keys, a robust trading system for exchanging keys with other users, and customizable collections to organize and showcase the apps, which is what can be activated by your keys on Steam.

## Technology Stack

- **Nuxt 3** for frontend architecture.
- **Supabase** as the backend (PostgreSQL, Auth, and Edge Functions).
- **Vuetify** for UI components.
- **Custom ORM** for data layer abstraction.
- **Deno** for serverless functions via Supabase Edge.

---

## Global Conventions

- Do not use typescript in this project.
- **Use `script setup`** syntax.
- **Imports go at the top**, followed by props and global instances, and at the bottom metadata (such as `title`, `breadcrumbs`, `useHead`, `definePageMeta`).
- Group **related code together** in script setup.
- **Use arrow functions** in watchers.
- **Use `useLazyAsyncData`** for data fetching. Only fetch a single data source at a time, and reuse the same key for the same data source across components.
- **Use Vuetify classes** for styling.
- **Use `useORM()`** to access ORM entities, for any data interaction.
- **Use `useSupabaseClient()`** to access the Supabase client, for any direct Supabase interaction or for the ORM static methods (such as `User.login(supabase, verify)`)

---

## ORM Best Practices

The project uses a custom ORM system via `BaseEntity`, extended by each entity (like `User`, `Collection`, `App`).

### ORM Utilities

- **`toDB()` / `fromDB()`**: Map ORM fields to/from raw Supabase records.
- Use `Entity.fields.fieldName` to access field metadata (especially inside data tables).
- Use ORM metadata:
  - `Entity.labels`
  - `Entity.descriptions`
  - `Entity.icons`
  - `Entity.enums`
  - `Entity.table`
  - `Entity.fields`
  - `Entity.colors`
  - `Entity.<relatedEntity>.<table/fields>` (e.g., `Trade.apps.table`)

### Composables

Use `useORM()` like this:

```js
const { User, Collection } = useORM();
```

- It injects the Supabase client automatically.
- Prefer destructured entity usage.

---

## Data Fetching

Always prefer `useLazyAsyncData`:

```js
const { User } = useORM();
const { data: users } = await useLazyAsyncData(`user-${id}`, () => {
  const instance = new User(id);
  await instance.load();
  return instance.toObject();
});
```

- **Reuse the same key** for the same data source across components for caching.

---

## Data Tables

For dynamic tables like `TableData`, `TableApps`, and `TableCollections`:

- Fields are accessed directly as: `item[Entity.fields.fieldName]`.

Example:

```js
headers: [
  { text: User.labels.username, value: User.fields.username },
  { text: User.labels.email, value: User.fields.email },
]
```

---

## Supabase Functions

- Edge Functions are written in Deno under `supabase/functions/`.
- Register functions in `supabase/config.toml` with entrypoint pointing to the function's `index.js` file.
- Use javascript, not typescript, for the functions.

---

## Naming & Structure

- Match filenames to their components/pages/classes.
- Use PascalCase for classes/entities.
- Use camelCase for variables and functions.
- Components go under domain folders (`App/`, `Collection/`, `User/`).

---