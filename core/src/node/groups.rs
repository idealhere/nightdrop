//! Small group chats: client-side fan-out over the existing pairwise sessions.
//!
//! A group is a list of members who each already have an ordinary chat with one another. A group
//! message is encrypted separately on each member's pairwise session and sent to that member in a
//! [`Frame::Group`]; the relay sees ordinary, unrelated messages. There is no group key and no new
//! cryptography. The sender of a group frame is always the owner of the session it decrypted on —
//! a sender named inside the payload would be that member's claim about someone else.
//!
//! Members need a chat with each other, and at first each may only have one with the creator. So
//! the creator **introduces** them: of two members without a chat, the one whose identity key
//! sorts first hands the creator a fresh invite for the other (`intro`), the creator passes it on
//! unopened, and the other connects with it as if they had scanned a code. The creator could pass
//! on a different invite; the receiver checks that the invite's identity is the member named in
//! the group, and comparing safety numbers remains the way to be sure of who that member is.
use super::*;

/// The most members a group may have, the local user included.
pub(crate) const MAX_GROUP_MEMBERS: usize = 10;

#[derive(Clone, Debug)]
pub(crate) struct Group {
    pub id: String,
    pub name: String,
    /// Identity key of the member who created the group.
    pub creator: String,
    /// Identity keys of every member, the local user included; sorted.
    pub members: Vec<String>,
    pub history: Vec<GroupMessage>,
    /// We left: the group is read-only and nothing more is sent to or accepted for it.
    pub left: bool,
}

/// An invite payload longer than this is not an invite.
const MAX_INTRO_PAYLOAD: usize = 4096;

/// Pack a group envelope: `[group_id][op][body…]`. `op` names what the frame does (`create`,
/// `msg`, `leave`, `intro`); a build that does not know an `op` ignores the frame.
pub(super) fn pack_group(group_id: &str, op: &str, body: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    put_field(&mut out, group_id.as_bytes());
    put_field(&mut out, op.as_bytes());
    out.extend_from_slice(body);
    out
}

/// Inverse of [`pack_group`]: `(group_id, op, body)`.
pub(super) fn unpack_group(buf: &[u8]) -> Result<(String, String, Vec<u8>)> {
    let mut p = 0;
    let group_id = String::from_utf8(take_field(buf, &mut p)?)?;
    let op = String::from_utf8(take_field(buf, &mut p)?)?;
    Ok((group_id, op, buf[p..].to_vec()))
}

impl Node {
    /// Tell every open chat that this build understands group frames. Same shape as
    /// [`announce_burns`](Self::announce_burns): once per run per chat, retried until delivered.
    pub fn announce_groups(&mut self) {
        if !self.announce_ready() {
            return;
        }
        let ids: Vec<String> = self
            .chats
            .iter()
            .filter(|(id, c)| !c.closed && !self.groups_announced.contains(id.as_str()))
            .map(|(id, _)| id.clone())
            .collect();
        for id in ids {
            self.announce_groups_to(&id);
        }
    }

    /// Tell one chat that this build understands group frames. Quiet: no history entry.
    pub(super) fn announce_groups_to(&mut self, contact_id: &str) {
        let Some((addr, frame)) =
            self.authed_control(contact_id, MARK_GROUPS_V1, |from, message| Frame::Groups {
                from,
                message,
            })
        else {
            return;
        };
        if self.deliver(&addr, contact_id, &frame).is_ok() {
            self.groups_announced.insert(contact_id.to_string());
        }
    }

    /// Whether this contact's build has announced that it understands group frames.
    pub fn peer_supports_groups(&self, contact_id: &str) -> bool {
        self.groups_peers.contains(contact_id)
    }

