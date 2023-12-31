#[starknet::contract]
mod ERC20 {
    use option::OptionTrait;
    use traits::TryInto;
    use integer::BoundedInt;
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use zeroable::Zeroable;
    use debug::PrintTrait;

    use starkpepe::token::interface::{
        token::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait},
        eth::{IETHDispatcher, IETHDispatcherTrait}
    };

    #[storage]
    struct Storage {
        _name: felt252,
        _symbol: felt252,
        _total_supply: u256,
        _balances: LegacyMap<ContractAddress, u256>,
        _allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
        owner: ContractAddress,
        hodl_limit: bool,
        pool_addresses: LegacyMap<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256
    }

    const MAX_SUPPLY: u256 = 42_000_000_000_000000000000000000;
    const JEDI_ROUTER: felt252 = 0x041fd22b238fa21cfcf5dd45a8548974d8263b3a531a60388411c5e230f97023;

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        recipient: ContractAddress,
        owner: ContractAddress,
    ) {
        self.initializer(
            name,
            symbol,
            initial_supply,
            recipient,
            owner
        );
    }

    //
    // External
    //

    #[abi(embed_v0)]
    impl ERC20Impl of IERC20<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self._name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self._symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            18
        }

        fn total_supply(self: @ContractState) -> u256 {
            self._total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self._balances.read(account)
        }

        fn totalSupply(self: @ContractState) -> u256 {
            self._total_supply.read()
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self._balances.read(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self._allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            self._spend_allowance(sender, caller, amount);
            self._transfer(sender, recipient, amount);
            true
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            self._spend_allowance(sender, caller, amount);
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self._approve(caller, spender, amount);
            true
        }

        fn withdraw_other(ref self: ContractState, amount: u256, receiver: ContractAddress, token: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'ERC20: not owner');

            IERC20Dispatcher{contract_address: token}.transfer(receiver, amount);
        }

        fn add_pool(ref self: ContractState, pool_address: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'ERC20: not owner');

            self._add_pool(:pool_address);
        }

        fn set_hodl_limit(ref self: ContractState, hodl_limit: bool) {
            assert(get_caller_address() == self.owner.read(), 'ERC20: not owner');

            self.hodl_limit.write(hodl_limit);
        }

    }

    #[external(v0)]
    fn increase_allowance(
        ref self: ContractState, spender: ContractAddress, added_value: u256
    ) -> bool {
        self._increase_allowance(spender, added_value)
    }

    #[external(v0)]
    fn increaseAllowance(
        ref self: ContractState, spender: ContractAddress, addedValue: u256
    ) -> bool {
        increase_allowance(ref self, spender, addedValue)
    }

    #[external(v0)]
    fn decrease_allowance(
        ref self: ContractState, spender: ContractAddress, subtracted_value: u256
    ) -> bool {
        self._decrease_allowance(spender, subtracted_value)
    }

    #[external(v0)]
    fn decreaseAllowance(
        ref self: ContractState, spender: ContractAddress, subtractedValue: u256
    ) -> bool {
        decrease_allowance(ref self, spender, subtractedValue)
    }



    //
    // Internal
    //

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn initializer(
            ref self: ContractState,
            name: felt252,
            symbol: felt252,
            initial_supply: u256,
            recipient: ContractAddress,
            owner: ContractAddress,
        ) {
            self._name.write(name);
            self._symbol.write(symbol);
            self.owner.write(owner);
            self.hodl_limit.write(true);
            self._mint(recipient, initial_supply);
            self._add_pool(pool_address: JEDI_ROUTER.try_into().unwrap());
        }

        fn _add_pool(ref self: ContractState, pool_address: ContractAddress) {
            self.pool_addresses.write(pool_address, true);
        }

        fn _increase_allowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256
        ) -> bool {
            let caller = get_caller_address();
            self._approve(caller, spender, self._allowances.read((caller, spender)) + added_value);
            true
        }

        fn _decrease_allowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256
        ) -> bool {
            let caller = get_caller_address();
            self
                ._approve(
                    caller, spender, self._allowances.read((caller, spender)) - subtracted_value
                );
            true
        }

        fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            assert(!recipient.is_zero(), 'ERC20: mint to 0');
            assert(self._total_supply.read() + amount <= MAX_SUPPLY, 'ERC20: exceed total supply');

            self._total_supply.write(self._total_supply.read() + amount);
            self._balances.write(recipient, self._balances.read(recipient) + amount);

            self.emit(Transfer { from: Zeroable::zero(), to: recipient, value: amount });
        }

        fn _approve(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            assert(!owner.is_zero(), 'ERC20: approve from 0');
            assert(!spender.is_zero(), 'ERC20: approve to 0');

            self._allowances.write((owner, spender), amount);

            self.emit(Approval { owner, spender, value: amount });
        }

        fn _transfer(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), 'ERC20: transfer from 0');
            assert(!recipient.is_zero(), 'ERC20: transfer to 0');

            let sender_balance = self._balances.read(sender) - amount;
            let recipient_balance = self._balances.read(recipient) + amount;

            // hodl limit check
            let is_owner = self.owner.read() == sender;
            let is_hodl_limit_enabled = self.hodl_limit.read();

            if (is_hodl_limit_enabled && !is_owner && !self.pool_addresses.read(recipient)) {
                assert(recipient_balance <= self.total_supply() / 100, 'hodl limit active, 1% max');
            }

            // balances update
            self._balances.write(sender, sender_balance);
            self._balances.write(recipient, recipient_balance);

            // transfer event
            self.emit(Transfer { from: sender, to: recipient, value: amount });
        }

        fn _spend_allowance(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            let current_allowance = self._allowances.read((owner, spender));

            if current_allowance != BoundedInt::max() {
                self._approve(owner, spender, current_allowance - amount);
            }
        }
    }
}
