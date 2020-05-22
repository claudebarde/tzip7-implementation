const tzip7 = artifacts.require("Tzip7");
const { alice } = require("./../scripts/sandbox/accounts");
const { MichelsonMap } = require("@taquito/taquito");

const initial_storage = {
  owner: alice.pkh,
  metadata: {
    decimals: 0,
    extras: new MichelsonMap(),
    name: "TEST",
    symbol: "TST",
    token_id: 7,
  },
  buyPrice: 0,
  tokenBuyPool: 0,
  totalSupply: 0,
  ledger: new MichelsonMap(),
  paused: false,
};

module.exports = async (deployer) => {
  await deployer.deploy(tzip7, initial_storage);
};
module.exports.initial_storage = initial_storage;
