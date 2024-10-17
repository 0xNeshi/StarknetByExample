use core::num::traits::Zero;
use erc721::erc721::{
    IERC721Dispatcher, IERC721DispatcherTrait, ERC721::{Event, Transfer, Approval, ApprovalForAll}
};
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait, start_cheat_caller_address, spy_events,
    EventSpyAssertionsTrait,
};
use starknet::{ContractAddress, contract_address_const};

pub const SUCCESS: felt252 = 'SUCCESS';
pub const FAILURE: felt252 = 'FAILURE';
pub const PUBKEY: felt252 = 'PUBKEY';
pub const TOKEN_ID: u256 = 21;

pub fn CALLER() -> ContractAddress {
    contract_address_const::<'CALLER'>()
}

pub fn OPERATOR() -> ContractAddress {
    contract_address_const::<'OPERATOR'>()
}

pub fn OTHER() -> ContractAddress {
    contract_address_const::<'OTHER'>()
}

pub fn OWNER() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}

pub fn RECIPIENT() -> ContractAddress {
    contract_address_const::<'RECIPIENT'>()
}

pub fn SPENDER() -> ContractAddress {
    contract_address_const::<'SPENDER'>()
}

pub fn ZERO() -> ContractAddress {
    contract_address_const::<0>()
}

pub fn DATA(success: bool) -> Span<felt252> {
    let value = if success {
        SUCCESS
    } else {
        FAILURE
    };
    array![value].span()
}

fn deploy_account() -> ContractAddress {
    let contract = declare("AccountMock").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![PUBKEY]).unwrap();
    contract_address
}

fn deploy_receiver() -> ContractAddress {
    let contract = declare("ERC721ReceiverMock").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

fn deploy_non_receiver() -> ContractAddress {
    let contract = declare("NonReceiverMock").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

fn setup() -> (IERC721Dispatcher, ContractAddress) {
    let contract = declare("ERC721").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    let contract = IERC721Dispatcher { contract_address };
    contract.mint(OWNER(), TOKEN_ID);
    (contract, contract_address)
}

//
// Getters
//

#[test]
fn test_balance_of() {
    let (contract, _) = setup();
    assert_eq!(contract.balance_of(OWNER()), 1);
}

#[test]
#[should_panic(expected: ('ERC721: invalid account',))]
fn test_balance_of_zero() {
    let (contract, _) = setup();
    contract.balance_of(ZERO());
}

#[test]
fn test_owner_of() {
    let (contract, _) = setup();
    assert_eq!(contract.owner_of(TOKEN_ID), OWNER());
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID',))]
fn test_owner_of_non_minted() {
    let (contract, _) = setup();
    contract.owner_of(7);
}

#[test]
fn test_get_approved() {
    let (mut contract, contract_address) = setup();
    let spender = SPENDER();
    let token_id = TOKEN_ID;

    start_cheat_caller_address(contract_address, OWNER());

    assert_eq!(contract.get_approved(token_id), ZERO());
    contract.approve(spender, token_id);
    assert_eq!(contract.get_approved(token_id), spender);
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID',))]
fn test_get_approved_nonexistent() {
    let (contract, _) = setup();
    contract.get_approved(7);
}

//
// approve
//

#[test]
fn test_approve_from_owner() {
    let (mut contract, contract_address) = setup();
    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, OWNER());
    contract.approve(SPENDER(), TOKEN_ID);

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Approval(
                        Approval { owner: OWNER(), approved: SPENDER(), token_id: TOKEN_ID }
                    )
                )
            ]
        );

    let approved = contract.get_approved(TOKEN_ID);
    assert_eq!(approved, SPENDER());
}

#[test]
fn test_approve_from_operator() {
    let (mut contract, contract_address) = setup();

    start_cheat_caller_address(contract_address, OWNER());
    contract.set_approval_for_all(OPERATOR(), true);

    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, OPERATOR());
    contract.approve(SPENDER(), TOKEN_ID);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Approval(
                        Approval { owner: OWNER(), approved: SPENDER(), token_id: TOKEN_ID }
                    )
                )
            ]
        );

    let approved = contract.get_approved(TOKEN_ID);
    assert_eq!(approved, SPENDER());
}

