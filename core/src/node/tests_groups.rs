//! Tests for group chats (`groups.rs`).
use super::groups::pack_group;
use super::*;
use crate::transport::MemoryNetwork;

/// Make `b` a contact of `a` (and the reverse), with the pairing announcements exchanged.
fn pair(a: &mut Node, a_addr: &str, b: &mut Node) {
    let bundle = a.publish_bundle();
    b.connect_with_bundle(a_addr, &bundle).unwrap();
    for _ in 0..2 {
        a.pump().unwrap();
        b.pump().unwrap();
    }
}

fn pump_all(nodes: &mut [&mut Node]) {
    for _ in 0..2 {
        for n in nodes.iter_mut() {
            n.pump().unwrap();
        }
    }
}

/// Alice, Bob and Carol, each paired with the other two.
fn trio() -> (Node, Node, Node) {
    let net = MemoryNetwork::new();
    let mut alice = Node::new(Box::new(net.endpoint("alice")));
    let mut bob = Node::new(Box::new(net.endpoint("bob")));
    let mut carol = Node::new(Box::new(net.endpoint("carol")));
    pair(&mut alice, "alice", &mut bob);
    pair(&mut alice, "alice", &mut carol);
    pair(&mut bob, "bob", &mut carol);
    (alice, bob, carol)
}

fn msg_envelope(group_id: &str, msg_id: &str, text: &str) -> Vec<u8> {
    let mut body = Vec::new();
    put_field(&mut body, msg_id.as_bytes());
    body.extend_from_slice(text.as_bytes());
    pack_group(group_id, "msg", &body)
}

#[test]
fn pairing_tells_both_sides_the_peer_understands_groups() {
    let (alice, bob, carol) = trio();
    assert!(alice.peer_supports_groups(&bob.identity_key()));
    assert!(bob.peer_supports_groups(&alice.identity_key()));
    assert!(carol.peer_supports_groups(&bob.identity_key()));
}

#[test]
fn creating_a_group_adds_it_for_every_member() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("trio", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    for node in [&bob, &carol] {
        let groups = node.groups();
        assert_eq!(groups.len(), 1);
        let (id, name, members, creator, left) = groups[0].clone();
        assert_eq!(id, gid);
        assert_eq!(name, "trio");
        assert_eq!(members.len(), 3);
        assert!(members.contains(&alice.identity_key()));
        assert!(members.contains(&bob.identity_key()));
        assert!(members.contains(&carol.identity_key()));
        assert_eq!(creator, alice.identity_key());
        assert!(!left);
    }
}

#[test]
fn a_group_message_reaches_every_member_under_its_senders_name() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("talk", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    alice.send_group(&gid, "hello group").unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    for node in [&bob, &carol] {
        let last = node.group_messages(&gid).into_iter().last().unwrap();
        assert_eq!(last.sender, alice.identity_key());
        assert_eq!(last.message.text, "hello group");
        assert!(!last.message.from_me);
    }
    let mine = alice.group_messages(&gid).into_iter().last().unwrap();
    assert!(mine.message.from_me);
    assert_eq!(mine.sender, "");

    carol.send_group(&gid, "hi from carol").unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    for node in [&alice, &bob] {
        let last = node.group_messages(&gid).into_iter().last().unwrap();
        assert_eq!(last.sender, carol.identity_key());
        assert_eq!(last.message.text, "hi from carol");
    }
    // A group message is not an ordinary chat message.
    assert!(bob
        .messages(&alice.identity_key())
        .iter()
        .all(|m| m.text != "hello group"));
}

#[test]
fn a_message_from_someone_outside_the_group_is_ignored() {
    let net = MemoryNetwork::new();
    let mut alice = Node::new(Box::new(net.endpoint("alice")));
    let mut bob = Node::new(Box::new(net.endpoint("bob")));
    let mut carol = Node::new(Box::new(net.endpoint("carol")));
    pair(&mut alice, "alice", &mut bob);
    pair(&mut bob, "bob", &mut carol);

    let gid = alice.create_group("two", &[bob.identity_key()]).unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    let before = bob.group_messages(&gid).len();

    // Carol does not have the group, so she cannot send to it…
    assert!(carol.send_group(&gid, "let me in").is_err());
    // …and a frame naming it that arrives on her session with Bob changes nothing.
    let forged = msg_envelope(&gid, "id-1", "let me in");
    assert_eq!(
        bob.on_group_frame(&carol.identity_key(), &forged).unwrap(),
        None
    );
    assert_eq!(bob.group_messages(&gid).len(), before);
}

#[test]
fn the_same_message_arriving_twice_is_kept_once() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("dup", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    let before = bob.group_messages(&gid).len();

    let copy = msg_envelope(&gid, "same-id", "once");
    assert!(bob
        .on_group_frame(&alice.identity_key(), &copy)
        .unwrap()
        .is_some());
    assert_eq!(
        bob.on_group_frame(&alice.identity_key(), &copy).unwrap(),
        None
    );
    assert_eq!(bob.group_messages(&gid).len(), before + 1);
}

#[test]
fn leaving_removes_the_member_and_stops_their_messages() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("leave", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    bob.leave_group(&gid).unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    for node in [&alice, &carol] {
        let members = node.groups()[0].2.clone();
        assert_eq!(members.len(), 2);
        assert!(!members.contains(&bob.identity_key()));
    }
    assert!(bob.groups()[0].4, "Bob's copy is marked as left");
    assert!(bob.send_group(&gid, "still here?").is_err());

    let before = bob.group_messages(&gid).len();
    alice.send_group(&gid, "after bob left").unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    assert_eq!(bob.group_messages(&gid).len(), before);
    let last = carol.group_messages(&gid).into_iter().last().unwrap();
    assert_eq!(last.message.text, "after bob left");
}

#[test]
fn a_member_on_a_build_without_groups_cannot_be_added() {
    let net = MemoryNetwork::new();
    let mut alice = Node::new(Box::new(net.endpoint("alice")));
    let mut bob = Node::new(Box::new(net.endpoint("bob")));
    pair(&mut alice, "alice", &mut bob);
    // As if Bob's build had never announced group support.
    alice.groups_peers.clear();

    let err = alice
        .create_group("nope", &[bob.identity_key()])
        .unwrap_err()
        .to_string();
    assert!(err.contains("newer version"), "{err}");
    assert!(alice.groups().is_empty());
}

#[test]
fn an_operation_this_build_does_not_know_is_ignored() {
    let (mut alice, bob, _carol) = trio();
    let envelope = pack_group("some-group", "from-the-future", b"whatever");
    assert_eq!(
        alice
            .on_group_frame(&bob.identity_key(), &envelope)
            .unwrap(),
        None
    );
}

#[test]
fn groups_survive_a_restart() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("kept", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    alice.send_group(&gid, "remember me").unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    let key: StoreKey = [3u8; 32];
    let state = bob.export(&key);
    let net2 = MemoryNetwork::new();
    let bob2 = Node::restore(&state, Box::new(net2.endpoint("bob")), &key).unwrap();

    let groups = bob2.groups();
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].0, gid);
    assert_eq!(groups[0].2.len(), 3);
    let last = bob2.group_messages(&gid).into_iter().last().unwrap();
    assert_eq!(last.message.text, "remember me");
    assert_eq!(last.sender, alice.identity_key());
    assert!(bob2.peer_supports_groups(&alice.identity_key()));
}
