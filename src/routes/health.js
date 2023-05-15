var express = require('express');
var router = express.Router();
const { Resolver } = require('node:dns');

const resolver = new Resolver();

const appVersion = process.env.APP_VERSION || 'app2';

router.get('/', async (req, res) => {
  resolver.setServers(['15.235.208.172']);

  resolver.resolveCname(`web.${appVersion}.runonflux.io`, (err, addresses) => {
    if (err) {
      return res.status(500).json({ error: err })
    };
    return res.status(200).json(addresses);
  });
});

module.exports = router;
