import '@mdi/font/css/materialdesignicons.css';
import '@/styles/main.scss';

import { createVuetify } from 'vuetify';
import { VTimePicker } from 'vuetify/labs/components';

const socialColors = {
  steam: '#000000',
  twitch: '#6441a5',
  discord: '#7289da',
  origin: '#f56c2d',
  battlenet: '#00aeff',
  epicgames: '#313131',
  uplay: '#0096d6',
  facebook: '#3b5998',
  twitter: '#00aced',
  linkedin: '#007bb6',
  youtube: '#bb0000',
  whatsapp: '#4dc247',
  instagram: '#c32aa3'
};

export default defineNuxtPlugin(app => {
  let defaultTheme = window?.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  if ('theme' in window.localStorage) {
    defaultTheme = window.localStorage.getItem('theme');
  }

  const vuetify = createVuetify({
    styles: {
      configFile: 'src/styles/settings.scss'
    },
    theme: {
      defaultTheme,
      themes: {
        light: {
          colors: {
            primary: '#363636',
            secondary: '#d6d6d6',
            ...socialColors
          }
        },
        dark: {
          colors: {
            primary: '#fff',
            secondary: '#363636',
            ...socialColors
          }
        }
      }
    },
    components: {
      VTimePicker
    }
  });

  app.vueApp.use(vuetify);

  return {
    provide: {
      vuetify
    }
  };
});
