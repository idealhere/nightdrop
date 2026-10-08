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
    /// We left, or the creator removed us: the group is read-only and nothing more is sent to
    /// or accepted for it.
    pub left: bool,
    /// The group's disappearing-messages timer in seconds; 0 = off. Any member may set it.
    pub disappearing_secs: u64,
}

/// A system notice as a group history entry.
fn notice(text: &str) -> GroupMessage {
    GroupMessage {
        sender: String::new(),
        message: ChatMessage::system(text.to_string()),
    }
}

/// Parse a member list as it travels in `create` and `members`: identity keys, one per line.
/// `None` unless it is sorted without repeats, within the size limit, and includes `creator`.
fn parse_members(listed: &str, creator: &str) -> Option<Vec<String>> {
    let mut members: Vec<String> = listed
        .split('\n')
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect();
    members.sort();
    let unique = members.windows(2).all(|w| w[0] != w[1]);
    let ok = unique
        && members.len() <= MAX_GROUP_MEMBERS
        && members.iter().any(|m| m.as_str() == creator);
    ok.then_some(members)
}

/// An invite payload longer than this is not an invite.
const MAX_INTRO_PAYLOAD: usize = 4096;

/// Pack a group envelope: `[group_id][op][body…]`. `op` names what the frame does (`create`,
/// `msg`, `media`, `unsend`, `timer`, `members`, `leave`, `intro`); a build that does not know
/// an `op` ignores the frame.
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

/// The attachment kinds a group carries: photos, videos and voice messages.
fn is_group_attachment(kind: &str) -> bool {
    matches!(kind, "image" | "video" | "audio")
}

/// Whether `id` names this message for an unsend: a text message by its `msg_id`, a photo or
/// video by its `transfer_id`. Notices and tombstones are named by nothing.
fn names_message(msg: &ChatMessage, id: &str) -> bool {
    !msg.system
        && ((msg.kind == "text" && !msg.msg_id.is_empty() && msg.msg_id == id)
            || is_attachment_named(msg, id))
}

