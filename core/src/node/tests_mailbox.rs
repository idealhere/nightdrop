//! v2 mailbox handles (`docs/design/mailbox-handles.md`, `mailbox.rs`). The property that matters
//! most is the one the design puts first: **no message is ever addressed to a handle its recipient
//! cannot compute.** Each test here is a way that could go wrong.
use super::mailbox::{
    current_epoch, pair_secret, v2_handle, MailboxPair, OLD_VERSION_GRACE_SECS, POLL_PAD,
};
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

// ---- Stage 2: fragmented, isolated polling and per-recipient posting (§5a/§5c, §8) ----

use crate::relay_client::RelayDialer;
use crate::transport::{Address, MemoryTransport, Transport};
use std::sync::{Arc, Mutex};

/// (isolation group — `None` for the default circuits, op, handle), one per relay request.
type Log = Arc<Mutex<Vec<(Option<u64>, String, String)>>>;

fn recording_dialer(log: &Log, group: Option<u64>) -> RelayDialer {
    let log = Arc::clone(log);
    Arc::new(move |line: &str| {
        let v: serde_json::Value = serde_json::from_str(line.trim()).unwrap();
        let op = v
            .as_object()
            .and_then(|o| {
                o.get("op")
                    .or_else(|| o.keys().next().and_then(|k| o.get(k)))
            })
            .map(|x| x.to_string())
            .unwrap_or_default();
        // `take_many` names a list; everything else one `handle`. One log row per handle.
        let req = v.get("req").unwrap_or(&v);
        let handles: Vec<String> = match req.get("handles") {
            Some(list) => list
                .as_array()
                .unwrap()
                .iter()
                .map(|h| h.as_str().unwrap().to_string())
                .collect(),
            None => vec![req
                .get("handle")
                .and_then(|h| h.as_str())
                .unwrap_or_default()
                .to_string()],
        };
        for handle in handles {
            log.lock().unwrap().push((group, op.clone(), handle));
        }
        // A well-formed reply: a malformed one reads as a dead relay, whose remaining fragments
        // the drain then skips for the round.
        Ok(format!(
            r#"{{"v":{},"resp":{{"ok":true,"msg_id":"m","delete_token":"t"}}}}"#,
            crate::relay_client::RELAY_VERSION
        ))
    })
}

/// A memory transport whose isolated relay dialers record which group carried what.
struct Recording {
    inner: MemoryTransport,
    log: Log,
}

impl Transport for Recording {
    fn address(&self) -> Address {
        self.inner.address()
    }
    fn send(&self, peer: &str, frame: &[u8]) -> Result<()> {
        self.inner.send(peer, frame)
    }
    fn try_recv(&self) -> Option<(Address, Vec<u8>)> {
        self.inner.try_recv()
    }
    fn is_synchronous(&self) -> bool {
        self.inner.is_synchronous()
    }
    fn published(&self) -> bool {
        self.inner.published()
    }
    fn relay_dialer_isolated(&self, _addr: &str, group: u64) -> Option<RelayDialer> {
        Some(recording_dialer(&self.log, Some(group)))
    }
}

/// Alice on a recording transport, paired (and agreed) with each of `names`.
fn recorded(names: &[&str]) -> (Node, Log, Vec<(Node, String)>, MemoryNetwork) {
    let net = MemoryNetwork::new();
    let log: Log = Arc::new(Mutex::new(Vec::new()));
    let mut alice = Node::new(Box::new(Recording {
        inner: net.endpoint("alice"),
        log: Arc::clone(&log),
    }));
    alice.set_relay(RelayClient::with_dialer_for(
        "relay.onion",
        recording_dialer(&log, None),
    ));
    let mut peers = Vec::new();
    for name in names {
        let mut peer = Node::new(Box::new(net.endpoint(name)));
        let bundle = alice.publish_bundle();
        peer.connect_with_bundle("alice", &bundle).unwrap();
        for _ in 0..3 {
            alice.pump().unwrap();
            peer.pump().unwrap();
        }
        let id = peer.identity_key();
        assert!(confirmed(&alice, &id), "{name} agreed with Alice");
        peers.push((peer, id));
    }
    log.lock().unwrap().clear();
    (alice, log, peers, net)
}

