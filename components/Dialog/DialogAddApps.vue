<script setup>
  import jsonata from 'jsonata';

  const props = defineProps({
    collectionId: {
      type: String,
      required: true
    }
  });

  const { Collection } = useORM();
  const { search } = useAppsStore();
  const internalValue = ref(false);
  const inputText = ref('');
  const isLoading = ref(false);
  const preview = ref([]);
  const previewCount = 10;
  const validationError = ref('');

  const selectedValueType = ref('title');
  const valueTypes = [
    { title: 'AppID\'s', value: 'appid' },
    { title: 'App titles', value: 'title' }
  ];

  const selectedInputType = ref('text');
  const inputTypes = [
    { title: 'Text', value: 'text' },
    { title: 'JSON', value: 'json' }
  ];

  // For text input with delimiter
  const showDelimiterOption = ref(false);
  const delimiter = ref(',');

  // For JSON input with JSONata
  const jsonIsValid = ref(true);
  const jsonataQuery = ref('');
  const jsonataError = ref('');

  const totalItems = ref(0);
  const processedItems = ref(0);
  const emit = defineEmits(['submit']);

  // Process text input into array of items
  const processTextInput = (text) => {
    const lines = text.trim().split('\n').filter(line => line.trim());

    if (lines.length === 1) {
      showDelimiterOption.value = true;
      return lines[0].split(delimiter.value).map(item => item.trim()).filter(Boolean);
    } else {
      showDelimiterOption.value = false;
      return lines;
    }
  };

  // Parse JSON and apply JSONata query if provided
  const processJsonInput = async (text, query) => {
    try {
      const jsonData = JSON.parse(text);
      jsonIsValid.value = true;

      if (query.trim()) {
        try {
          // Use JSONata for query processing
          const expression = jsonata(query);
          const result = await expression.evaluate(jsonData);
          jsonataError.value = '';

          if (Array.isArray(result)) {
            return result;
          } else if (result !== undefined) {
            return [result];
          }
          return [];
        } catch (e) {
          jsonataError.value = e.message;
          return [];
        }
      } else {
        // No query provided, just return the top-level array if it exists
        return Array.isArray(jsonData) ? jsonData : [jsonData];
      }
    } catch {
      jsonIsValid.value = false;
      return [];
    }
  };

  // Process input based on selected type
  const processInput = async () => {
    if (!inputText.value.trim()) {
      return [];
    }

    try {
      if (selectedInputType.value === 'text') {
        return processTextInput(inputText.value);
      } else if (selectedInputType.value === 'json') {
        return await processJsonInput(inputText.value, jsonataQuery.value);
      }
    } catch (e) {
      console.error(e);
    }

    return [];
  };

  // Validate app IDs
  const validateAppIds = (items) => {
    const validAppIds = items
      .map(item => Number(item))
      .filter(appId => !isNaN(appId) && appId > 0 && appId === Math.floor(appId));

    if (validAppIds.length !== items.length) {
      validationError.value = 'Not all items are valid AppIDs (positive integers)';
    }

    return validAppIds;
  };

  // Update preview based on current selections and input
  const updatePreview = async () => {
    preview.value = [];
    validationError.value = '';

    const items = await processInput();

    // Validate if all items are valid AppIDs if value type is appid
    if (selectedValueType.value === 'appid' && items.length > 0) {
      validateAppIds(items);
    }

    // Limit preview to first n items
    preview.value = items.slice(0, previewCount);
  };

  // Watch for input changes to update preview
  watch([inputText, selectedInputType, selectedValueType, delimiter, jsonataQuery], () => {
    updatePreview();
  }, { immediate: true });

  const submit = async () => {
    isLoading.value = true;
    validationError.value = '';

    try {
      const inputItems = await processInput();
      let finalAppIds = [];

      // If appids are already selected, just validate them
      if (selectedValueType.value === 'appid') {
        finalAppIds = validateAppIds(inputItems);
      // If app titles are selected, search for each title and extract the appids
      } else if (selectedValueType.value === 'title') {
        totalItems.value = inputItems.length;
        processedItems.value = 0;

        const batchSize = 20;
        for (let i = 0; i < inputItems.length; i += batchSize) {
          if (internalValue.value === false) {
            break; // Abort if dialog is closed
          }

          const batch = inputItems.slice(i, i + batchSize);
          const appIdPromises = batch.map(async (title) => {
            const results = await search(title);
            processedItems.value++;

            if (results && results.length > 0) {
              // Get the appid from the best match
              return results[0]?.item?.appid;
            }
            return null;
          });

          const resolvedAppIds = await Promise.all(appIdPromises);
          finalAppIds.push(...resolvedAppIds.filter(id => id !== null && !isNaN(id)));
        }

        if (finalAppIds.length !== inputItems.length) {
          validationError.value = 'Some app titles could not be found';
        }
      }

      const instance = new Collection(props.collectionId);
      await instance.addApps(finalAppIds);

      emit('submit', finalAppIds);

      internalValue.value = false;
      resetForm();
    } catch (error) {
      console.error(error);
      validationError.value = `Error: ${error.message}`;
    } finally {
      isLoading.value = false;
    }
  };

  const resetForm = () => {
    inputText.value = '';
    showDelimiterOption.value = false;
    jsonIsValid.value = true;
    jsonataQuery.value = '';
    jsonataError.value = '';
    validationError.value = '';
    preview.value = [];
    totalItems.value = 0;
    processedItems.value = 0;
  };
