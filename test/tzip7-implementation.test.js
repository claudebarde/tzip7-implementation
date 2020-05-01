const tzip_7_implementation = artifacts.require("Tzip7");
const { Tezos } = require("@taquito/taquito");
const { InMemorySigner, importKey } = require("@taquito/signer");
const { alice, bob } = require("../scripts/sandbox/accounts");

const signerFactory = async (pk) => {
  await Tezos.setProvider({ signer: new InMemorySigner(pk) });
  return Tezos;
};

contract("tzip7 contract", (accounts) => {
  let storage;
  let tzip7_instance;

  before(async () => {
    tzip7_instance = await tzip_7_implementation.deployed();
    // this code bypasses Truffle config to be able to have different signers
    // until I find how to do it directly with Truffle
    await Tezos.setProvider({ rpc: "http://localhost:8732" });
    await signerFactory(alice.sk);
    /**
     * Display the current contract address for debugging purposes
     */
    console.log("Contract deployed at:", tzip7_instance.address);
    tzip7_instance = await Tezos.contract.at(tzip7_instance.address);
    storage = await tzip7_instance.storage();
  });

  it("should have the right owner and the right metadata", () => {
    assert.equal(storage.owner, alice.pkh);
    assert.equal(storage.metadata.name, "TEST");
  });

  it("should mint 10000 tokens for Alice's account", async () => {
    // mints tokens
    const tokensToBeMinted = 10000;
    const op = await tzip7_instance.methods.mint(tokensToBeMinted).send();
    await op.confirmation();
    storage = await tzip7_instance.storage();
    // checks if tokens have been minted and total supply has been updated
    assert.equal(storage.totalSupply, tokensToBeMinted);
    // fetches Alice's token amount
    const aliceAccount = await storage.ledger.get(alice.pkh);
    assert.equal(aliceAccount.balance.toNumber(), tokensToBeMinted);
    assert.equal(storage.totalSupply.toNumber(), tokensToBeMinted);
  });

  it("should prevent Alice from transferring more tokens than she owns", async () => {
    let failwith = "";
    try {
      const op = await tzip7_instance.methods
        .transfer(alice.pkh, bob.pkh, 12000)
        .send();
      await op.confirmation();
    } catch (error) {
      failwith = error.message;
    }

    assert.equal(failwith, "Source balance is too low");
  });

  it("should transfer 2000 tokens from Alice to Bob", async () => {
    const tokensToTransfer = 2000;
    const aliceInitialAccount = await storage.ledger.get(alice.pkh);

    try {
      const op = await tzip7_instance.methods
        .transfer(alice.pkh, bob.pkh, tokensToTransfer)
        .send();
      await op.confirmation();
    } catch (error) {
      console.log(error);
    }

    // fetches new storage
    storage = await tzip7_instance.storage();
    const aliceAccount = await storage.ledger.get(alice.pkh);
    const bobAccount = await storage.ledger.get(bob.pkh);

    assert.equal(
      aliceAccount.balance.toNumber(),
      aliceInitialAccount.balance.toNumber() - tokensToTransfer
    );
    assert.equal(bobAccount.balance.toNumber(), 2000);
  });

  it("should prevent Bob from spending Alice's tokens", async () => {
    // switches signer to Bob
    await signerFactory(bob.sk);

    let failwith = "";
    try {
      const op = await tzip7_instance.methods
        .transfer(alice.pkh, bob.pkh, 2000)
        .send();
      await op.confirmation();
    } catch (error) {
      failwith = error.message;
    }

    assert.equal(failwith, "Sender not allowed to spend tokens from source");
  });

  it("Bob should now be able to transfer tokens back to Alice", async () => {
    // fetches a fresh storage
    storage = await tzip7_instance.storage();
    // gets initial values of Bob's and Alice's accounts
    const aliceInitialAccount = await storage.ledger.get(alice.pkh);
    const bobInitialAccount = await storage.ledger.get(bob.pkh);
    // Bob transfers 1000 tokens to Alice
    const tokensToTransfer = 1000;
    const op = await tzip7_instance.methods
      .transfer(bob.pkh, alice.pkh, tokensToTransfer)
      .send();
    await op.confirmation();
    // fetches updated storage
    storage = await tzip7_instance.storage();
    const aliceAccount = await storage.ledger.get(alice.pkh);
    const bobAccount = await storage.ledger.get(bob.pkh);
    // compares values
    assert.equal(
      aliceAccount.balance.toNumber(),
      aliceInitialAccount.balance.toNumber() + tokensToTransfer
    );
    assert.equal(
      bobAccount.balance.toNumber(),
      bobInitialAccount.balance.toNumber() - tokensToTransfer
    );
  });

  it("should allow Bob to spend 2000 tokens on Alice's behalf", async () => {
    // switches signer to Alice
    await signerFactory(alice.sk);

    const tokensToBeApproved = 2000;
    const op = await tzip7_instance.methods
      .approve(bob.pkh, tokensToBeApproved)
      .send();
    await op.confirmation();
    // fetches updated storage
    storage = await tzip7_instance.storage();
    // fetches Bob's allowance
    const aliceAccount = await storage.ledger.get(alice.pkh);
    const alicesAllowanceForBob = await aliceAccount.allowances.get(bob.pkh);

    assert.equal(alicesAllowanceForBob, tokensToBeApproved);
  });

  it("should prevent Bob from spending more than his allowance", async () => {
    let error = "";
    // fetches Bob's allowance
    const aliceAccount = await storage.ledger.get(alice.pkh);
    const alicesAllowanceForBob = await aliceAccount.allowances.get(bob.pkh);
    const tokensToTransfer = alicesAllowanceForBob + 1000;

    // switches signer to Bob
    await signerFactory(bob.sk);

    // Bob tries to transfer more tokens than he is allowed
    try {
      const op = await tzip7_instance.methods
        .transfer(alice.pkh, bob.pkh, tokensToTransfer)
        .send();
      await op.confirmation();
    } catch (err) {
      error = err.message;
    }

    assert.equal(error, "Sender not allowed to spend tokens from source");
  });

  it("should reduce Bob's allowance and Alice's balance after Bob spends 1000 tokens on behalf of Alice", async () => {
    const tokensToTransfer = 1000;
    const aliceInitialAccount = await storage.ledger.get(alice.pkh);
    const alicesAllowanceForBob = await aliceInitialAccount.allowances.get(
      bob.pkh
    );

    const op = await tzip7_instance.methods
      .transfer(alice.pkh, bob.pkh, tokensToTransfer)
      .send();
    await op.confirmation();
    // fetches the updated storage
    storage = await tzip7_instance.storage();
    const aliceAccount = await storage.ledger.get(alice.pkh);
    const alicesNewAllowanceForBob = await aliceAccount.allowances.get(bob.pkh);

    assert.equal(
      aliceAccount.balance.toNumber(),
      aliceInitialAccount.balance.toNumber() - tokensToTransfer
    );
    assert.equal(
      alicesNewAllowanceForBob,
      alicesAllowanceForBob - tokensToTransfer
    );
  });

  it("should burn 1000 tokens from Alice's balance and reduce total supply", async () => {
    // switches signer to Alice
    await signerFactory(alice.sk);

    const aliceInitialAccount = await storage.ledger.get(alice.pkh);
    const initialTotalSupply = storage.totalSupply;
    const tokensToBurn = 1000;

    const op = await tzip7_instance.methods.burn(tokensToBurn).send();
    await op.confirmation();

    // fetches the updated storage
    storage = await tzip7_instance.storage();
    // checks if Alice's balance and total supply have been reduced
    const aliceAccount = await storage.ledger.get(alice.pkh);

    assert.equal(
      aliceAccount.balance.toNumber(),
      aliceInitialAccount.balance.toNumber() - tokensToBurn
    );
    assert.equal(storage.totalSupply, initialTotalSupply - tokensToBurn);
  });

  it("should remove Bob's allowance approval from Alice's account", async () => {
    const op = await tzip7_instance.methods.removeApproval(bob.pkh).send();
    await op.confirmation();

    // fetches the updated storage
    storage = await tzip7_instance.storage();

    // fetching Bob's allowances should fail as Bob is not allowed anymore
    const aliceAccount = await storage.ledger.get(alice.pkh);

    assert.isUndefined(await aliceAccount.allowances.get(bob.pkh));
  });
});