#[test]
fn every_poll_rides_its_fragment_and_v1_rides_alone() {
    let (alice, log, peers, _net) = recorded(&["bob", "carol"]);
    crate::node::drain_relay_mailboxes(&alice.relay_drain_plan().unwrap());
    let takes: Vec<_> = log.lock().unwrap().clone();
    assert!(!takes.is_empty());
    assert!(
        takes.iter().all(|(g, _, _)| g.is_some()),
        "no poll uses the shared default circuits"
    );

    let v1 = mailbox_handle(&alice.identity_key());
    let v1_group = takes.iter().find(|(_, _, h)| *h == v1).unwrap().0;
    assert!(
        takes
            .iter()
            .filter(|(g, _, _)| *g == v1_group)
            .all(|(_, _, h)| *h == v1),
        "the static v1 handle shares its circuits with nothing"
    );

    // One pair's handles for neighbouring days never share a fragment.
    let (_, bob_id) = &peers[0];
    let pair = alice.chats[bob_id].mailbox.clone().unwrap();
    let secret = pair_secret(
        &alice.identity_key(),
        bob_id,
        &pair.own,
        &pair.peer.unwrap(),
    );
    let today = current_epoch();
    let groups: Vec<_> = [today - 1, today, today + 1]
        .iter()
        .map(|e| {
            let h = v2_handle(&secret, &alice.identity_key(), *e);
            takes.iter().find(|(_, _, x)| *x == h).expect("polled").0
        })
        .collect();
    assert!(
        groups[0] != groups[1] && groups[1] != groups[2] && groups[0] != groups[2],
        "yesterday, today and tomorrow are in different fragments"
    );
}

#[test]
fn the_partition_is_fixed_for_the_epoch_and_survives_a_restart() {
    let (alice, _log, _peers, net) = recorded(&["bob", "carol", "dave"]);
    let shape = |n: &Node| {
        let mut v: Vec<(u64, Vec<String>)> = n
            .poll_fragments()
            .into_iter()
            .map(|f| {
                let mut h = f.handles;
                h.sort();
                (f.group, h)
            })
            .collect();
        v.sort();
        v
    };
    assert_eq!(shape(&alice), shape(&alice), "the same every round");
    let key = [3u8; 32];
    let restored =
        Node::restore(&alice.export(&key), Box::new(net.endpoint("alice2")), &key).unwrap();
    assert_eq!(
        shape(&restored),
        shape(&alice),
        "a restart must not re-draw it — a fresh partition mid-epoch is the §5c trap"
    );
}

#[test]
fn each_epoch_is_padded_so_one_round_does_not_count_contacts() {
    for names in [&[][..], &["bob"][..], &["bob", "carol", "dave"][..]] {
        let (alice, _log, _peers, _net) = recorded(names);
        let v1 = mailbox_handle(&alice.identity_key());
        let polled: Vec<String> = alice
            .poll_fragments()
            .into_iter()
            .flat_map(|f| f.handles)
            .filter(|h| *h != v1)
            .collect();
        assert_eq!(
            polled.len(),
            3 * POLL_PAD,
            "{} contact(s) poll the same {} v2 handles as nobody",
            names.len(),
            3 * POLL_PAD
        );
        let mut unique = polled.clone();
        unique.sort();
        unique.dedup();
        assert_eq!(unique.len(), polled.len(), "no dummy repeats a real handle");
    }
}

#[test]
fn posts_for_different_recipients_never_share_circuits() {
    let (mut alice, log, peers, net) = recorded(&["bob", "carol"]);
    net.disconnect("bob");
    net.disconnect("carol");
    let (bob, carol) = (&peers[0].1, &peers[1].1);
    alice.send(bob, "one for bob").unwrap();
    alice.send(bob, "another for bob").unwrap();
    alice.send(carol, "one for carol").unwrap();
    let posts: Vec<_> = log
        .lock()
        .unwrap()
        .iter()
        .filter(|(_, op, _)| op.contains("post") || op.contains("Post"))
        .cloned()
        .collect();
    let group_for = |h: &str| -> Vec<Option<u64>> {
        posts
            .iter()
            .filter(|(_, _, x)| x == h)
            .map(|(g, _, _)| *g)
            .collect()
    };
    let to_bob = group_for(&alice.post_handle(bob));
    let to_carol = group_for(&alice.post_handle(carol));
    assert_eq!(to_bob.len(), 2);
    assert_eq!(to_carol.len(), 1);
    assert!(
        to_bob.iter().chain(&to_carol).all(Option::is_some),
        "posts are isolated"
    );
    assert_eq!(
        to_bob[0], to_bob[1],
        "one recipient keeps one set of circuits"
    );
    assert_ne!(to_bob[0], to_carol[0], "two recipients never share");
}