#[test]
#[should_panic(expected: ('ERC721: unauthorized caller',))]
fn test_approve_from_unauthorized() {
    let (mut contract, contract_address) = setup();

    start_cheat_caller_address(contract_address, OTHER());
    contract.approve(SPENDER(), TOKEN_ID);
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID',))]
fn test_approve_nonexistent() {
    let (mut contract, _) = setup();
    contract.approve(SPENDER(), TOKEN_ID);
}

#[test]
fn test_approve_auth_is_approved_for_all() {
    let (mut contract, contract_address) = setup();
    let auth = CALLER();

    start_cheat_caller_address(contract_address, OWNER());
    contract.set_approval_for_all(auth, true);

    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, auth);
    contract.approve(SPENDER(), TOKEN_ID);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Approval(
                        Approval { owner: OWNER(), approved: SPENDER(), token_id: TOKEN_ID }
                    )
                )
            ]
        );

    let approved = contract.get_approved(TOKEN_ID);
    assert_eq!(approved, SPENDER());
}

//
// set_approval_for_all
//

#[test]
fn test_set_approval_for_all() {
    let (mut contract, contract_address) = setup();
    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, OWNER());
    let not_approved_for_all = !contract.is_approved_for_all(OWNER(), OPERATOR());
    assert!(not_approved_for_all);

    contract.set_approval_for_all(OPERATOR(), true);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::ApprovalForAll(
                        ApprovalForAll { owner: OWNER(), operator: OPERATOR(), approved: true }
                    )
                )
            ]
        );

    let is_approved_for_all = contract.is_approved_for_all(OWNER(), OPERATOR());
    assert!(is_approved_for_all);

    contract.set_approval_for_all(OPERATOR(), false);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::ApprovalForAll(
                        ApprovalForAll { owner: OWNER(), operator: OPERATOR(), approved: false }
                    )
                )
            ]
        );

    let not_approved_for_all = !contract.is_approved_for_all(OWNER(), OPERATOR());
    assert!(not_approved_for_all);
}

#[test]
#[should_panic(expected: ('ERC721: invalid operator',))]
fn test_set_approval_for_all_invalid_operator() {
    let (mut contract, _) = setup();
    contract.set_approval_for_all(ZERO(), true);
}

//
// transfer_from
//

#[test]
fn test_transfer_from_owner() {
    let (mut contract, contract_address) = setup();
    let token_id = TOKEN_ID;
    let owner = OWNER();
    let recipient = RECIPIENT();

    // set approval to check reset
    start_cheat_caller_address(contract_address, owner);
    contract.approve(OTHER(), token_id);

    assert_state_before_transfer(contract, owner, recipient, token_id);

    let approved = contract.get_approved(token_id);
    assert_eq!(approved, OTHER());

    let mut spy = spy_events();

    contract.transfer_from(owner, recipient, token_id);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Transfer(Transfer { from: owner, to: recipient, token_id })
                )
            ]
        );

    assert_state_after_transfer(contract, owner, recipient, token_id);
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID',))]
fn test_transfer_from_nonexistent() {
    let (mut contract, contract_address) = setup();
    start_cheat_caller_address(contract_address, OWNER());
    contract.transfer_from(ZERO(), RECIPIENT(), TOKEN_ID);
}

#[test]
#[should_panic(expected: ('ERC721: invalid receiver',))]
fn test_transfer_from_to_zero() {
    let (mut contract, contract_address) = setup();
    start_cheat_caller_address(contract_address, OWNER());
    contract.transfer_from(OWNER(), ZERO(), TOKEN_ID);
}