    /// Create a group of the local user plus `member_ids`, and tell each member. Every member
    /// must be a live chat of ours whose build understands groups. Returns the new group's id.
    pub fn create_group(&mut self, name: &str, member_ids: &[String]) -> Result<String> {
        if member_ids.is_empty() || member_ids.len() > MAX_GROUP_MEMBERS - 1 {
            anyhow::bail!("a group needs 1 to {} other members", MAX_GROUP_MEMBERS - 1);
        }
        let me = self.identity_key();
        let mut seen = std::collections::HashSet::new();
        for id in member_ids {
            if !seen.insert(id.as_str()) {
                anyhow::bail!("the same member was added twice");
            }
            let chat = self
                .chats
                .get(id)
                .ok_or_else(|| anyhow::anyhow!("unknown contact"))?;
            if !chat.authorized || chat.closed {
                anyhow::bail!("every member must be an open chat of yours");
            }
            if !self.groups_peers.contains(id) {
                anyhow::bail!("a member needs a newer version of the app");
            }
        }
        let name: String = name.chars().take(64).collect();
        let group_id = crate::storage::random_password();
        let mut members: Vec<String> = member_ids.to_vec();
        members.push(me.clone());
        members.sort();
        self.groups.insert(
            group_id.clone(),
            Group {
                id: group_id.clone(),
                name: name.clone(),
                creator: me.clone(),
                members: members.clone(),
                history: vec![GroupMessage {
                    sender: String::new(),
                    message: ChatMessage::system("👥 You created the group.".to_string()),
                }],
                left: false,
            },
        );
        self.dirty = true;

        let mut body = Vec::new();
        put_field(&mut body, name.as_bytes());
        put_field(&mut body, members.join("\n").as_bytes());
        let envelope = pack_group(&group_id, "create", &body);
        self.fan_out(member_ids, &envelope)?;
        Ok(group_id)
    }

    /// Send a text message to a group: one separately encrypted copy per member.
    pub fn send_group(&mut self, group_id: &str, text: &str) -> Result<()> {
        if text.is_empty() {
            anyhow::bail!("message text is empty");
        }
        let me = self.identity_key();
        let msg_id = random_msg_id();
        let recipients: Vec<String> = {
            let group = self
                .groups
                .get_mut(group_id)
                .ok_or_else(|| anyhow::anyhow!("unknown group"))?;
            if group.left {
                anyhow::bail!("you left this group");
            }
            let mut msg = ChatMessage::text(true, text.to_string(), msg_id.clone());
            msg.delivery = "sent".to_string();
            group.history.push(GroupMessage {
                sender: String::new(),
                message: msg,
            });
            group
                .members
                .iter()
                .filter(|m| m.as_str() != me.as_str())
                .cloned()
                .collect()
        };
        self.dirty = true;

        let mut body = Vec::new();
        put_field(&mut body, msg_id.as_bytes());
        body.extend_from_slice(text.as_bytes());
        let envelope = pack_group(group_id, "msg", &body);
        self.fan_out(&recipients, &envelope)
    }

    /// Leave a group: tell the other members (best effort) and keep it locally as read-only.
    pub fn leave_group(&mut self, group_id: &str) -> Result<()> {
        let me = self.identity_key();
        let recipients: Vec<String> = {
            let group = self
                .groups
                .get_mut(group_id)
                .ok_or_else(|| anyhow::anyhow!("unknown group"))?;
            if group.left {
                return Ok(());
            }
            group.left = true;
            group.members.retain(|m| m.as_str() != me.as_str());
            group.history.push(GroupMessage {
                sender: String::new(),
                message: ChatMessage::system("👥 You left the group.".to_string()),
            });
            group.members.clone()
        };
        self.dirty = true;
        let envelope = pack_group(group_id, "leave", b"");
        let _ = self.fan_out(&recipients, &envelope);
        Ok(())
    }

    /// Remove a group from this device, leaving it first if we had not already.
    pub fn delete_group(&mut self, group_id: &str) {
        let _ = self.leave_group(group_id);
        self.groups.remove(group_id);
        self.dirty = true;
    }

    /// Every group as `(id, name, members, creator, left)`, sorted by name then id.
    pub fn groups(&self) -> Vec<(String, String, Vec<String>, String, bool)> {
        let mut out: Vec<(String, String, Vec<String>, String, bool)> = self
            .groups
            .values()
            .map(|g| {
                (
                    g.id.clone(),
                    g.name.clone(),
                    g.members.clone(),
                    g.creator.clone(),
                    g.left,
                )
            })
            .collect();
        out.sort_by(|a, b| a.1.cmp(&b.1).then_with(|| a.0.cmp(&b.0)));
        out
    }