#[test]
fn the_contact_cap_refuses_a_new_contact_and_says_why() {
    let net = MemoryNetwork::new();
    let mut alice = Node::new(Box::new(net.endpoint("alice")));
    let mut peers = Vec::new();
    for i in 0..super::mailbox::MAX_CONTACTS {
        let mut peer = Node::new(Box::new(net.endpoint(&format!("p{i}"))));
        let bundle = peer.publish_bundle();
        alice
            .connect_with_bundle(&format!("p{i}"), &bundle)
            .unwrap();
        peers.push(peer);
    }
    let mut one_more = Node::new(Box::new(net.endpoint("late")));
    let bundle = one_more.publish_bundle();
    let err = alice
        .connect_with_bundle("late", &bundle)
        .unwrap_err()
        .to_string();
    assert!(
        err.contains("50 contacts") && err.contains("relay"),
        "{err}"
    );
    assert!(
        one_more.pump().unwrap().is_empty(),
        "nothing reached the network for the refused contact"
    );
    // Re-pairing someone already in the list is not a new contact.
    let bundle = peers[0].publish_bundle();
    alice
        .connect_with_bundle("p0", &bundle)
        .expect("re-pairing an existing contact at the cap is allowed");
}

#[test]
fn a_dead_relay_costs_two_attempts_per_round_not_one_per_fragment() {
    // A relay that never answers: every dial fails, and each would wait out the full timeout.
    let attempts = Arc::new(Mutex::new(0usize));
    let counter = Arc::clone(&attempts);
    let dead_dialer: RelayDialer = Arc::new(move |_line: &str| {
        *counter.lock().unwrap() += 1;
        anyhow::bail!("relay dial timed out")
    });
    let dead = RelayClient::with_dialer_for("dead.onion", dead_dialer);
    let live = RelayClient::new(RelayServer::spawn("127.0.0.1:0").unwrap().to_string());
    live.post("mbx:live", b"mail", Duration::from_secs(60))
        .unwrap();

    let job = |addr: &str, client: &RelayClient, handle: &str| DrainJob {
        addr: Some(addr.to_string()),
        client: client.clone(),
        handles: vec![handle.to_string()],
    };
    let mut jobs: Vec<DrainJob> = (0..5)
        .map(|i| job("dead.onion", &dead, &format!("mbx:d{i}")))
        .collect();
    jobs.insert(2, job("live.onion", &live, "mbx:live"));
    let harvest = drain_relay_mailboxes(&RelayDrainPlan {
        jobs,
        stagger: false,
    });

    assert_eq!(
        *attempts.lock().unwrap(),
        2,
        "the dead relay was tried twice, not once per fragment"
    );
    assert_eq!(
        harvest.blobs,
        vec![b"mail".to_vec()],
        "the live relay still delivered"
    );
    assert!(harvest
        .reachability
        .contains(&("dead.onion".to_string(), false)));
    assert!(harvest
        .reachability
        .contains(&("live.onion".to_string(), true)));
}

// ---- Stage 3: telling the user their contact is on an older version (§5.4) ----

/// Move the pairing — our contribution's send time and the peer's activity so far — `secs` into
/// the past, standing in for the wait.
fn backdate_announce(node: &mut Node, contact: &str, secs: u64) {
    let chat = node.chats.get_mut(contact).unwrap();
    chat.last_seen = chat.last_seen.map(|t| t - secs);
    let pair = chat.mailbox.as_mut().unwrap();
    pair.announced_at = Some(pair.announced_at.expect("announced") - secs);
}