#[test]
fn test_transfer_from_to_owner() {
    let (mut contract, contract_address) = setup();
    let mut spy = spy_events();

    assert_eq!(contract.owner_of(TOKEN_ID), OWNER());
    assert_eq!(contract.balance_of(OWNER()), 1);

    start_cheat_caller_address(contract_address, OWNER());
    contract.transfer_from(OWNER(), OWNER(), TOKEN_ID);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Transfer(Transfer { from: OWNER(), to: OWNER(), token_id: TOKEN_ID })
                )
            ]
        );

    assert_eq!(contract.owner_of(TOKEN_ID), OWNER());
    assert_eq!(contract.balance_of(OWNER()), 1);
}

#[test]
fn test_transfer_from_approved() {
    let (mut contract, contract_address) = setup();
    let token_id = TOKEN_ID;
    let owner = OWNER();
    let recipient = RECIPIENT();

    assert_state_before_transfer(contract, owner, recipient, token_id);

    start_cheat_caller_address(contract_address, owner);
    contract.approve(OPERATOR(), token_id);

    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, OPERATOR());
    contract.transfer_from(owner, recipient, token_id);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Transfer(Transfer { from: owner, to: recipient, token_id })
                )
            ]
        );

    assert_state_after_transfer(contract, owner, recipient, token_id);
}

#[test]
fn test_transfer_from_approved_for_all() {
    let (mut contract, contract_address) = setup();
    let token_id = TOKEN_ID;
    let owner = OWNER();
    let recipient = RECIPIENT();

    assert_state_before_transfer(contract, owner, recipient, token_id);

    start_cheat_caller_address(contract_address, owner);
    contract.set_approval_for_all(OPERATOR(), true);

    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, OPERATOR());
    contract.transfer_from(owner, recipient, token_id);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Transfer(Transfer { from: owner, to: recipient, token_id })
                )
            ]
        );

    assert_state_after_transfer(contract, owner, recipient, token_id);
}

#[test]
#[should_panic(expected: ('ERC721: unauthorized caller',))]
fn test_transfer_from_unauthorized() {
    let (mut contract, contract_address) = setup();
    start_cheat_caller_address(contract_address, OTHER());
    contract.transfer_from(OWNER(), RECIPIENT(), TOKEN_ID);
}

//
// safe_transfer_from
//

#[test]
fn test_safe_transfer_from_to_account() {
    let (mut contract, contract_address) = setup();
    let account = deploy_account();
    let mut spy = spy_events();
    let token_id = TOKEN_ID;
    let owner = OWNER();

    assert_state_before_transfer(contract, owner, account, token_id);

    start_cheat_caller_address(contract_address, owner);
    contract.safe_transfer_from(owner, account, token_id, DATA(true));
    spy
        .assert_emitted(
            @array![
                (contract_address, Event::Transfer(Transfer { from: owner, to: account, token_id }))
            ]
        );

    assert_state_after_transfer(contract, owner, account, token_id);
}

#[test]
fn test_safe_transfer_from_to_receiver() {
    let (mut contract, contract_address) = setup();
    let receiver = deploy_receiver();
    let mut spy = spy_events();
    let token_id = TOKEN_ID;
    let owner = OWNER();

    assert_state_before_transfer(contract, owner, receiver, token_id);

    start_cheat_caller_address(contract_address, owner);
    contract.safe_transfer_from(owner, receiver, token_id, DATA(true));
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Transfer(Transfer { from: owner, to: receiver, token_id })
                )
            ]
        );

    assert_state_after_transfer(contract, owner, receiver, token_id);
}

#[test]
#[should_panic(expected: ('ERC721: safe transfer failed',))]
fn test_safe_transfer_from_to_receiver_failure() {
    let (mut contract, contract_address) = setup();
    let receiver = deploy_receiver();
    let token_id = TOKEN_ID;
    let owner = OWNER();

    start_cheat_caller_address(contract_address, owner);
    contract.safe_transfer_from(owner, receiver, token_id, DATA(false));
}

