<script setup>
  const { VaultEntry } = useORM();

  const props = defineProps({
    disabled: {
      type: Boolean,
      default: false
    },
    encrypted: {
      type: Boolean,
      required: true
    }
  });

  const model = defineModel({
    type: Object,
    default: () => ({
      appid: null,
      type: 'key',
      values: ['']
    })
  });

  const emit = defineEmits(['update:encrypted']);

  const inputRefs = ref([]);
  const focusedIndex = ref(null);

  const handleClear = (index) => {
    model.value.values.splice(index, 1);
    model.value.values = [...model.value.values.filter(Boolean), ''];
  };

  const handleBackspace = index => {
    if (model.value.values[index] === '') {
      inputRefs.value[index - 1]?.focus();
    }
  };

  const handleEnter = index => {
    inputRefs.value[index + 1]?.focus();
  };

  const handlePaste = event => {
    event.preventDefault();
    const pastedText = event.clipboardData.getData('text');
    model.value = {
      ...model.value,
      values: [...model.value.values.filter(Boolean), ...pastedText.split('\n').filter(Boolean), '']
    };
  };

  const handleValueUpdate = () => {
    if (!model.value.values.includes('')) {
      model.value.values.push('');
    }
    emit('update:encrypted', false);
  };

  const getInputIcon = value => {
    if (props.encrypted) { return 'mdi-lock'; }
    return ['https://', 'http://'].some(prefix => value.startsWith(prefix)) ? 'mdi-link' : 'mdi-key';
  };
</script>

<template>
  <v-select
    v-model="model.type"
    class="flex-0-0"
    density="compact"
    hide-details
    :items="Object.keys(VaultEntry.enums.type).map(type => ({
      title: VaultEntry.labels[type],
      value: VaultEntry.enums.type[type]
    }))"
    label="Type"
    prepend-inner-icon="mdi-tag"
    variant="outlined"
  >
    <template #item="{ item: { title, value }, props: itemProps }">
      <v-list-item
        v-bind="itemProps"
        :prepend-icon="VaultEntry.icons[value]"
        :title="title"
      />
    </template>
  </v-select>

  <v-divider />

  <v-text-field
    v-for="(_, index) in model.values"
    :key="index"
    :ref="el => inputRefs[index] = el?.$el.querySelector('input')"
    v-model="model.values[index]"
    :class="['flex-0-0', { 'text-monospace': disabled }]"
    density="compact"
    :disabled="disabled"
    hide-details
    :prepend-inner-icon="getInputIcon(model.values[index])"
    :tabindex="index + 1"
    variant="outlined"
    @blur="focusedIndex = null"
    @focus="focusedIndex = index"
    @keydown.backspace="handleBackspace(index)"
    @keydown.enter="handleEnter(index)"
    @paste="handlePaste"
    @update:model-value="handleValueUpdate"
  >
    <template #append-inner>
      <v-fade-transition>
        <v-icon
          v-if="focusedIndex === index"
          class="fade-icon"
          icon="mdi-close-circle"
          @click="handleClear(index)"
        />
      </v-fade-transition>
    </template>
  </v-text-field>
</template>

<style lang="scss" scoped>
  .text-monospace {
    font-family: 'Fira Code', monospace;

    :deep(input) {
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
  }

  .fade-icon {
    transition: opacity 0.3s ease, transform 0.3s ease;
    opacity: 0.8;

    &:hover {
      opacity: 1;
      transform: scale(1.1);
    }
  }
</style>