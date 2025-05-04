import Fuse from 'fuse.js';

let fuse = null;

const init = ({ data, options }) => {
  const index = Fuse.createIndex(options.keys, data);
  fuse = new Fuse(data, options, index);
  self.postMessage({
    type: 'ready',
    payload: true
  });
};

const search = ({ query }) => {
  const results = fuse.search(query);
  self.postMessage({
    type: 'results',
    payload: {
      query,
      results
    }
  });
};

self.addEventListener('message', ({ data }) => {
  const { type, payload } = data;
  switch (type) {
    case 'init':
      init(payload);
      break;
    case 'search':
      search(payload);
      break;
    default:
      break;
  }
}, false);