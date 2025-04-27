<script setup>
  const { User } = useORM();
  const supabase = useSupabaseClient();

  const headers = [
    { title: User.labels.avatar, value: User.fields.avatar, sortable: false },
    { title: User.labels.displayName, value: User.fields.displayName, sortable: true },
    { title: User.labels.region, value: User.fields.region, sortable: true },
    { title: User.labels.bio, value: User.fields.bio, sortable: false },
    { title: User.labels.steamId, value: User.fields.steamId, sortable: true },
    { title: User.labels.createdAt, value: User.fields.createdAt, sortable: true }
  ];

  const queryGetter = () => {
    return supabase
      .from(User.table)
      .select([User.fields.id, ...headers.map(({ value }) => value)].join(','));
  };

  const title = 'Users';
  const breadcrumbs = [
    { title: 'Home', to: '/' },
    { title, disabled: true }
  ];

  useHead({ title });
</script>

<template>
  <s-page-content :breadcrumbs="breadcrumbs">
    <v-card class="h-100">
      <table-data
        class="h-100"
        :headers="headers"
        no-data-text="No users found"
        :query-getter="queryGetter"
        :search-field="User.fields.displayName"
        @click:row="(item) => navigateTo(`/user/${item[User.fields.customUrl] || item[User.fields.steamId]}`)"
      >
        <template #[`item.avatar`]="{ item }">
          <rich-profile-link
            hide-text
            :user-data="item"
            :user-id="item.id"
          />
        </template>

        <template #[`item.${User.fields.region}`]="{ item }">
          <span v-tooltip:top="User.labels[item.region]">
            {{ item.region }}
          </span>
        </template>

        <template #[`item.${User.fields.createdAt}`]="{ item }">
          <rich-date :date="item[User.fields.createdAt]" />
        </template>
      </table-data>
    </v-card>
  </s-page-content>
</template>