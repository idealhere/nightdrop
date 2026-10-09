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
        let (id, name, members, creator, left, _timer) = groups[0].clone();
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

/// Alice knows Bob and Carol; Bob and Carol have never met.
fn creator_and_two_strangers() -> (Node, Node, Node) {
    let net = MemoryNetwork::new();
    let mut alice = Node::new(Box::new(net.endpoint("alice")));
    let mut bob = Node::new(Box::new(net.endpoint("bob")));
    let mut carol = Node::new(Box::new(net.endpoint("carol")));
    pair(&mut alice, "alice", &mut bob);
    pair(&mut alice, "alice", &mut carol);
    (alice, bob, carol)
}

fn settle(nodes: &mut [&mut Node]) {
    for _ in 0..4 {
        pump_all(nodes);
    }
}

/// A group that exists only on `node`, as if `creator` had made it.
fn plant_group(node: &mut Node, id: &str, creator: &str, members: &[String]) {
    let mut members = members.to_vec();
    members.sort();
    node.groups.insert(
        id.to_string(),
        super::groups::Group {
            id: id.to_string(),
            name: id.to_string(),
            creator: creator.to_string(),
            members,
            history: Vec::new(),
            left: false,
            disappearing_secs: 0,
            acks: HashMap::new(),
        },
    );
}

fn intro_envelope(group_id: &str, named: &str, payload: &str) -> Vec<u8> {
    let mut body = Vec::new();
    put_field(&mut body, named.as_bytes());
    body.extend_from_slice(payload.as_bytes());
    pack_group(group_id, "intro", &body)
}

#[test]
fn members_who_only_know_the_creator_are_introduced() {
    let (mut alice, mut bob, mut carol) = creator_and_two_strangers();
    let gid = alice
        .create_group("intro", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol]);

    assert!(bob.contacts().iter().any(|c| c.id == carol.identity_key()));
    assert!(carol.contacts().iter().any(|c| c.id == bob.identity_key()));

    bob.send_group(&gid, "hi from bob").unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol]);
    let last = carol.group_messages(&gid).into_iter().last().unwrap();
    assert_eq!(last.sender, bob.identity_key());
    assert_eq!(last.message.text, "hi from bob");

    carol.send_group(&gid, "hi from carol").unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol]);
    let last = bob.group_messages(&gid).into_iter().last().unwrap();
    assert_eq!(last.sender, carol.identity_key());
    assert_eq!(last.message.text, "hi from carol");
}

#[test]
fn introduced_members_do_not_need_approval() {
    let (mut alice, mut bob, mut carol) = creator_and_two_strangers();
    bob.set_require_authorization(true);
    carol.set_require_authorization(true);
    let gid = alice
        .create_group("no-ask", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol]);

    assert!(bob.chats.get(&carol.identity_key()).unwrap().authorized);
    assert!(carol.chats.get(&bob.identity_key()).unwrap().authorized);

    bob.send_group(&gid, "no approval needed").unwrap();
    carol.send_group(&gid, "none here either").unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol]);
    assert!(carol
        .group_messages(&gid)
        .iter()
        .any(|m| m.message.text == "no approval needed"));
    assert!(bob
        .group_messages(&gid)
        .iter()
        .any(|m| m.message.text == "none here either"));
}

#[test]
fn an_introduction_to_a_different_identity_is_refused() {
    let net = MemoryNetwork::new();
    let mut alice = Node::new(Box::new(net.endpoint("alice")));
    let mut bob = Node::new(Box::new(net.endpoint("bob")));
    let carol = Node::new(Box::new(net.endpoint("carol")));
    let mut dave = Node::new(Box::new(net.endpoint("dave")));
    pair(&mut alice, "alice", &mut bob);
    let members = [
        alice.identity_key(),
        bob.identity_key(),
        carol.identity_key(),
    ];
    plant_group(&mut bob, "g", &alice.identity_key(), &members);

    // The creator names Carol but passes on an invite that leads to Dave.
    let envelope = intro_envelope("g", &carol.identity_key(), &dave.build_pair_payload());
    assert_eq!(
        bob.on_group_frame(&alice.identity_key(), &envelope)
            .unwrap(),
        None
    );
    assert!(!bob.chats.contains_key(&carol.identity_key()));
    assert!(!bob.chats.contains_key(&dave.identity_key()));
}