#[test]
#[ignore] // REASON: should_panic attribute not fit for complex panic messages.
#[should_panic(expected: ('ENTRYPOINT_NOT_FOUND',))]
fn test_safe_transfer_from_to_non_receiver() {
    let (mut contract, contract_address) = setup();
    let recipient = deploy_non_receiver();
    let token_id = TOKEN_ID;
    let owner = OWNER();

    start_cheat_caller_address(contract_address, owner);
    contract.safe_transfer_from(owner, recipient, token_id, DATA(true));
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID',))]
fn test_safe_transfer_from_nonexistent() {
    let (mut contract, contract_address) = setup();
    start_cheat_caller_address(contract_address, OWNER());
    contract.safe_transfer_from(ZERO(), RECIPIENT(), TOKEN_ID, DATA(true));
}

#[test]
#[should_panic(expected: ('ERC721: invalid receiver',))]
fn test_safe_transfer_from_to_zero() {
    let (mut contract, contract_address) = setup();
    start_cheat_caller_address(contract_address, OWNER());
    contract.safe_transfer_from(OWNER(), ZERO(), TOKEN_ID, DATA(true));
}

#[test]
fn test_safe_transfer_from_to_owner() {
    let (mut contract, contract_address) = setup();
    let token_id = TOKEN_ID;
    let owner = deploy_receiver();

    assert_eq!(contract.owner_of(token_id), owner);
    assert_eq!(contract.balance_of(owner), 1);

    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, owner);
    contract.safe_transfer_from(owner, owner, token_id, DATA(true));
    spy
        .assert_emitted(
            @array![
                (contract_address, Event::Transfer(Transfer { from: owner, to: owner, token_id }))
            ]
        );

    assert_eq!(contract.owner_of(token_id), owner);
    assert_eq!(contract.balance_of(owner), 1);
}

#[test]
fn test_safe_transfer_from_approved() {
    let (mut contract, contract_address) = setup();
    let receiver = deploy_receiver();
    let token_id = TOKEN_ID;
    let owner = OWNER();

    assert_state_before_transfer(contract, owner, receiver, token_id);

    start_cheat_caller_address(contract_address, owner);
    contract.approve(OPERATOR(), token_id);

    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, OPERATOR());
    contract.safe_transfer_from(owner, receiver, token_id, DATA(true));
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Transfer(Transfer { from: owner, to: receiver, token_id })
                )
            ]
        );

    assert_state_after_transfer(contract, owner, receiver, token_id);
}

#[test]
fn test_safe_transfer_from_approved_for_all() {
    let (mut contract, contract_address) = setup();
    let receiver = deploy_receiver();
    let token_id = TOKEN_ID;
    let owner = OWNER();

    assert_state_before_transfer(contract, owner, receiver, token_id);

    start_cheat_caller_address(contract_address, owner);
    contract.set_approval_for_all(OPERATOR(), true);

    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, OPERATOR());
    contract.safe_transfer_from(owner, receiver, token_id, DATA(true));
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Transfer(Transfer { from: owner, to: receiver, token_id })
                )
            ]
        );

    assert_state_after_transfer(contract, owner, receiver, token_id);
}

#[test]
#[should_panic(expected: ('ERC721: unauthorized caller',))]
fn test_safe_transfer_from_unauthorized() {
    let (mut contract, contract_address) = setup();
    start_cheat_caller_address(contract_address, OTHER());
    contract.safe_transfer_from(OWNER(), RECIPIENT(), TOKEN_ID, DATA(true));
}

//
// Helpers
//

fn assert_state_before_transfer(
    contract: IERC721Dispatcher, owner: ContractAddress, recipient: ContractAddress, token_id: u256
) {
    assert_eq!(contract.owner_of(token_id), owner);
    assert_eq!(contract.balance_of(owner), 1);
    assert!(contract.balance_of(recipient).is_zero());
}

fn assert_state_after_transfer(
    contract: IERC721Dispatcher, owner: ContractAddress, recipient: ContractAddress, token_id: u256
) {
    assert_eq!(contract.owner_of(token_id), recipient);
    assert_eq!(contract.balance_of(owner), 0);
    assert_eq!(contract.balance_of(recipient), 1);
    assert!(contract.get_approved(token_id).is_zero());
}