    /// One group's history; empty if there is no such group.
    pub fn group_messages(&self, group_id: &str) -> Vec<GroupMessage> {
        self.groups
            .get(group_id)
            .map(|g| g.history.clone())
            .unwrap_or_default()
    }

    /// Apply a decrypted [`Frame::Group`] envelope that arrived on our session with `from`.
    /// `from` is the only sender this trusts. Anything it does not understand is ignored rather
    /// than refused, so a later build's new `op` costs an older build that one frame.
    pub(super) fn on_group_frame(
        &mut self,
        from: &str,
        plaintext: &[u8],
    ) -> Result<Option<(String, String)>> {
        let (group_id, op, body) = unpack_group(plaintext)?;
        match op.as_str() {
            "create" => {
                if self.groups.contains_key(&group_id) {
                    return Ok(None);
                }
                let mut p = 0;
                let name = String::from_utf8(take_field(&body, &mut p)?)?;
                let listed = String::from_utf8(take_field(&body, &mut p)?)?;
                let mut members: Vec<String> = listed
                    .split('\n')
                    .filter(|s| !s.is_empty())
                    .map(str::to_string)
                    .collect();
                members.sort();
                let unique = members.windows(2).all(|w| w[0] != w[1]);
                let me = self.identity_key();
                if name.chars().count() > 64
                    || !unique
                    || members.len() < 2
                    || members.len() > MAX_GROUP_MEMBERS
                    || !members.iter().any(|m| m.as_str() == from)
                    || !members.iter().any(|m| m.as_str() == me.as_str())
                {
                    return Ok(None);
                }
                self.groups.insert(
                    group_id.clone(),
                    Group {
                        id: group_id.clone(),
                        name,
                        creator: from.to_string(),
                        members,
                        history: vec![GroupMessage {
                            sender: String::new(),
                            message: ChatMessage::system(
                                "👥 You were added to the group.".to_string(),
                            ),
                        }],
                        left: false,
                    },
                );
                self.dirty = true;
                self.offer_introductions(&group_id);
                Ok(Some((from.to_string(), String::new())))
            }
            "intro" => {
                let mut p = 0;
                let named = String::from_utf8(take_field(&body, &mut p)?)?;
                if body.len() - p > MAX_INTRO_PAYLOAD {
                    return Ok(None);
                }
                let payload = String::from_utf8(body[p..].to_vec())?;
                let me = self.identity_key();
                let (we_created, creator) = {
                    let Some(group) = self.groups.get(&group_id) else {
                        return Ok(None);
                    };
                    let is_member = |id: &str| group.members.iter().any(|m| m.as_str() == id);
                    if group.left
                        || !is_member(from)
                        || !is_member(&named)
                        || named.as_str() == from
                        || named.as_str() == me.as_str()
                    {
                        return Ok(None);
                    }
                    (group.creator.as_str() == me.as_str(), group.creator.clone())
                };
                if we_created {
                    // A member's invite for `named`: pass it on unopened, saying whose it is.
                    let mut forward = Vec::new();
                    put_field(&mut forward, from.as_bytes());
                    forward.extend_from_slice(payload.as_bytes());
                    let envelope = pack_group(&group_id, "intro", &forward);
                    let _ = self.send_group_frame(&named, &envelope);
                    return Ok(None);
                }
                // An invite from `named`, passed on to us. Only the creator may pass one on, and
                // it must be an invite to the member it claims to come from.
                if from != creator.as_str() || self.chats.contains_key(&named) {
                    return Ok(None);
                }
                let Ok((_, bundle)) = crate::api::parse_invite(&payload) else {
                    return Ok(None);
                };
                if bundle.identity_key != named {
                    return Ok(None);
                }
                // A failed connection must not fail the frame: the group works without it, only
                // these two members will not see each other's messages.
                if self.connect_from_invite_payload(&payload).is_ok() {
                    self.dirty = true;
                    return Ok(Some((named, String::new())));
                }
                Ok(None)
            }
            "msg" => {
                let mut p = 0;
                let msg_id = String::from_utf8(take_field(&body, &mut p)?)?;
                let text = String::from_utf8(body[p..].to_vec())?;
                let Some(group) = self.groups.get_mut(&group_id) else {
                    return Ok(None);
                };
                if group.left || !group.members.iter().any(|m| m.as_str() == from) {
                    return Ok(None);
                }
                // The same message can arrive twice (a direct copy and a relay copy).
                let duplicate = !msg_id.is_empty()
                    && group
                        .history
                        .iter()
                        .any(|gm| gm.sender.as_str() == from && gm.message.msg_id == msg_id);
                if duplicate {
                    return Ok(None);
                }
                group.history.push(GroupMessage {
                    sender: from.to_string(),
                    message: ChatMessage::text(false, text.clone(), msg_id),
                });
                self.dirty = true;
                Ok(Some((from.to_string(), text)))
            }
            "leave" => {
                let Some(group) = self.groups.get_mut(&group_id) else {
                    return Ok(None);
                };
                if group.left || !group.members.iter().any(|m| m.as_str() == from) {
                    return Ok(None);
                }
                group.members.retain(|m| m.as_str() != from);
                group.history.push(GroupMessage {
                    sender: String::new(),
                    message: ChatMessage::system("👥 A member left the group.".to_string()),
                });
                self.dirty = true;
                Ok(Some((from.to_string(), String::new())))
            }
            _ => Ok(None),
        }
    }