#[test]
fn only_the_creator_can_pass_an_introduction_on() {
    let net = MemoryNetwork::new();
    let mut alice = Node::new(Box::new(net.endpoint("alice")));
    let mut bob = Node::new(Box::new(net.endpoint("bob")));
    let mut carol = Node::new(Box::new(net.endpoint("carol")));
    let mut dave = Node::new(Box::new(net.endpoint("dave")));
    pair(&mut alice, "alice", &mut bob);
    pair(&mut bob, "bob", &mut carol);
    let members = [
        alice.identity_key(),
        bob.identity_key(),
        carol.identity_key(),
        dave.identity_key(),
    ];
    plant_group(&mut bob, "g", &alice.identity_key(), &members);

    // Carol is a member, but not the creator: her passing on Dave's invite counts for nothing.
    let envelope = intro_envelope("g", &dave.identity_key(), &dave.build_pair_payload());
    assert_eq!(
        bob.on_group_frame(&carol.identity_key(), &envelope)
            .unwrap(),
        None
    );
    assert!(!bob.chats.contains_key(&dave.identity_key()));
}

/// Give each node a media store of its own; returns the directories, in the same order.
fn media_stores(test: &str, nodes: &mut [&mut Node]) -> Vec<String> {
    let key: StoreKey = [9u8; 32];
    let base = std::env::temp_dir().join(format!("nightdrop-grp-{test}-{}", std::process::id()));
    let mut dirs = Vec::new();
    for (i, node) in nodes.iter_mut().enumerate() {
        let dir = format!("{}-{i}", base.display());
        node.set_media_store(dir.clone(), key);
        dirs.push(dir);
    }
    dirs
}

fn remove_stores(dirs: &[String]) {
    for dir in dirs {
        std::fs::remove_dir_all(dir).ok();
    }
}

fn last_of(node: &Node, group_id: &str) -> ChatMessage {
    node.group_messages(group_id)
        .into_iter()
        .last()
        .unwrap()
        .message
}

fn sealed(dir: &str, media_id: &str) -> bool {
    std::path::Path::new(&format!("{dir}/{media_id}.bin")).exists()
}

