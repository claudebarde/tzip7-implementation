// This is an implementation of the FA1.2 specification in ReasonLIGO
type amountNat = nat;

type account = {
  balance: amountNat,
  allowances: map(address, amountNat)
};

type metadata = {
  token_id : nat,
  symbol : string,
  name : string,
  decimals : nat,
  extras : map (string, string)
};

type action =
  | Transfer ((address, address, amountNat))
  | Mint (amountNat)
  | Burn (amountNat)
  | Approve ((address, amountNat))
  | RemoveApproval (address)
  | GetAllowance ((address, address, contract(amountNat)))
  | GetBalance ((address, contract(amountNat)))
  | GetTotalSupply ((unit, contract(amountNat)))
  | GetMetadata ((unit, contract(metadata)))

type storage = {
  owner: address,
  metadata: metadata,
  totalSupply: amountNat,
  ledger: big_map(address, account)
};

let isAllowed = (accountFrom: address, value: amountNat, s: storage): bool => {
  if (Tezos.sender != accountFrom) {
    // Checking if the sender is allowed to spend in name of accountFrom
    switch (Big_map.find_opt(accountFrom, s.ledger)){
      | None => failwith("No account found!"): bool
      | Some (acc) => {
          switch (Map.find_opt(Tezos.sender, acc.allowances)){
          | None => false
          | Some (allowanceAmount) => allowanceAmount >= value
        }
      }
    }
  } else {
    true;
  }
}

// Transfer a specific amountNat of tokens from accountFrom address to a destination address
// Preconditions:
//  The sender address is the account owner or is allowed to spend x in the name of accountFrom
//  The accountFrom account has a balance higher than the amountNat
// Postconditions:
//  The balance of accountFrom is decreased by the amountNat
//  The balance of destination is increased by the amountNat
let transfer = (accountFrom: address, accountTo: address, value: amountNat, s: storage): storage => {
  // If accountFrom = destination transfer is not necessary
  if(accountFrom == accountTo) {
    failwith ("Origin and destination accounts can not be the same!"): storage;
  } else {
    if(!isAllowed(accountFrom, value, s)){
      failwith ("Sender not allowed to spend tokens from source"): storage;
    } else {
      // Fetch src account
      let src = switch(Map.find_opt(accountFrom, s.ledger)) {
        | None => failwith ("Account not found!"): account;
        | Some (src) => src
      };
      // Check that the accountFrom can spend that much
      if(value > src.balance){
        failwith ("Source balance is too low"): storage;
      } else {
        // Update the accountFrom balance
        // Using the abs function to convert int to nat
        let src_ = {...src, balance: abs(src.balance - value)};

        // Fetch destination account or add empty destination account to ledger
        // Update the destination balance
        let dest: account = switch(Map.find_opt(accountTo, s.ledger)){
          | None => {
              balance: value,
              allowances: Map.empty: map(address, amountNat)
            }
          | Some (n) => {...n, balance: n.balance + value}
        };

        // Decrease the allowance amountNat if necessary
        let new_allowances = switch(Map.find_opt(Tezos.sender, src_.allowances)){
          | None => src_.allowances
          | Some (dstAllowance) => 
            Big_map.update(Tezos.sender, Some (abs(dstAllowance - value)), src_.allowances) // ensure non negative
        };

        let new_storage = 
          {...s, 
            ledger: Big_map.update(accountFrom, Some ({...src_, allowances: new_allowances}), 
            s.ledger)};

        {...new_storage, ledger: Big_map.update(accountTo, Some (dest), new_storage.ledger)}
      }
    }
  }
}

// Mint tokens into the owner balance
// Preconditions:
//  The sender is the owner of the contract
// Postconditions:
//  The minted tokens are added in the balance of the owner
//  The totalSupply is increased by the amountNat of minted token
let mint = (value: amountNat, s: storage): storage => {
  // If the sender is not the owner fail
  if(Tezos.sender != s.owner){
    failwith ("You must be the owner of the contract to mint tokens"): storage;
  } else {
    let ownerAccount: account = switch(Map.find_opt(s.owner, s.ledger)){
      | None => {
          balance: 0n,
          allowances: Map.empty: map(address, amountNat)
        }
      | Some (acc) => acc
    };

    // Update the owner balance
    let updated_ownerAccount = {...ownerAccount, balance: ownerAccount.balance + value};
    // returns the new storage
    {...s, ledger: Big_map.update(s.owner, Some (updated_ownerAccount), s.ledger), totalSupply: s.totalSupply + value}
  }
}

// Burn tokens from the owner balance
// Preconditions:
//  The owner have the required balance to burn
// Postconditions:
//  The burned tokens are subtracted from the balance of the owner
//  The totalSupply is decreased by the amountNat of burned token 
let burn = (value: amountNat, s : storage):  storage => {
  // If the sender is not the owner fail
  if(Tezos.sender != s.owner){
    failwith("You must be the owner of the contract to burn tokens"):  storage;
  } else {
    let ownerAccount = switch(Big_map.find_opt(s.owner, s.ledger)){
      | None => {balance: 0n, allowances: Map.empty: map(address, amountNat)}
      | Some (acc) => acc
    };
    // Check that the owner can spend that much
    if(value > ownerAccount.balance){
      failwith ("Owner balance is too low"): storage;
    } else {
      // Update the owner balance
      // Using the abs function to convert int to nat
      let new_ownerAccount = {...ownerAccount, balance: abs(ownerAccount.balance - value)};

      {...s, 
        ledger: Big_map.update(s.owner, Some (new_ownerAccount), s.ledger), 
        totalSupply: abs(s.totalSupply - value)};
    }
  }
}