    /// Offer an introduction to every member of `group_id` we have no chat with. Of each such
    /// pair only the member whose identity key sorts first offers, so the two never invite each
    /// other at once. The offer goes to the creator, who has a chat with everyone.
    fn offer_introductions(&mut self, group_id: &str) {
        let me = self.identity_key();
        let (creator, targets): (String, Vec<String>) = {
            let Some(group) = self.groups.get(group_id) else {
                return;
            };
            if group.left || group.creator.as_str() == me.as_str() {
                return;
            }
            let targets = group
                .members
                .iter()
                .filter(|m| {
                    m.as_str() != group.creator.as_str()
                        && me.as_str() < m.as_str()
                        && !self.chats.contains_key(m.as_str())
                })
                .cloned()
                .collect();
            (group.creator.clone(), targets)
        };
        for target in targets {
            let payload = self.build_pair_payload();
            let mut body = Vec::new();
            put_field(&mut body, target.as_bytes());
            body.extend_from_slice(payload.as_bytes());
            let envelope = pack_group(group_id, "intro", &body);
            if self.send_group_frame(&creator, &envelope).is_ok() {
                self.intro_expected.insert(target);
            }
        }
    }

    /// Send one envelope to each of `members` on their own session. A member we no longer have a
    /// live chat with is skipped, and one failed send does not stop the rest; the last error is
    /// returned only if no copy went out at all.
    fn fan_out(&mut self, members: &[String], envelope: &[u8]) -> Result<()> {
        let mut sent = 0usize;
        let mut last_err: Option<anyhow::Error> = None;
        for member in members {
            match self.send_group_frame(member, envelope) {
                Ok(()) => sent += 1,
                Err(e) => last_err = Some(e),
            }
        }
        match last_err {
            Some(e) if sent == 0 => Err(e),
            _ => Ok(()),
        }
    }

    /// Encrypt a group envelope on `member`'s pairwise session and deliver it, the way
    /// [`unsend_message`](Self::unsend_message) delivers its frame.
    fn send_group_frame(&mut self, member: &str, envelope: &[u8]) -> Result<()> {
        let from = self.identity_key();
        let (peer_address, frame) = {
            let chat = self
                .chats
                .get_mut(member)
                .ok_or_else(|| anyhow::anyhow!("unknown contact"))?;
            if !chat.authorized || chat.closed {
                anyhow::bail!("no open chat with this member");
            }
            let message = crypto::encrypt(&mut chat.session, envelope);
            let frame = Frame::Group {
                from,
                message: WireOlm::from_olm(&message),
            };
            (chat.peer_address.clone(), frame)
        };
        self.deliver(&peer_address, member, &frame)
    }
}