#[test]
fn a_group_photo_reaches_every_member() {
    let (mut alice, mut bob, mut carol) = trio();
    let dirs = media_stores("photo", &mut [&mut alice, &mut bob, &mut carol]);
    let gid = alice
        .create_group("photo", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    alice
        .send_group_media(&gid, &[1, 2, 3, 4], "image/png", "image")
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    for node in [&bob, &carol] {
        let last = node.group_messages(&gid).into_iter().last().unwrap();
        assert_eq!(last.sender, alice.identity_key());
        assert_eq!(last.message.kind, "image");
        assert_eq!(
            node.media_bytes(&last.message.media_id).unwrap(),
            vec![1u8, 2, 3, 4]
        );
    }
    remove_stores(&dirs);
}

#[test]
fn a_group_photo_arriving_twice_is_stored_once() {
    let (mut alice, mut bob, mut carol) = trio();
    let dirs = media_stores("twice", &mut [&mut alice, &mut bob, &mut carol]);
    let gid = alice
        .create_group("twice", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    let before = bob.group_messages(&gid).len();

    let copy = pack_group(
        &gid,
        "media",
        &pack_media("transfer-1", "image", "image/png", &[1, 2, 3]),
    );
    assert!(bob
        .on_group_frame(&alice.identity_key(), &copy)
        .unwrap()
        .is_some());
    assert_eq!(
        bob.on_group_frame(&alice.identity_key(), &copy).unwrap(),
        None
    );
    assert_eq!(bob.group_messages(&gid).len(), before + 1);
    remove_stores(&dirs);
}

#[test]
fn unsending_a_group_message_removes_it_for_everyone() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("unsend", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    alice.send_group(&gid, "delete me").unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    assert_eq!(last_of(&bob, &gid).text, "delete me");

    let msg_id = last_of(&alice, &gid).msg_id;
    alice.unsend_group_message(&gid, &msg_id).unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    for node in [&alice, &bob, &carol] {
        let last = last_of(node, &gid);
        assert_eq!(last.kind, "deleted");
        assert_eq!(last.text, "");
    }
}

#[test]
fn unsending_a_group_photo_deletes_the_files_everywhere() {
    let (mut alice, mut bob, mut carol) = trio();
    let dirs = media_stores("unsend-photo", &mut [&mut alice, &mut bob, &mut carol]);
    let gid = alice
        .create_group("unsend-photo", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    alice
        .send_group_media(&gid, &[5, 6, 7], "image/jpeg", "image")
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    let media_ids = [
        last_of(&alice, &gid).media_id,
        last_of(&bob, &gid).media_id,
        last_of(&carol, &gid).media_id,
    ];
    for (dir, media_id) in dirs.iter().zip(&media_ids) {
        assert!(sealed(dir, media_id));
    }

    let transfer_id = last_of(&alice, &gid).transfer_id;
    alice.unsend_group_message(&gid, &transfer_id).unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    for node in [&alice, &bob, &carol] {
        let last = last_of(node, &gid);
        assert_eq!(last.kind, "deleted");
        assert!(last.media_id.is_empty());
    }
    for (dir, media_id) in dirs.iter().zip(&media_ids) {
        assert!(!sealed(dir, media_id), "the sealed file is gone");
    }

    // A late second copy of the photo must not bring it back.
    let before = bob.group_messages(&gid).len();
    let late = pack_group(
        &gid,
        "media",
        &pack_media(&transfer_id, "image", "image/jpeg", &[5, 6, 7]),
    );
    assert_eq!(
        bob.on_group_frame(&alice.identity_key(), &late).unwrap(),
        None
    );
    assert_eq!(bob.group_messages(&gid).len(), before);
    remove_stores(&dirs);
}

#[test]
fn a_member_cannot_unsend_someone_elses_message() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("not-yours", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    alice.send_group(&gid, "not yours").unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    // Carol names Alice's message; on Bob it arrives as Carol's request.
    let msg_id = last_of(&alice, &gid).msg_id;
    let envelope = pack_group(&gid, "unsend", msg_id.as_bytes());
    assert_eq!(
        bob.on_group_frame(&carol.identity_key(), &envelope)
            .unwrap(),
        None
    );
    assert_eq!(last_of(&bob, &gid).text, "not yours");
    // …and Carol's own app refuses to send it in the first place.
    assert!(carol.unsend_group_message(&gid, &msg_id).is_err());
}

#[test]
fn a_voice_message_reaches_the_group_and_can_be_unsent() {
    let (mut alice, mut bob, mut carol) = trio();
    let dirs = media_stores("voice", &mut [&mut alice, &mut bob, &mut carol]);
    let gid = alice
        .create_group("voice", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    alice
        .send_group_media(&gid, &[9, 8, 7], "audio/mp4", "audio")
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    let got = last_of(&bob, &gid);
    assert_eq!(got.kind, "audio");
    assert_eq!(bob.media_bytes(&got.media_id).unwrap(), vec![9u8, 8, 7]);

    let transfer_id = last_of(&alice, &gid).transfer_id;
    alice.unsend_group_message(&gid, &transfer_id).unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    assert_eq!(last_of(&carol, &gid).kind, "deleted");
    assert!(!sealed(&dirs[1], &got.media_id));

    // Anything that is not a photo, a video or a voice message is refused.
    assert!(alice
        .send_group_media(&gid, &[1], "application/pdf", "file")
        .is_err());
    remove_stores(&dirs);
}

#[test]
fn a_group_timer_is_shared_and_noted() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("timer", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    alice.set_group_disappearing(&gid, 3600).unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    for node in [&alice, &bob, &carol] {
        assert_eq!(node.groups()[0].5, 3600);
        let last = last_of(node, &gid);
        assert!(last.system);
        assert!(last.text.contains("disappearing messages to 1 hour"));
    }
}

#[test]
fn group_messages_expire_with_the_timer() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("expire", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    alice.set_group_disappearing(&gid, 60).unwrap();
    alice.send_group(&gid, "old").unwrap();
    alice.send_group(&gid, "fresh").unwrap();

    // Two minutes pass for the first message only.
    let group = alice.groups.get_mut(&gid).unwrap();
    let old = group
        .history
        .iter_mut()
        .find(|gm| gm.message.text == "old")
        .unwrap();
    old.message.at = crate::api::now_secs() - 120;
    alice.sweep_time();

    let texts: Vec<String> = alice
        .group_messages(&gid)
        .into_iter()
        .map(|gm| gm.message.text)
        .collect();
    assert!(!texts.iter().any(|t| t == "old"));
    assert!(texts.iter().any(|t| t == "fresh"));
}

#[test]
fn the_creator_can_add_a_member_who_then_gets_messages() {
    let net = MemoryNetwork::new();
    let mut alice = Node::new(Box::new(net.endpoint("alice")));
    let mut bob = Node::new(Box::new(net.endpoint("bob")));
    let mut carol = Node::new(Box::new(net.endpoint("carol")));
    let mut dave = Node::new(Box::new(net.endpoint("dave")));
    pair(&mut alice, "alice", &mut bob);
    pair(&mut alice, "alice", &mut carol);
    pair(&mut alice, "alice", &mut dave);
    let gid = alice
        .create_group("grow", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol, &mut dave]);
    alice.set_group_disappearing(&gid, 3600).unwrap();

    alice
        .add_group_members(&gid, &[dave.identity_key()])
        .unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol, &mut dave]);

    for node in [&alice, &bob, &carol, &dave] {
        assert_eq!(node.groups()[0].2.len(), 4);
    }
    assert_eq!(dave.groups()[0].5, 3600, "the newcomer gets the timer too");

    // Dave knew only Alice; the others were introduced to him.
    dave.send_group(&gid, "dave here").unwrap();
    bob.send_group(&gid, "hello dave").unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol, &mut dave]);
    assert!(bob
        .group_messages(&gid)
        .iter()
        .any(|gm| gm.sender == dave.identity_key() && gm.message.text == "dave here"));
    assert!(dave
        .group_messages(&gid)
        .iter()
        .any(|gm| gm.sender == bob.identity_key() && gm.message.text == "hello dave"));
}

