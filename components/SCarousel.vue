<script setup>
  const props = defineProps({
    media: {
      type: Array,
      required: true
    },
    rounded: {
      type: Boolean,
      default: false
    }
  });

  const currentIndex = ref(0);
  const videoRefs = ref([]);
  const dialog = ref(false);
  const selectedItem = ref({});

  const detectMediaType = url => {
    const parsedUrl = new URL(url);
    const extension = parsedUrl.pathname.split('.').pop().toLowerCase();
    const videoExtensions = ['mp4', 'webm', 'ogg', 'mov', 'avi'];
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'];

    if (videoExtensions.includes(extension)) {
      return {
        type: 'video',
        mimeType: `video/${extension === 'mov' ? 'quicktime' : extension}`,
        controls: false,
        autoplay: false,
        muted: true,
        loop: true,
        overlay: true,
        pattern: ''
      };
    }

    return {
      type: 'image',
      mimeType: imageExtensions.includes(extension) ?
        `image/${extension === 'svg' ? 'svg+xml' : extension}` :
        'image/*'
    };
  };

  const brokenitems = ref([]);
  const mediaItems = computed(() =>
    props.media.map(item => {
      const baseItem = typeof item === 'string' ? { src: item } : item;
      return {
        ...detectMediaType(baseItem.src),
        ...baseItem
      };
    }).filter(({ src }) => !brokenitems.value.includes(src))
  );

  let timer = null;
  watch(() => currentIndex.value, newIndex => {
    clearTimeout(timer);

    videoRefs.value.forEach((video, index) => {
      if (video) {
        if (index === newIndex && mediaItems.value[index].type === 'video') {
          video.play();
        } else {
          video.pause();
        }
      }
    });

    if (mediaItems.value[newIndex].type === 'image') {
      timer = setTimeout(() => {
        currentIndex.value = (newIndex + 1) % mediaItems.value.length;
      }, 5000);
    }
  });

  const openDialog = item => {
    selectedItem.value = item;
    dialog.value = true;
  };
</script>

<template>
  <v-carousel
    v-model="currentIndex"
    :class="{ carousel: true, 'rounded': rounded }"
    height="auto"
    hide-delimiters
    :show-arrows="mediaItems.length > 1 ? 'hover' : false"
  >
    <v-carousel-item
      v-for="(item, index) in mediaItems"
      :key="index"
      :value="index"
    >
      <video
        v-if="item.type === 'video'"
        ref="videoRefs"
        v-ripple
        autoplay
        class="carousel-video"
        controls
        muted
        @ended="currentIndex = (currentIndex + 1) % mediaItems.length"
      >
        <source
          :src="item.src"
          :type="item.mimeType"
        >
      </video>
      <v-img
        v-else
        v-ripple
        class="carousel-image"
        cover
        :src="item.src"
        @click="openDialog(item)"
      />
    </v-carousel-item>
  </v-carousel>

  <v-dialog
    v-model="dialog"
    max-width="800px"
  >
    <v-img :src="selectedItem.src" />
  </v-dialog>
</template>

<style lang="scss" scoped>
  .carousel {
    .carousel-video {
      height: 100%;
      width: 100%;
      aspect-ratio: 16/9;

      video {
        height: 100%;
        width: 100%;

        position: absolute;
        top: 0;
        left: 0;
      }
    }

    .carousel-image {
      cursor: pointer;
      aspect-ratio: 16/9;
    }

    &.rounded {
      .carousel-image {
        border-radius: 4px;
      }

      .carousel-video {
        border-radius: 4px;
      }
    }
  }
</style>