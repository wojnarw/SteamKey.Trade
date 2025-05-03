<script setup>
  import { formatNumber } from '~/assets/js/format';

  const props = defineProps({
    label: {
      type: String,
      default: ''
    },
    items: {
      type: Array,
      default: () => []
    },
    size: {
      type: Number,
      default: 100
    },
    legend: {
      type: Boolean,
      default: false
    },
    donut: {
      type: Boolean,
      default: false
    }
  });

  const totalValue = computed(() => {
    return props.items.reduce((acc, item) => acc + item.value, 0);
  });

  const computedSize = computed(() => {
    return `${props.size}px`;
  });

  const getRotateValue = index => {
    return props.items
      .slice(0, index)
      .reduce((acc, item) => acc + (item.value / totalValue.value) * 360, 0) + 90;
  };

  const getModelValue = value => {
    return (value / totalValue.value) * 100;
  };
</script>

<template>
  <div class="pie-chart">
    <div :style="{ width: computedSize, height: computedSize }">
      <v-hover
        v-for="(item, index) in props.items"
        :key="index"
      >
        <template #default="{ isHovering, props: hoverProps }">
          <v-progress-circular
            class="pie-segment"
            :color="item.color"
            :model-value="getModelValue(item.value)"
            :rotate="getRotateValue(index)"
            :size="props.size"
            :style="{ pointerEvents: 'none', zIndex: 0 }"
            :width="!donut ? props.size * 0.5 : isHovering ? props.size * 0.2 : props.size * 0.1"
          />
          <!-- needed to avoid jittering -->
          <v-progress-circular
            v-tooltip:end="`${item.title}: ${formatNumber(item.value * 100 / totalValue)}% (${item.value})`"
            class="pie-segment"
            color="transparent"
            :model-value="getModelValue(item.value)"
            :rotate="getRotateValue(index)"
            :size="props.size"
            :style="{ zIndex: 1 }"
            :width="!donut ? props.size * 0.5 : props.size * 0.2"
            v-bind="hoverProps"
          />
        </template>
      </v-hover>
      <div
        v-if="props.label"
        class="pie-chart-label"
        :style="{ width: computedSize, height: computedSize }"
      >
        {{ props.label }}
      </div>
    </div>

    <div
      v-if="props.legend"
      class="pie-chart-legend"
    >
      <v-row>
        <v-col
          v-for="(item, index) in props.items"
          :key="index"
          cols="12"
          :md="12 / props.items.length"
        >
          <div class="d-flex flex-row align-center">
            <div
              class="legend-color"
              :style="{ backgroundColor: item.color }"
            />
            <span class="legend-text">{{ item.title }}: {{ item.value }}</span>
          </div>
        </v-col>
      </v-row>
    </div>
  </div>
</template>

<style lang="scss" scoped>
  .pie-chart {
    position: relative;

    .pie-segment {
      pointer-events: none;
      position: absolute;
      top: 0;
      left: 0;
      transform: rotate(-90deg);

      ::v-deep(.v-progress-circular__underlay) {
        pointer-events: none;
        display: none;
      }

      ::v-deep(.v-progress-circular__overlay) {
        pointer-events: all;
        // transition: stroke-width 0.3s ease;
      }
    }

    .pie-chart-label {
      align-items: center;
      display: flex;
      justify-content: center;
      pointer-events: none;
      position: absolute;
      top: 0;
    }

    .pie-chart-legend {
      position: absolute;
      margin-top: 1rem;

      .legend-color {
        border-radius: 50%;
        height: 1rem;
        margin-right: 0.3rem;
        width: 1rem;
      }

      .legend-text {
        font-size: 0.7rem;
      }
    }
  }
</style>
