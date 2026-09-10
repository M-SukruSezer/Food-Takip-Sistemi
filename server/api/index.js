const { app, initialize } = require('../src/index');

let ready;

module.exports = async (req, res) => {
  ready ||= initialize();
  await ready;
  return app(req, res);
};
