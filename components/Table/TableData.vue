<script setup>
  import { parseDate } from '~/assets/js/date';

  const snackbarStore = useSnackbarStore();
  const slots = useSlots();

  const emit = defineEmits(['click:row']);
  const props = defineProps({
    queryGetter: {
      type: Function,
      required: true
    },
    headers: {
      type: Array,
      required: true
    },
    defaultSortBy: {
      type: Array,
      default: () => []
    },
    sortDescFirst: {
      type: Boolean,
      default: false
    },
    mustSort: {
      type: Boolean,
      default: false
    },
    searchField: {
      type: [String, Boolean],
      default: false
    },
    simple: {
      type: Boolean,
      default: false
    },
    mapItem: {
      type: Function,
      default: item => item
    },
    mapKey: {
      type: Function,
      default: key => key
    },
    defaultItemsPerPage: {
      type: Number,
      default: 10,
      validator: value => value > 0
    },
    noDataText: {
      type: String,
      default: 'No results'
    },
    showSelect: {
      type: Boolean,
      default: false
    },
    maxSelection: {
      type: Number,
      default: 0
    },
    filters: {
      type: Array,
      default: () => []
    }
  });

  const selectedOnly = ref(false);
  const selected = defineModel({
    type: Array,
    default: () => []
  });

  const activeFilters = ref([]);

  watch([
    () => props.queryGetter,
    // () => props.headers,
    // () => props.mapItem,
    // () => props.rowProps,
    () => selectedOnly.value,
    () => activeFilters.value.length
  ], () => nextTick(refresh), { deep: true });

  watch(() => selected.value, newValue => {
    if (props.maxSelection > 0 && newValue.length > props.maxSelection) {
      selected.value = newValue.slice(0, props.maxSelection);
      snackbarStore.set('warning', `You can only select up to ${props.maxSelection} items.`);
    }
  });

  const sortBy = ref([...props.defaultSortBy]);
  const itemsPerPage = ref(props.defaultItemsPerPage * 1);
  const loading = ref(false);
  const prevPage = ref(1);
  const search = ref('');
  const totalItems = ref(0);
  const serverItems = ref([]);
  let queryResults = [];

  const applyFilters = (filters) => {
    activeFilters.value = filters;
    refresh();
  };

  const clearFilters = () => {
    activeFilters.value = [];
    refresh();
  };

  // Workaround until this is implemented: https://github.com/vuetifyjs/vuetify/issues/11117
  watch(() => sortBy.value, (newValue, oldValue) => {
    if (props.sortDescFirst) {
      for (let i = 0; i < sortBy.value.length; i++) {
        const isNew = !oldValue.find(({ key }) => key === sortBy.value[i].key);
        if (isNew) {
          sortBy.value[i].order = 'desc';
        }
      }
      if (!props.mustSort) {
        for (let i = 0; i < oldValue.length; i++) {
          const isRemoved = !sortBy.value.find(({ key }) => key === oldValue[i].key);
          if (isRemoved && oldValue[i].order === 'desc') {
            sortBy.value.splice(0, i, { key: oldValue[i].key, order: 'asc' });
          }
        }
        for (let i = 0; i < sortBy.value.length; i++) {
          const old = oldValue.find(({ key }) => key === sortBy.value[i].key);
          if (old && old.order === 'asc' && sortBy.value[i].order === 'desc') {
            // Bugged with multisort for some reason :/
            sortBy.value.splice(i, 1);
          }
        }
      }
    }
  });

  const itemsPerPageOptions = computed(() => {
    return [1, 5, 10, 25, 50, 100, 250, 500, 1000].filter(item => item <= totalItems.value).concat(
      totalItems.value > 1000 ? [] : [{ title: 'All', value: totalItems.value }]
    );
  });

  const mapper = result => {
    return props.mapItem(result);
  };

  const remap = async () => {
    serverItems.value = await Promise.all(queryResults.map(mapper));
  };

  const loadItems = async ({ itemsPerPage, page, search, sortBy }) => {
    loading.value = true;
    // prevPage.value = page;

    try {
      let query = props.queryGetter(selectedOnly.value && selected.value.length);

      if (search && props.searchField) {
        query = query.ilike(props.searchField, `%${search}%`);

        // // This only matches whole words, not partials
        // query = query.textSearch(props.searchField, search, {
        //   type: 'websearch',
        //   config: 'english'
        // });
      }

      if (activeFilters.value.length) {
        activeFilters.value.forEach(filter => {
          const { field, operation, value } = filter;

          // Format date values for database queries
          let formattedValue = value;
          if (value instanceof Date) {
            formattedValue = parseDate(value)?.toISOString();
          }

          if (operation === 'is') {
            if (value === 'null') {
              query = query.is(field, null);
            } else if (value === 'not.null') {
              query = query.not(field, 'is', null);
            }
          } else if (operation === 'eq') {
            query = query.eq(field, formattedValue);
          } else if (operation === 'neq') {
            query = query.neq(field, formattedValue);
          } else if (operation === 'gt') {
            query = query.gt(field, formattedValue);
          } else if (operation === 'gte') {
            query = query.gte(field, formattedValue);
          } else if (operation === 'lt') {
            query = query.lt(field, formattedValue);
          } else if (operation === 'lte') {
            query = query.lte(field, formattedValue);
          } else if (operation === 'like') {
            query = query.like(field, formattedValue);
          } else if (operation === 'ilike') {
            query = query.ilike(field, `%${formattedValue}%`);
          } else if (operation === 'cs') {
            query = query.contains(field, formattedValue);
          } else if (operation === 'cd') {
            query = query.containedBy(field, formattedValue);
          } else if (operation === 'ov') {
            query = query.overlaps(field, formattedValue);
          } else if (operation === 'in') {
            query = query.in(field, formattedValue);
          }
        });
      }

      if (sortBy && sortBy.length) {
        sortBy.forEach(({ key, order }) => {
          query = query.order(props.mapKey(key), {
            ascending: order === 'asc',
            nullsFirst: false
          });
        });
      }

      // Force returning the count
      query.headers.Prefer = 'count=exact';
      const { data, error, count } = await query.range((page - 1) * itemsPerPage, page * itemsPerPage - 1); // for some reason it adds 1 to the end index
      if (error) {
        throw error;
      }

      queryResults = data;
      await remap();
      totalItems.value = count;
    } catch (error) {
      console.error(error);
      snackbarStore.set('error', 'Something went wrong while fetching the data');
    }

    loading.value = false;
  };

  const refresh = () => loadItems({ itemsPerPage: itemsPerPage.value, page: prevPage.value, search: search.value, sortBy: sortBy.value });

  defineExpose({
    loading,
    remap,
    refresh
  });
