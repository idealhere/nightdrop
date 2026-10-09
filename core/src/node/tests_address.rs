//! Tests for the standing address (`Node::my_address`).
use super::*;
use crate::transport::MemoryNetwork;

fn node(net: &MemoryNetwork, name: &str) -> Node {
    let mut node = Node::new(Box::new(net.endpoint(name)));
    node.set_require_authorization(true);
    node
}

fn pump_all(nodes: &mut [&mut Node]) {
    for _ in 0..3 {
        for n in nodes.iter_mut() {
            n.pump().unwrap();
        }
    }
}

#[test]
fn an_address_is_stable_and_can_be_used_by_several_people() {
    let net = MemoryNetwork::new();
    let mut alice = node(&net, "alice");
    let mut bob = node(&net, "bob");
    let mut carol = node(&net, "carol");

    let address = alice.my_address().unwrap();
    assert_eq!(alice.my_address().unwrap(), address);

    bob.connect_from_invite_payload(&address).unwrap();
    carol.connect_from_invite_payload(&address).unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    // Both arrive as requests, and both are marked as having come through the address.
    let mut expected = vec![bob.identity_key(), carol.identity_key()];
    expected.sort();
    assert_eq!(alice.address_requests(), expected);
    assert_eq!(alice.pending_authorizations().len(), 2);
    assert!(!alice.chats.get(&bob.identity_key()).unwrap().authorized);
}

#[test]
fn a_request_to_the_address_becomes_a_chat_once_accepted() {
    let net = MemoryNetwork::new();
    let mut alice = node(&net, "alice");
    let mut bob = node(&net, "bob");
    let address = alice.my_address().unwrap();
    bob.connect_from_invite_payload(&address).unwrap();
    pump_all(&mut [&mut alice, &mut bob]);

    alice.authorize(&bob.identity_key(), true).unwrap();
    pump_all(&mut [&mut alice, &mut bob]);
    assert!(alice.address_requests().is_empty());

    bob.send(&alice.identity_key(), "hello by address").unwrap();
    alice.send(&bob.identity_key(), "hello back").unwrap();
    pump_all(&mut [&mut alice, &mut bob]);
    assert_eq!(
        alice.messages(&bob.identity_key()).last().unwrap().text,
        "hello by address"
    );
    assert_eq!(
        bob.messages(&alice.identity_key()).last().unwrap().text,
        "hello back"
    );
}

#[test]
fn an_ordinary_invite_is_not_an_address_request() {
    let net = MemoryNetwork::new();
    let mut alice = node(&net, "alice");
    let mut bob = node(&net, "bob");
    alice.my_address().unwrap();
    let bundle = alice.publish_bundle();
    bob.connect_with_bundle("alice", &bundle).unwrap();
    pump_all(&mut [&mut alice, &mut bob]);

    assert_eq!(alice.pending_authorizations().len(), 1);
    assert!(alice.address_requests().is_empty());
}

#[test]
fn the_same_request_arriving_again_is_dropped() {
    let net = MemoryNetwork::new();
    let mut alice = node(&net, "alice");
    let mut bob = node(&net, "bob");
    let address = alice.my_address().unwrap();
    bob.connect_from_invite_payload(&address).unwrap();
    pump_all(&mut [&mut alice, &mut bob]);

    // Any ciphertext will do as a stand-in for a captured first message.
    let chat = bob.chats.get_mut(&alice.identity_key()).unwrap();
    let captured = WireOlm::from_olm(&crypto::encrypt(&mut chat.session, b"captured"));
    assert!(
        alice.note_address_hello(&captured),
        "seen for the first time"
    );
    assert!(!alice.note_address_hello(&captured), "a replay");
}

#[test]
fn the_address_survives_a_restart() {
    let net = MemoryNetwork::new();
    let mut alice = node(&net, "alice");
    let address = alice.my_address().unwrap();

    let key: StoreKey = [5u8; 32];
    let state = alice.export(&key);
    let mut alice2 = Node::restore(&state, Box::new(net.endpoint("alice2")), &key).unwrap();
    alice2.set_require_authorization(true);
    // Same identity and same pre-key; only the transport address differs in this test.
    let after = alice2.my_address().unwrap();
    let keys = |a: &str| a.split_once("&ik=").map(|(_, rest)| rest.to_string());
    assert_eq!(keys(&after), keys(&address));

    let mut bob = node(&net, "bob");
    bob.connect_from_invite_payload(&after).unwrap();
    pump_all(&mut [&mut alice2, &mut bob]);
    assert_eq!(alice2.address_requests(), vec![bob.identity_key()]);
}
