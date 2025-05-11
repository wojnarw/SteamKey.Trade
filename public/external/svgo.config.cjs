module.exports = {
  plugins: [
    {
      name: 'addAttributesToSVGElement',
      params: { attributes: [{ fill: 'currentColor' }] }
    },
    { name: 'removeAttrs', params: { attrs: ['stroke'] } },
    'removeDimensions',
    { name: 'removeViewBox', active: false }
  ]
};
