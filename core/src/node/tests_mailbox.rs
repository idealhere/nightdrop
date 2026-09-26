//! v2 mailbox handles (`docs/design/mailbox-handles.md`, `mailbox.rs`). The property that matters
//! most is the one the design puts first: **no message is ever addressed to a handle its recipient
//! cannot compute.** Each test here is a way that could go wrong.
use super::mailbox::{current_epoch, pair_secret, v2_handle, MailboxPair};
use super::*;
use crate::relay_client::{RelayClient, RelayServer};
use crate::transport::MemoryNetwork;

struct Pair {
    net: MemoryNetwork,
    relay: RelayClient,
    alice: Node,
    bob: Node,
    /// Bob as Alice knows him, and Alice as Bob knows her.
    bob_id: String,
    alice_id: String,
}

/// Pair Alice and Bob over one relay, then let their pumps run the agreement to completion.
/// `legacy_bob` makes Bob a build from before v2 (he never sends or reads a `MailboxKey`).
fn pair(legacy_bob: bool) -> Pair {
    let relay = RelayClient::new(RelayServer::spawn("127.0.0.1:0").unwrap().to_string());
    let net = MemoryNetwork::new();
    let mut alice = Node::new(Box::new(net.endpoint("alice")));
    let mut bob = Node::new(Box::new(net.endpoint("bob")));
    alice.set_relay(relay.clone());
    bob.set_relay(relay.clone());
    bob.legacy_v1_only = legacy_bob;
    let bundle = alice.publish_bundle();
    let alice_id = bob.connect_with_bundle("alice", &bundle).unwrap();
    for _ in 0..3 {
        alice.pump().unwrap();
        bob.pump().unwrap();
    }
    let bob_id = alice.contacts()[0].id.clone();
    Pair {
        net,
        relay,
        alice,
        bob,
        bob_id,
        alice_id,
    }
}

fn confirmed(node: &Node, contact: &str) -> bool {
    node.chats[contact]
        .mailbox
        .as_ref()
        .is_some_and(|p| p.peer_confirmed)
}

fn received_texts(node: &Node, contact: &str) -> Vec<String> {
    node.messages(contact)
        .into_iter()
        .filter(|m| !m.from_me && !m.system)
        .map(|m| m.text)
        .collect()
}

#[test]
fn two_new_builds_agree_and_offline_mail_travels_under_a_v2_handle() {
    let mut p = pair(false);
    assert!(
        confirmed(&p.alice, &p.bob_id),
        "Alice holds Bob's confirmation"
    );
    assert!(
        confirmed(&p.bob, &p.alice_id),
        "Bob holds Alice's confirmation"
    );

    p.net.disconnect("bob");
    p.alice.send(&p.bob_id, "under v2").unwrap();

    let v2 = p.alice.post_handle(&p.bob_id);
    assert_ne!(v2, mailbox_handle(&p.bob_id), "a confirmed pair posts v2");
    assert_eq!(
        p.relay.peek(&v2).unwrap(),
        1,
        "the copy sits under today's v2 handle"
    );
    assert_eq!(
        p.relay.peek(&mailbox_handle(&p.bob_id)).unwrap(),
        0,
        "and nothing under Bob's static v1 handle"
    );

    p.net.reconnect("bob");
    p.bob.poll_relay().unwrap();
    assert!(received_texts(&p.bob, &p.alice_id).contains(&"under v2".to_string()));
}

#[test]
fn a_new_build_keeps_an_old_peer_on_v1_in_both_directions() {
    let mut p = pair(true);
    assert!(
        !confirmed(&p.alice, &p.bob_id),
        "an old build never confirms, so Alice never switches"
    );
    assert_eq!(p.alice.post_handle(&p.bob_id), mailbox_handle(&p.bob_id));

    // New → old, offline.
    p.net.disconnect("bob");
    p.alice.send(&p.bob_id, "to the old build").unwrap();
    p.net.reconnect("bob");
    p.bob.poll_relay().unwrap();
    assert!(received_texts(&p.bob, &p.alice_id).contains(&"to the old build".to_string()));

    // Old → new, offline: the old build posts v1, which the new one still polls.
    p.net.disconnect("alice");
    p.bob.send(&p.alice_id, "from the old build").unwrap();
    p.net.reconnect("alice");
    p.alice.poll_relay().unwrap();
    assert!(received_texts(&p.alice, &p.bob_id).contains(&"from the old build".to_string()));
}