</script>

<template>
  <v-data-table-server
    v-bind="$attrs"
    v-model="selected"
    v-model:items-per-page="itemsPerPage"
    v-model:sort-by="sortBy"
    :class="['data-table', { 'desc-first': sortDescFirst }]"
    fixed-header
    :header-props="{ class: 'text-overline', style: { lineHeight: 1.5 } }"
    :headers="headers"
    hover
    :items="serverItems"
    :items-length="totalItems"
    :items-per-page-options="itemsPerPageOptions"
    :loading="loading"
    :must-sort="mustSort"
    :search="search"
    :show-select="showSelect"
    @click:row="(_, { item }) => emit('click:row', toRaw(item))"
    @update:options="loadItems"
  >
    <template #no-data>
      <span class="text-disabled font-italic">
        {{ noDataText }}
      </span>
    </template>

    <template
      v-if="!props.simple"
      #top="attrs"
    >
      <slot
        name="top"
        v-bind="attrs"
      />
      <div
        v-if="showSelect || searchField || props.filters.length"
        class="d-flex justify-end align-center ga-2 px-2 pt-2"
      >
        <v-text-field
          v-if="searchField"
          v-model="search"
          clearable
          density="compact"
          hide-details
          label="Search"
          rounded
          variant="outlined"
        />

        <v-chip
          v-if="showSelect && maxSelection > 0"
          :color="selectedOnly ? 'success' : ''"
          filter
          @click="selectedOnly = !selectedOnly"
        >
          {{ selected.length }}{{ maxSelection ? `/${maxSelection}` : '' }} selected
        </v-chip>

        <dialog-data-filter
          v-if="props.filters.length"
          :active-filters="activeFilters"
          :filters="props.filters"
          @apply="applyFilters"
          @clear="clearFilters"
        >
          <template #activator="{ props: dialogProps }">
            <v-badge
              color="primary"
              :content="activeFilters.length.toString()"
              :model-value="activeFilters.length > 0"
              offset-x="5"
              offset-y="5"
            >
              <v-btn
                v-tooltip:top="activeFilters.length > 0 ? `${activeFilters.length} filter${activeFilters.length > 1 ? 's' : ''} applied` : 'Apply filters'"
                v-bind="dialogProps"
                icon="mdi-filter"
                variant="text"
              />
            </v-badge>
          </template>
        </dialog-data-filter>
      </div>
    </template>

    <template
      v-if="simple"
      #headers
    >
      <!-- POOF, GONE -->
    </template>

    <template
      v-for="slot in Object.keys(slots).filter(n => n !== 'top')"
      #[slot]="attrs"
    >
      <slot
        :name="slot"
        v-bind="attrs"
      />
    </template>
  </v-data-table-server>
</template>

<style lang="scss" scoped>
  .data-table {
    min-height: 200px;
    display: flex;
    flex-grow: 1;
    overflow-y: auto;
    overflow-x: hidden;

    ::v-deep(.v-data-table__td) {
      max-width: 300px;
    }

    .desc-first ::v-deep(.v-data-table__th--sortable:not(.v-data-table__th--sorted) .v-icon) {
      transform: rotate(180deg);
    }
  }
</style>
