type storage = nat;

type balance_param = { callback: contract (nat), owner: address };
type allowance_param = { owner: address, spender: address, callback: contract (nat) }

type action =
  | GetTotalSupply (address)
  | ReceiveTotalSupply (nat)
  | GetBalance ((address, address))
  | ReceiveBalance (nat)
  | GetAllowance ((address, address, address))
  | ReceiveAllowance (nat);

let getTotalSupply = (contractAddr: address, s: storage): (list (operation), storage) => {
  // tzip7 contract from which the total supply should be requested
  let tzip7: contract (contract (nat)) = 
    switch(Tezos.get_entrypoint_opt("%getTotalSupply", contractAddr): option(contract(contract(nat)))){
    | None => failwith ("ContractNotFound"): contract (contract (nat))
    | Some (contr) => contr
  };
  // current contract where the total supply should be received
  let param: contract (nat) = 
    switch(Tezos.get_entrypoint_opt("%receiveTotalSupply", Tezos.self_address): option(contract(nat))){
    | None => failwith ("Error"): contract (nat)
    | Some (cb) => cb
  };
  // sends transaction
  ([Tezos.transaction(param, 0tez, tzip7)], s);
}

let receiveTotalSupply = (totalSupply: nat): storage => totalSupply;

let getBalance = (contractAddr: address, owner: address, s: storage): (list (operation), storage) => {
  // tzip7 contract from which the total supply should be requested
  let tzip7: contract (balance_param) = 
    switch(Tezos.get_entrypoint_opt("%getBalance", contractAddr): option(contract(balance_param))){
    | None => failwith ("ContractNotFound"): contract (balance_param)
    | Some (contr) => contr
  };
  // current contract where the total supply should be received
  let params = {
    owner: owner,
    callback: switch(Tezos.get_entrypoint_opt("%receiveBalance", Tezos.self_address): option(contract(nat))){
      | None => failwith ("Error"): contract (nat)
      | Some (cb) => cb
    }
  };

  // sends transaction
  ([Tezos.transaction(params, 0tez, tzip7)], s);
}

let receiveBalance = (accBalance: nat): storage => accBalance;

let getAllowance = (spender: address, owner: address, contractAddr: address, s: storage): (list (operation), storage) => {
  // tzip7 contract from which the total supply should be requested
  let tzip7: contract (allowance_param) = 
    switch(Tezos.get_entrypoint_opt("%getAllowance", contractAddr): option(contract(allowance_param))){
    | None => failwith ("ContractNotFound"): contract (allowance_param)
    | Some (contr) => contr
  };
  // current contract where the total supply should be received
  let params = {
    owner: owner,
    spender: spender,
    callback: switch(Tezos.get_entrypoint_opt("%receiveAllowance", Tezos.self_address): option(contract(nat))){
      | None => failwith ("Error"): contract (nat)
      | Some (cb) => cb
    }
  };

  // sends transaction
  ([Tezos.transaction(params, 0tez, tzip7)], s);
}

let receiveAllowance = (allowance: nat): storage => allowance;

let main = ((p, s): (action, storage)) => {
  switch (p) {
    | GetTotalSupply (contractAddr) => getTotalSupply(contractAddr, s)
    | ReceiveTotalSupply (n) => ([]: list (operation), receiveTotalSupply(n))
    | GetBalance (n) => getBalance(n[0], n[1], s)
    | ReceiveBalance (n) => ([]: list (operation), receiveBalance(n))
    | GetAllowance (n) => getAllowance(n[0], n[1], n[2], s)
    | ReceiveAllowance (n) => ([]: list (operation), receiveAllowance(n))
    };
};