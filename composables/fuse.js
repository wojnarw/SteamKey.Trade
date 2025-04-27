import FuseWorker from '~/assets/js/workers/fuse?worker';

export const useFuse = (data, options) => {
  const worker = new FuseWorker();
  let ready = false;

  const init = () => new Promise((resolve, reject) => {
    const listener = ({ data }) => {
      const { type, payload } = data;
      switch (type) {
        case 'ready':
          ready = payload;
          worker.removeEventListener('message', listener, false);
          resolve(payload);
          break;
        default:
          break;
      }
    };

    worker.addEventListener('message', listener, false);
    worker.addEventListener('error', reject, false);
    worker.postMessage({
      type: 'init',
      payload: {
        data,
        options
      }
    });
  });

  const search = query => {
    return new Promise((resolve, reject) => {
      if (!ready) {
        return init()
          .then(() => search(query))
          .then(resolve)
          .catch(reject);
      }

      const listener = ({ data }) => {
        const { type, payload } = data;
        switch (type) {
          case 'results':
            if (payload.query === query) {
              worker.removeEventListener('message', listener, false);
              resolve(payload.results);
            }
            break;
          default:
            break;
        }
      };

      worker.addEventListener('message', listener, false);
      worker.addEventListener('error', reject, false);
      worker.postMessage({
        type: 'search',
        payload: {
          query
        }
      });
    });
  };

  // onUnmounted(() => {
  //   if (worker) {
  //     worker.terminate();
  //   }
  // });

  const destroy = () => {
    worker.terminate();
    ready = false;
  };

  return { search, destroy };
};