</script>

<template>
  <v-dialog
    v-model="internalValue"
    :persistent="isLoading"
    width="720"
  >
    <template #activator="attrs">
      <slot
        name="activator"
        v-bind="attrs"
      />
    </template>

    <template #default>
      <v-card :loading="isLoading">
        <v-card-title>
          Apps import
          <template v-if="isLoading && selectedValueType === 'title'">
            ({{ processedItems }}/{{ totalItems }})
          </template>
        </v-card-title>
        <v-card-text>
          <v-row>
            <v-col
              cols="12"
              md="6"
            >
              <v-select
                v-model="selectedValueType"
                density="comfortable"
                hide-details
                :items="valueTypes"
                label="Target"
              />
            </v-col>
            <v-col
              cols="12"
              md="6"
            >
              <v-select
                v-model="selectedInputType"
                density="comfortable"
                hide-details
                :items="inputTypes"
                label="Input"
              />
            </v-col>
          </v-row>

          <template v-if="selectedInputType === 'text'">
            <v-textarea
              v-model="inputText"
              class="mt-4"
              :label="`Enter ${selectedValueType === 'appid' ? 'appids' : 'app titles'}`"
              rows="5"
            />

            <v-expand-transition>
              <div v-if="showDelimiterOption">
                <v-text-field
                  v-model="delimiter"
                  density="comfortable"
                  hint="Character that separates values"
                  label="Delimiter"
                />
              </div>
            </v-expand-transition>
          </template>

          <!-- JSON Input Section -->
          <template v-else-if="selectedInputType === 'json'">
            <p class="text-caption mt-4">
              TIP: Import <a
                href="https://store.steampowered.com/dynamicstore/userdata/"
                rel="noopener noreferrer"
                target="_blank"
              >Steam's dynamic store data</a> as JSON.
            </p>
            <v-textarea
              v-model="inputText"
              class="mt-4"
              :error="!jsonIsValid"
              :error-messages="jsonIsValid ? '' : 'Invalid JSON format'"
              label="Enter JSON"
              :placeholder="JSON.stringify({ apps: { 400: { title: 'Portal' }, 620: { title: 'Portal 2' } } }, null, 2)"
              rows="5"
            />

            <v-text-field
              v-model="jsonataQuery"
              density="comfortable"
              :error-messages="jsonataError"
              :hint="selectedValueType === 'title' ? 'e.g. apps.*.title' : 'e.g. $keys(apps)'"
              label="JSON selector"
            />
          </template>

          <!-- Validation Error -->
          <div
            v-if="validationError"
            class="text-error mt-2"
          >
            {{ validationError }}
          </div>

          <!-- Preview Section -->
          <v-card
            v-if="Array.isArray(preview) && preview.length > 0 && !validationError"
            class="mt-4 text-disabled"
            variant="tonal"
          >
            <v-card-title class="text-subtitle-1">
              Parsed preview (first {{ previewCount }} items)
            </v-card-title>
            <v-card-text>
              <p
                v-for="(item, index) in preview"
                :key="index"
              >
                {{ item }}
              </p>
              <div
                v-if="preview.length === previewCount"
                class="text-caption text-center pa-2"
              >
                More items not shown in preview
              </div>
            </v-card-text>
          </v-card>
        </v-card-text>
        <v-card-actions>
          <v-btn @click="internalValue = false">
            {{ isLoading ? 'Abort' : 'Close' }}
          </v-btn>

          <v-spacer />

          <v-btn
            color="primary"
            :disabled="isLoading || preview.length === 0 || !!validationError"
            variant="tonal"
            @click="submit"
          >
            Save apps
          </v-btn>
        </v-card-actions>
      </v-card>
    </template>
  </v-dialog>
</template>