// Approve an amountNat to be spent by another address in the name of the sender
// Preconditions:
//  The spender account is not the sender account
// Postconditions:
//  The allowance of spender in the name of sender is value
let approve = (spender: address, value: amountNat, s : storage): storage => {
  // If sender is the spender approving is not necessary
  if(Tezos.sender == spender){
    failwith ("The account owner and the spender address cannot be the same!"): storage;
  } else {
    let src: account = switch(Big_map.find_opt(Tezos.sender, s.ledger)){
      | None => failwith ("Account not found!"): account;
      | Some (acc) => acc
    };
    
    let new_allowances = Map.update(spender, Some (value), src.allowances);

    {...s, 
      ledger: Big_map.update(Tezos.sender, Some ({...src, allowances: new_allowances}), s.ledger)
    }
  }
}

// Remove an address that was earlier approved to spend tokens on behalf of the account
// Preconditions:
//  The spender account is not the sender account
//  The spender address exists in the account
// Postconditions:
// The spender address no longer exists in the account

let removeApproval = (spender: address, s: storage): storage => {
  // If sender is the spender approving is not necessary
  if(Tezos.sender == spender){
    failwith ("The account owner and the spender address cannot be the same!"): storage;
  } else {
    switch(Big_map.find_opt(Tezos.sender, s.ledger)){
      | None => failwith ("Account not found!"): storage;
      | Some (acc) => {...s, 
          ledger: Big_map.update(Tezos.sender, Some ({...acc, allowances: Map.remove(spender, acc.allowances)}), 
          s.ledger)
        }
    };
  }
}

// View function that forwards the allowance amountNat of spender in the name of owner to a contract
// Preconditions:
//  None
// Postconditions:
//  The state is unchanged
let getAllowance = (owner: address, spender: address, contract: contract(amountNat), s: storage): list(operation) => {
  // finds owner's account
  let src: account = switch(Big_map.find_opt(owner, s.ledger)){
    | None => failwith ("Account not found!"): account
    | Some (acc) => acc
  };
  // gets spender's allowance
  let destAllowance: amountNat = switch(Map.find_opt(spender, src.allowances)){
    | None => failwith ("Account not found!"): amountNat
    | Some (allowances) => allowances
  };
  // returns transaction with allowance
  [Tezos.transaction(destAllowance, 0tz, contract)]: list(operation);
}

// View function that forwards the balance of source to a contract
// Preconditions:
//  None
// Postconditions:
//  The state is unchanged
let getBalance = (accountFrom: address, contract: contract(amountNat), s : storage): list(operation) => {
  let src: account = switch(Big_map.find_opt(accountFrom, s.ledger)){
    | None => failwith ("Account not found!"): account
    | Some (acc) => acc
  };
  // returns transaction with balance
  [Tezos.transaction(src.balance, 0tz, contract)]: list(operation);
}

// View function that forwards the totalSupply to a contract
// Preconditions:
//  None
// Postconditions:
//  The state is unchanged
let getTotalSupply = (contract: contract(amountNat), s: storage): list(operation) => {
  // returns transaction with total supply
  // this doesn't compile => [Tezos.transaction(s.totalSupply, 0tz, contr)]: list(operation);
  [Tezos.transaction(s.totalSupply, 0tz, contract)];
}

let getMetadata = (contract: contract(metadata), s: storage): list(operation) => {
  // returns transaction with metadata
  // this doesn't compile => [Tezos.transaction(s.metadata, 0tz, contr)]: list(operation);
  [Tezos.transaction(s.metadata, 0tz, contract)];
}

let main = ((p, s): (action, storage)): (list(operation), storage) => {
  // Reject any transaction that try to transfer token to this contract
  if(Tezos.amount != 0tz){
    failwith ("This contract do not accept token"): (list(operation), storage);
  } else {
    switch(p){
      | Transfer (n) => ([]: list(operation), transfer(n[0], n[1], n[2] , s))
      | Approve (n) => ([]: list(operation), approve(n[0], n[1], s))
      | RemoveApproval (n) => ([]: list(operation), removeApproval(n, s))
      | GetAllowance (n) => (getAllowance(n[0], n[1], n[2], s), s)
      | GetBalance (n) => (getBalance(n[0], n[1], s), s)
      | GetTotalSupply (n) => (getTotalSupply(n[1], s), s)
      | GetMetadata (n) => (getMetadata(n[1], s), s)
      | Mint (n) => ([]: list(operation), mint(n, s))
      | Burn (n) => ([]: list(operation), burn(n, s))
    };
  }
}