#[test]
fn half_an_agreement_never_posts_v2() {
    let mut p = pair(false);
    // Alice has Bob's contribution but not his confirmation — as if that frame were lost.
    let pair_state = p
        .alice
        .chats
        .get_mut(&p.bob_id)
        .unwrap()
        .mailbox
        .as_mut()
        .unwrap();
    pair_state.peer_confirmed = false;
    assert_eq!(
        p.alice.post_handle(&p.bob_id),
        mailbox_handle(&p.bob_id),
        "without proof the peer holds the secret, mail goes to v1"
    );
}

#[test]
fn a_peer_that_restores_an_old_backup_is_not_left_with_unreadable_mail() {
    let mut p = pair(false);
    assert!(confirmed(&p.alice, &p.bob_id));

    // Bob loses his side (restored from before the agreement) and starts again.
    p.bob.chats.get_mut(&p.alice_id).unwrap().mailbox = Some(MailboxPair::fresh());
    p.bob.mailbox_announced.clear();
    p.bob.announce_mailbox();
    p.alice.pump().unwrap();

    // Before anything else crosses, Alice must already be back on v1 for him.
    // (She has his new contribution and replied; his confirmation of the NEW secret is not in yet.)
    assert_eq!(
        p.alice.post_handle(&p.bob_id),
        mailbox_handle(&p.bob_id),
        "a changed contribution drops the pair to v1 at once"
    );
    p.net.disconnect("bob");
    p.alice.send(&p.bob_id, "during the re-agreement").unwrap();
    p.net.reconnect("bob");
    p.bob.poll_relay().unwrap();
    assert!(received_texts(&p.bob, &p.alice_id).contains(&"during the re-agreement".to_string()));

    // And they settle on the new secret.
    for _ in 0..3 {
        p.bob.pump().unwrap();
        p.alice.pump().unwrap();
    }
    assert!(confirmed(&p.alice, &p.bob_id) && confirmed(&p.bob, &p.alice_id));
}

#[test]
fn readers_poll_the_neighbouring_days_so_midnight_loses_nothing() {
    let p = pair(false);
    let bob_pair = p.bob.chats[&p.alice_id].mailbox.clone().unwrap();
    let secret = pair_secret(
        &p.bob.identity_key(),
        &p.alice_id,
        &bob_pair.own,
        &bob_pair.peer.unwrap(),
    );
    let polled = p.bob.drain_handles();
    let today = current_epoch();
    for epoch in [today - 1, today, today + 1] {
        assert!(
            polled.contains(&v2_handle(&secret, &p.bob.identity_key(), epoch)),
            "Bob polls day {epoch} (today is {today})"
        );
    }
    assert!(
        polled.contains(&mailbox_handle(&p.bob.identity_key())),
        "and v1, throughout the transition"
    );
    assert!(
        !polled.contains(&v2_handle(&secret, &p.alice_id, today)),
        "never the other direction's handle — that is Alice's mail"
    );
}

#[test]
fn the_agreement_survives_a_restart() {
    let p = pair(false);
    let key = [5u8; 32];
    let saved = p.alice.export(&key);
    let restored = Node::restore(&saved, Box::new(p.net.endpoint("alice2")), &key).unwrap();
    assert_eq!(
        restored.chats[&p.bob_id].mailbox, p.alice.chats[&p.bob_id].mailbox,
        "own and peer contributions and both flags come back as they were"
    );
    assert_eq!(
        restored.post_handle(&p.bob_id),
        p.alice.post_handle(&p.bob_id)
    );
}

#[test]
fn an_edit_recalls_a_copy_posted_under_v2() {
    let mut p = pair(false);
    p.net.disconnect("bob");
    p.alice.send(&p.bob_id, "first draft").unwrap();
    let v2 = p.alice.post_handle(&p.bob_id);
    assert_eq!(p.relay.peek(&v2).unwrap(), 1);
    let msg_id = p.alice.messages(&p.bob_id).last().unwrap().msg_id.clone();
    p.alice.edit_message(&p.bob_id, &msg_id, "final").unwrap();
    // The recall found the v2 copy (else the old text would still be waiting beside the new).
    p.net.reconnect("bob");
    p.bob.poll_relay().unwrap();
    let got = received_texts(&p.bob, &p.alice_id);
    assert!(got.contains(&"final".to_string()));
    assert!(
        !got.contains(&"first draft".to_string()),
        "the recalled draft never arrives"
    );
}
