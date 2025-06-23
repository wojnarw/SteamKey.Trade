<script setup>
  import RichProfileLink from '~/components/Rich/RichProfileLink.vue';

  const props = defineProps({
    user: {
      type: Object,
      required: true
    },
    position: {
      type: String,
      required: true
    }
  });

  // get everything except for userId
  // TODO: Split this up into multiple props instead?
  const { userId, ...attributes } = props.user;
  // TODO: change order of attributes or just print them manually
  // console.info('attributes', attributes);
  const { User } = useORM();

  const cardMarginClass = computed(() => {
    return props.position === '1' ? 'mb-10' : 'mt-12'; // for showing cards at different height
  });

  const avatarSize = computed(() => {
    return props.position === '1' ? '110' : '100'; // for showing cards at different height
  });

  const positionBgClass = computed(() => {
    switch (props.position) {
      case '1':
        return 'first-place';
      case '2':
        return 'second-place';
      case '3':
        return 'third-place';
      default:
        return '';
    }
  });
</script>

<template>
  <v-col
    class="d-flex justify-center overflow-visible"
    :class="cardMarginClass"
    cols="4"
  >
    <v-card
      class="podium-card"
      width="250"
    >
      <!--card top-->
      <v-card-text
        class="d-flex align-center justify-start pa-0"
        :class="positionBgClass"
      >
        <v-container
          class="px-0 mx-0 z-10 overflow-visible mx-0 avatar-bg justify-space-between"
          :class="{ 'first-place-avatar-bg' : props.position === '1' }"
        >
          <rich-profile-link
            :avatar-size="avatarSize"
            class="overflow-visible my-n10 z-20 card-username position-relative font-weight-bold py-0 ml-n2"
            hide-reputation
            :user-id="userId"
          />
        </v-container>

        <!--        <rich-profile-link-->
        <!--          class="card-username position-relative font-weight-bold py-0 ml-4 z-99 color-primary-700"-->
        <!--          hide-avatar-->
        <!--          hide-reputation-->
        <!--          :user-id="props.user.userId"-->
        <!--        />-->
      </v-card-text>

      <!--user statistics panel-->
      <v-card-text class="pt-10 pb-4">
        <span
          v-if="metaLoadingError"
          class="text-disabled font-italic error-message"
        >
          {{ metaLoadingError?.message }}
        </span>

        <v-skeleton-loader
          v-else-if="!user || status === 'pending'"
          type="text@4"
        />

        <v-row
          v-for="key in Object.keys(attributes)"
          v-else
          :key="key"
          class="align-center"
        >
          <v-col
            class="text-right font-weight-bold pt-0 pb-0 text-h6"
            cols="3"
          >
            {{ attributes[key] }}
          </v-col>
          <v-col
            class="text-grey py-1"
            cols="9"
          >
            <span>
              {{ (User.shortLabels[key] ? User.shortLabels[key] : key) }}
              <v-tooltip
                activator="parent"
                open-delay="300"
              >
                {{ (User.labels[key] ? User.labels[key] : key) }}
              </v-tooltip>
            </span>
          </v-col>
        </v-row>
      </v-card-text>
    </v-card>
  </v-col>
</template>

<style scoped lang="scss">
.podium-card {
  border-radius: 10px;
  padding: 0;
  /*box-shadow: 0 8px 20px rgba(0, 0, 0, 0.2);*/
  transition: transform 0.3s ease, box-shadow 0.3s ease;
  border: 0 solid transparent;
  overflow: visible;
}

.first-place {
  background: rgb(204, 165, 0);
  background: linear-gradient(0deg, rgba(178, 132, 8, 0.8) 0%, rgba(245, 180, 17, 0.8) 35%, rgba(255, 228, 1, 0.8) 45%, rgba(255, 228, 1, 0.8) 100%);
  box-shadow: 0 5px 5px rgba(0, 0, 0, 0.3);
  transition: transform 0.5s ease;
}

.second-place {
  background: rgb(122, 122, 122);
  background: linear-gradient(0deg, rgba(124, 124, 124, 0.8) 35%, rgba(164, 164, 164, 0.8) 45%, rgba(177, 177, 177, 0.8) 60%);
  box-shadow: 0 5px 5px rgba(0, 0, 0, 0.3);
}

.third-place {
  background: rgb(158, 95, 20);
  background: linear-gradient(0deg, rgba(133, 76, 9, 0.8) 35%, rgba(158, 95, 20, 0.8) 45%, rgba(179, 102, 6, 0.8) 100%);
  box-shadow: 0 5px 5px rgba(0, 0, 0, 0.3);
}

:deep(.v-avatar) {
  border: 2px solid #a0a0a0; // TODO: use some theme color
  //border: 2px solid rgb(var(--v-theme-surface)) !important;
}

.avatar-bg {
  height: 50px;
  width: initial;
  background: rgba(0, 0, 0, 0);
}

.first-place-avatar-bg {
  height: 60px !important;
}

// make avatar loader fill whole space correctly
::v-deep .v-skeleton-loader {
  .v-skeleton-loader__avatar {
    height: 100%;
    width: 100%;
    max-height: initial;
    max-width: initial;
    margin: 0;
    padding: 0;
  }
}

.card-username::v-deep span {
  color: #dddddd !important;
  font-size: 1rem;
  z-index: 1;
  text-shadow: #4d4d4d 2px 1px;
}
</style>