/// Turn a message into a "deleted" tombstone in place; returns the ids of the sealed files an
/// attachment leaves behind, for the caller to delete.
fn tombstone(msg: &mut ChatMessage) -> Vec<String> {
    if msg.kind == "text" {
        make_tombstone(msg);
        Vec::new()
    } else {
        make_attachment_tombstone(msg)
    }
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
                disappearing_secs: 0,
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

    /// Send a photo or video to a group: one separately encrypted copy per member, and a sealed
    /// copy kept here. The body is the ordinary attachment envelope (`pack_media`).
    pub fn send_group_media(
        &mut self,
        group_id: &str,
        data: &[u8],
        mime: &str,
        kind: &str,
    ) -> Result<()> {
        if data.is_empty() {
            anyhow::bail!("attachment is empty");
        }
        if data.len() as u64 > MAX_MEDIA_BYTES {
            anyhow::bail!(
                "attachment too large (max {} MB)",
                MAX_MEDIA_BYTES / (1024 * 1024)
            );
        }
        if !is_group_attachment(kind) {
            anyhow::bail!("this kind of attachment cannot be sent to a group");
        }
        if self.groups.get(group_id).is_none_or(|g| g.left) {
            anyhow::bail!("unknown group, or you left it");
        }
        let me = self.identity_key();
        let transfer_id = crate::storage::random_password();
        let media_id = self.store_media(data)?;
        let recipients: Vec<String> = {
            let group = self
                .groups
                .get_mut(group_id)
                .ok_or_else(|| anyhow::anyhow!("unknown group"))?;
            let mut message = ChatMessage::media(
                true,
                kind.to_string(),
                mime.to_string(),
                media_id,
                data.len() as u64,
                transfer_id.clone(),
                String::new(),
            );
            message.delivery = "sent".to_string();
            group.history.push(GroupMessage {
                sender: String::new(),
                message,
            });
            group
                .members
                .iter()
                .filter(|m| m.as_str() != me.as_str())
                .cloned()
                .collect()
        };
        self.dirty = true;
        let envelope = pack_group(
            group_id,
            "media",
            &pack_media(&transfer_id, kind, mime, data),
        );
        self.fan_out(&recipients, &envelope)
    }

    /// Unsend ("delete for everyone") one of our own group messages, under the same 15-minute
    /// rule as a 1:1 chat. Text is named by its `msg_id`, a photo or video by its `transfer_id`;
    /// an attachment's sealed files are deleted on every member's device.
    pub fn unsend_group_message(&mut self, group_id: &str, id: &str) -> Result<()> {
        let me = self.identity_key();
        let now = crate::api::now_secs();
        let recipients: Vec<String> = {
            let group = self
                .groups
                .get_mut(group_id)
                .ok_or_else(|| anyhow::anyhow!("unknown group"))?;
            if group.left {
                anyhow::bail!("you left this group");
            }
            let index = group
                .history
                .iter()
                .position(|gm| gm.message.from_me && names_message(&gm.message, id))
                .ok_or_else(|| anyhow::anyhow!("message not found or not deletable"))?;
            let at = group.history[index].message.at;
            if at == 0 || now.saturating_sub(at) > EDIT_WINDOW.as_secs() {
                anyhow::bail!("messages can only be unsent within 15 minutes of sending");
            }
            let dead_files = tombstone(&mut group.history[index].message);
            if let Some((dir, _)) = &self.media_store {
                remove_attachment_files(dir, &dead_files);
            }
            group
                .members
                .iter()
                .filter(|m| m.as_str() != me.as_str())
                .cloned()
                .collect()
        };
        self.dirty = true;
        // Already deleted here; a member we could not reach keeps their copy.
        let _ = self.fan_out(&recipients, &pack_group(group_id, "unsend", id.as_bytes()));
        Ok(())
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

    /// The other members of a group we are an active member of, plus the group's name, member
    /// list and timer; an error if there is no such group or we left it. With `as_creator`, also
    /// an error unless we created it.
    fn group_snapshot(
        &self,
        group_id: &str,
        as_creator: bool,
    ) -> Result<(Vec<String>, String, Vec<String>, u64)> {
        let me = self.identity_key();
        let group = self
            .groups
            .get(group_id)
            .ok_or_else(|| anyhow::anyhow!("unknown group"))?;
        if group.left {
            anyhow::bail!("you left this group");
        }
        if as_creator && group.creator != me {
            anyhow::bail!("only the person who created the group can change its members");
        }
        let others = group
            .members
            .iter()
            .filter(|m| m.as_str() != me.as_str())
            .cloned()
            .collect();
        Ok((
            others,
            group.name.clone(),
            group.members.clone(),
            group.disappearing_secs,
        ))
    }

    /// Set the group's disappearing-messages timer (0 = off) and tell the other members. Any
    /// member may; messages older than the timer are then dropped on every device.
    pub fn set_group_disappearing(&mut self, group_id: &str, secs: u64) -> Result<()> {
        let (others, ..) = self.group_snapshot(group_id, false)?;
        if let Some(group) = self.groups.get_mut(group_id) {
            group.disappearing_secs = secs;
            group.history.push(notice(&format!(
                "⏱️ You set disappearing messages to {}.",
                disappearing_label(secs)
            )));
        }
        self.dirty = true;
        let _ = self.fan_out(
            &others,
            &pack_group(group_id, "timer", secs.to_string().as_bytes()),
        );
        Ok(())
    }

    /// Add contacts to a group we created. They receive the group as if it had just been made;
    /// the members already in it receive the new member list.
    pub fn add_group_members(&mut self, group_id: &str, member_ids: &[String]) -> Result<()> {
        let (others, name, old_members, timer) = self.group_snapshot(group_id, true)?;
        if member_ids.is_empty() {
            anyhow::bail!("nobody to add");
        }
        if old_members.len() + member_ids.len() > MAX_GROUP_MEMBERS {
            anyhow::bail!("a group can have at most {MAX_GROUP_MEMBERS} members");
        }
        let mut members = old_members;
        for id in member_ids {
            if members.contains(id) {
                anyhow::bail!("already a member, or added twice");
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
            members.push(id.clone());
        }
        members.sort();
        let listed = members.join("\n");
        if let Some(group) = self.groups.get_mut(group_id) {
            group.members = members;
            group
                .history
                .push(notice("👥 You added a member to the group."));
        }
        self.dirty = true;

        let _ = self.fan_out(&others, &pack_group(group_id, "members", listed.as_bytes()));
        let mut body = Vec::new();
        put_field(&mut body, name.as_bytes());
        put_field(&mut body, listed.as_bytes());
        self.fan_out(member_ids, &pack_group(group_id, "create", &body))?;
        if timer > 0 {
            let _ = self.fan_out(
                member_ids,
                &pack_group(group_id, "timer", timer.to_string().as_bytes()),
            );
        }
        Ok(())
    }

    /// Remove a member from a group we created. Everyone, the removed member included, receives
    /// the new member list; the removed member's copy becomes read-only.
    pub fn remove_group_member(&mut self, group_id: &str, member_id: &str) -> Result<()> {
        let (others, _, old_members, _) = self.group_snapshot(group_id, true)?;
        if member_id == self.identity_key() {
            anyhow::bail!("to go yourself, leave the group");
        }
        if !old_members.iter().any(|m| m.as_str() == member_id) {
            anyhow::bail!("not a member of this group");
        }
        let members: Vec<String> = old_members
            .into_iter()
            .filter(|m| m.as_str() != member_id)
            .collect();
        let listed = members.join("\n");
        if let Some(group) = self.groups.get_mut(group_id) {
            group.members = members;
            group
                .history
                .push(notice("👥 You removed a member from the group."));
        }
        self.dirty = true;
        // `others` still includes the removed member: they are told too.
        let _ = self.fan_out(&others, &pack_group(group_id, "members", listed.as_bytes()));
        Ok(())
    }

    /// Remove a group from this device, leaving it first if we had not already.
    pub fn delete_group(&mut self, group_id: &str) {
        let _ = self.leave_group(group_id);
        self.groups.remove(group_id);
        self.dirty = true;
    }

    /// Every group as `(id, name, members, creator, left, disappearing_secs)`, sorted by name
    /// then id.
    pub fn groups(&self) -> Vec<(String, String, Vec<String>, String, bool, u64)> {
        let mut out: Vec<(String, String, Vec<String>, String, bool, u64)> = self
            .groups
            .values()
            .map(|g| {
                (
                    g.id.clone(),
                    g.name.clone(),
                    g.members.clone(),
                    g.creator.clone(),
                    g.left,
                    g.disappearing_secs,
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
                let mut p = 0;
                let name = String::from_utf8(take_field(&body, &mut p)?)?;
                let listed = String::from_utf8(take_field(&body, &mut p)?)?;
                let me = self.identity_key();
                let Some(members) = parse_members(&listed, from) else {
                    return Ok(None);
                };
                if name.chars().count() > 64
                    || members.len() < 2
                    || !members.iter().any(|m| m.as_str() == me.as_str())
                {
                    return Ok(None);
                }
                if let Some(group) = self.groups.get_mut(&group_id) {
                    // A group we already have: only its creator adding us back after we left or
                    // were removed. The history we kept stays; the timer comes again if it is on.
                    if !group.left || group.creator.as_str() != from {
                        return Ok(None);
                    }
                    group.left = false;
                    group.name = name;
                    group.members = members;
                    group.disappearing_secs = 0;
                    group
                        .history
                        .push(notice("👥 You were added to the group."));
                } else {
                    self.groups.insert(
                        group_id.clone(),
                        Group {
                            id: group_id.clone(),
                            name,
                            creator: from.to_string(),
                            members,
                            history: vec![notice("👥 You were added to the group.")],
                            left: false,
                            disappearing_secs: 0,
                        },
                    );
                }
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
            "media" => {
                let (transfer_id, kind, mime, data) = unpack_media(&body)?;
                // Decided before the payload is stored: storing first would strand a sealed file.
                // A copy of something already here — or since unsent, whose tombstone keeps its
                // transfer id — is dropped.
                let wanted = self.groups.get(&group_id).is_some_and(|group| {
                    !group.left
                        && group.members.iter().any(|m| m.as_str() == from)
                        && is_group_attachment(&kind)
                        && !transfer_id.is_empty()
                        && !group.history.iter().any(|gm| {
                            gm.sender.as_str() == from && gm.message.transfer_id == transfer_id
                        })
                });
                if !wanted {
                    return Ok(None);
                }
                let media_id = self.store_media(&data)?;
                let Some(group) = self.groups.get_mut(&group_id) else {
                    return Ok(None);
                };
                group.history.push(GroupMessage {
                    sender: from.to_string(),
                    message: ChatMessage::media(
                        false,
                        kind,
                        mime,
                        media_id,
                        data.len() as u64,
                        transfer_id,
                        String::new(),
                    ),
                });
                self.dirty = true;
                Ok(Some((from.to_string(), String::new())))
            }
            "unsend" => {
                let target = unpack_unsend(&body)?;
                let now = crate::api::now_secs();
                let Some(group) = self.groups.get_mut(&group_id) else {
                    return Ok(None);
                };
                if group.left || !group.members.iter().any(|m| m.as_str() == from) {
                    return Ok(None);
                }
                // `sender == from`: a member can delete only what they sent themselves.
                let Some(gm) = group.history.iter_mut().find(|gm| {
                    gm.sender.as_str() == from
                        && !gm.message.from_me
                        && names_message(&gm.message, &target)
                        && gm.message.at != 0
                        && now.saturating_sub(gm.message.at) <= EDIT_WINDOW.as_secs()
                }) else {
                    return Ok(None);
                };
                let dead_files = tombstone(&mut gm.message);
                if let Some((dir, _)) = &self.media_store {
                    remove_attachment_files(dir, &dead_files);
                }
                self.dirty = true;
                Ok(Some((from.to_string(), String::new())))
            }
            "timer" => {
                let Ok(secs) = String::from_utf8_lossy(&body).parse::<u64>() else {
                    return Ok(None);
                };
                let Some(group) = self.groups.get_mut(&group_id) else {
                    return Ok(None);
                };
                if group.left
                    || !group.members.iter().any(|m| m.as_str() == from)
                    || group.disappearing_secs == secs
                {
                    return Ok(None);
                }
                group.disappearing_secs = secs;
                group.history.push(notice(&format!(
                    "⏱️ A member set disappearing messages to {}.",
                    disappearing_label(secs)
                )));
                self.dirty = true;
                Ok(Some((from.to_string(), String::new())))
            }
            "members" => {
                // The whole new member list, from the creator — the only one who may change it.
                let me = self.identity_key();
                let still_in = {
                    let Some(group) = self.groups.get_mut(&group_id) else {
                        return Ok(None);
                    };
                    if group.left || group.creator.as_str() != from {
                        return Ok(None);
                    }
                    let Some(members) = parse_members(&String::from_utf8_lossy(&body), from) else {
                        return Ok(None);
                    };
                    if members == group.members {
                        return Ok(None);
                    }
                    let still_in = members.iter().any(|m| m.as_str() == me.as_str());
                    let added = members.iter().any(|m| !group.members.contains(m));
                    group.history.push(notice(if !still_in {
                        "👥 You were removed from the group."
                    } else if added {
                        "👥 A member was added to the group."
                    } else {
                        "👥 A member was removed from the group."
                    }));
                    group.left = !still_in;
                    group.members = members;
                    still_in
                };
                self.dirty = true;
                if still_in {
                    // Someone new may be a stranger to us.
                    self.offer_introductions(&group_id);
                }
                Ok(Some((from.to_string(), String::new())))
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