#[test]
fn only_the_creator_can_change_members() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("roles", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    assert!(bob
        .remove_group_member(&gid, &carol.identity_key())
        .is_err());
    assert!(bob
        .add_group_members(&gid, &[carol.identity_key()])
        .is_err());

    // A member list that arrives from someone other than the creator changes nothing.
    let before = carol.groups()[0].2.clone();
    let without_alice = [bob.identity_key(), carol.identity_key()].join("\n");
    let envelope = pack_group(&gid, "members", without_alice.as_bytes());
    assert_eq!(
        carol
            .on_group_frame(&bob.identity_key(), &envelope)
            .unwrap(),
        None
    );
    assert_eq!(carol.groups()[0].2, before);
}

#[test]
fn a_removed_member_is_out_and_can_be_added_back() {
    let (mut alice, mut bob, mut carol) = trio();
    let gid = alice
        .create_group("remove", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    alice
        .remove_group_member(&gid, &bob.identity_key())
        .unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol]);
    assert_eq!(alice.groups()[0].2.len(), 2);
    assert_eq!(carol.groups()[0].2.len(), 2);
    assert!(bob.groups()[0].4, "Bob's copy is read-only");
    assert!(bob.send_group(&gid, "still here?").is_err());

    // What Bob might still send is refused by the others.
    let before = carol.group_messages(&gid).len();
    let late = msg_envelope(&gid, "late-id", "still here?");
    assert_eq!(
        carol.on_group_frame(&bob.identity_key(), &late).unwrap(),
        None
    );
    assert_eq!(carol.group_messages(&gid).len(), before);

    alice
        .add_group_members(&gid, &[bob.identity_key()])
        .unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol]);
    assert!(!bob.groups()[0].4);
    assert_eq!(bob.groups()[0].2.len(), 3);
    alice.send_group(&gid, "welcome back").unwrap();
    settle(&mut [&mut alice, &mut bob, &mut carol]);
    assert_eq!(last_of(&bob, &gid).text, "welcome back");
}

#[test]
fn a_group_message_is_delivered_once_every_member_has_it() {
    let (mut alice, mut bob, mut carol) = trio();
    let dirs = media_stores("acks", &mut [&mut alice, &mut bob, &mut carol]);
    let gid = alice
        .create_group("acks", &[bob.identity_key(), carol.identity_key()])
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);

    alice.send_group(&gid, "status?").unwrap();
    assert_eq!(last_of(&alice, &gid).delivery, "sent");

    // Bob has it; Carol has not looked yet.
    for _ in 0..2 {
        bob.pump().unwrap();
        alice.pump().unwrap();
    }
    assert_eq!(
        last_of(&alice, &gid).delivery,
        "sent",
        "one of two is not everyone"
    );

    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    assert_eq!(last_of(&alice, &gid).delivery, "delivered");
    assert!(alice.groups.get(&gid).unwrap().acks.is_empty());

    // A photo is acknowledged by its transfer id.
    alice
        .send_group_media(&gid, &[1, 2, 3], "image/png", "image")
        .unwrap();
    pump_all(&mut [&mut alice, &mut bob, &mut carol]);
    assert_eq!(last_of(&alice, &gid).delivery, "delivered");

    // Nobody can acknowledge on a member's behalf from outside the group.
    alice.send_group(&gid, "again").unwrap();
    let id = last_of(&alice, &gid).msg_id;
    let forged = pack_group(&gid, "ack", id.as_bytes());
    assert_eq!(alice.on_group_frame("a stranger", &forged).unwrap(), None);
    assert_eq!(last_of(&alice, &gid).delivery, "sent");
    remove_stores(&dirs);
}