fn flagged_old(node: &Node, contact: &str) -> bool {
    node.contacts()
        .iter()
        .find(|c| c.id == contact)
        .unwrap()
        .peer_on_old_version
}

#[test]
fn an_old_peer_is_flagged_once_it_is_active_and_still_silent() {
    let mut p = pair(true);
    assert!(
        !flagged_old(&p.alice, &p.bob_id),
        "not while their reply could still be on its way"
    );
    backdate_announce(&mut p.alice, &p.bob_id, OLD_VERSION_GRACE_SECS + 60);
    assert!(
        !flagged_old(&p.alice, &p.bob_id),
        "not on activity from before the grace ran out"
    );
    // Bob is active now, long after Alice's contribution reached him, and never answered it.
    p.bob.send(&p.alice_id, "still here").unwrap();
    p.alice.pump().unwrap();
    assert!(flagged_old(&p.alice, &p.bob_id));

    // It survives a restart: the send time is persisted with the agreement.
    let key = [5u8; 32];
    let saved = p.alice.export(&key);
    let restored = Node::restore(&saved, Box::new(p.net.endpoint("alice2")), &key).unwrap();
    assert!(flagged_old(&restored, &p.bob_id), "after a restart");
}

#[test]
fn a_current_peer_is_never_flagged_even_long_after() {
    let mut p = pair(false);
    backdate_announce(&mut p.alice, &p.bob_id, 24 * 60 * 60);
    p.bob.send(&p.alice_id, "hi").unwrap();
    p.alice.pump().unwrap();
    assert!(!flagged_old(&p.alice, &p.bob_id));
}

#[test]
fn an_offline_peer_is_not_mistaken_for_an_old_one() {
    let mut p = pair(true);
    // A day has passed and Bob has sent nothing since: silence proves nothing about his version.
    backdate_announce(&mut p.alice, &p.bob_id, 24 * 60 * 60);
    assert!(!flagged_old(&p.alice, &p.bob_id));
}

#[test]
fn the_notice_clears_when_the_old_peer_updates() {
    let mut p = pair(true);
    backdate_announce(&mut p.alice, &p.bob_id, OLD_VERSION_GRACE_SECS + 60);
    p.bob.send(&p.alice_id, "old").unwrap();
    p.alice.pump().unwrap();
    assert!(flagged_old(&p.alice, &p.bob_id));

    // Bob updates: his next launch announces his contribution, and the pair agrees.
    p.bob.legacy_v1_only = false;
    p.bob.announce_mailbox();
    for _ in 0..3 {
        p.alice.pump().unwrap();
        p.bob.pump().unwrap();
    }
    assert!(confirmed(&p.alice, &p.bob_id));
    assert!(!flagged_old(&p.alice, &p.bob_id));
}

#[test]
fn a_relay_that_answered_keeps_its_fragments_after_a_cold_miss() {
    // Answers, then fails once (a cold isolated connection that timed out), then answers again.
    let calls = Arc::new(Mutex::new(0usize));
    let counter = Arc::clone(&calls);
    let core = Arc::new(crate::relay_client::RelayCore::new(None));
    let c = Arc::clone(&core);
    let flaky: RelayDialer = Arc::new(move |line: &str| {
        let mut n = counter.lock().unwrap();
        *n += 1;
        if *n == 2 {
            anyhow::bail!("Unable to download hidden service descriptor")
        }
        Ok(c.handle_line(line))
    });
    let relay = RelayClient::with_dialer_for("flaky.onion", flaky);
    let jobs: Vec<DrainJob> = (0..4)
        .map(|i| DrainJob {
            addr: Some("flaky.onion".to_string()),
            client: relay.clone(),
            handles: vec![format!("mbx:f{i}")],
        })
        .collect();
    let harvest = drain_relay_mailboxes(&RelayDrainPlan {
        jobs,
        stagger: false,
    });
    assert_eq!(
        *calls.lock().unwrap(),
        4,
        "one miss on a relay that answered does not abandon its other fragments"
    );
    assert!(harvest
        .reachability
        .contains(&("flaky.onion".to_string(), true)));
}
