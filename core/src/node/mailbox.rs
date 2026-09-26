//! Per-pair, epoch-rotating **v2 mailbox handles** (`docs/design/mailbox-handles.md`).
//!
//! A v1 handle is a static hash of the recipient's identity key, so a relay can link every deposit
//! for one person, across senders and across days. A v2 handle is derived from a secret only the
//! two people in a chat hold, the recipient's key, and the UTC day — different for every sender,
//! and new every day. It is indistinguishable from a v1 handle on the wire (`mbx:` + 20 chars).
//!
//! **Losing a message is worse than the leak**, so the switch is gated (§5):
//!
//! * The pair *agrees* the secret over the chat they already have: each side contributes 32
//!   random bytes in a [`Frame::MailboxKey`], and the secret is derived from both.
//! * A side **posts** v2 only once the peer has *proven* it holds the same secret (a confirmation
//!   hash in its frame). Until then it posts v1.
//! * A side **polls** v1 always, plus the v2 handles of every pair whose secret it holds — for
//!   yesterday, today and tomorrow, so clock skew needs no negotiation.
//! * A changed contribution (a peer restored an older backup) resets confirmation at once, so
//!   nothing is posted to a handle the other side can no longer compute.

use super::*;

/// Marker prefix inside a [`Frame::MailboxKey`] plaintext, so a stray or truncated decrypt cannot
/// be mistaken for a contribution.
const MARK_MAILBOX_V2: &[u8] = b"nightdrop/ctl/mailbox/v2";

/// One UTC day. Handles rotate at this cadence; readers accept the neighbouring day either side.
pub(super) const EPOCH_SECS: u64 = 24 * 60 * 60;

/// This chat's side of the v2 agreement. `None` on a [`Chat`] until we first announce.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct MailboxPair {
    /// Our random contribution. Generated once, then fixed for the life of the chat.
    pub(super) own: [u8; 32],
    /// The peer's contribution, once received.
    pub(super) peer: Option<[u8; 32]>,
    /// The peer proved it computed the same secret. **Only then do we post v2** to it.
    pub(super) peer_confirmed: bool,
    /// We have sent a frame carrying *our* confirmation. Governs replies, so they terminate.
    pub(super) confirm_sent: bool,
}

impl MailboxPair {
    pub(super) fn fresh() -> Self {
        use rand::RngCore;
        let mut own = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut own);
        Self {
            own,
            peer: None,
            peer_confirmed: false,
            confirm_sent: false,
        }
    }
}

/// Base64 for the state file (sealed with everything else, like session pickles).
fn b64_32(b: &[u8; 32]) -> String {
    base64_handle(b)
}

fn unb64_32(s: &str) -> Option<[u8; 32]> {
    use base64::engine::general_purpose::URL_SAFE_NO_PAD;
    use base64::Engine as _;
    URL_SAFE_NO_PAD.decode(s).ok()?.try_into().ok()
}

/// Rebuild a chat's agreement state from its persisted fields. A missing or unreadable own
/// contribution yields `None` — the chat re-agrees, which is safe (see the module docs).
pub(super) fn from_persisted(chat: &crate::storage::PersistedChat) -> Option<MailboxPair> {
    let own = unb64_32(chat.mailbox_own.as_deref()?)?;
    let peer = chat.mailbox_peer.as_deref().and_then(unb64_32);
    Some(MailboxPair {
        own,
        peer,
        // Never confirmed without the contribution it confirms.
        peer_confirmed: peer.is_some() && chat.mailbox_peer_confirmed,
        confirm_sent: peer.is_some() && chat.mailbox_confirm_sent,
    })
}

/// The persisted fields for a chat's agreement state: `(own, peer, peer_confirmed, confirm_sent)`.
pub(super) fn to_persisted(
    pair: &Option<MailboxPair>,
) -> (Option<String>, Option<String>, bool, bool) {
    match pair {
        None => (None, None, false, false),
        Some(p) => (
            Some(b64_32(&p.own)),
            p.peer.as_ref().map(b64_32),
            p.peer_confirmed,
            p.confirm_sent,
        ),
    }
}

/// The pair secret: both contributions, order-independent, bound to both identity keys.
pub(super) fn pair_secret(a_ik: &str, b_ik: &str, own: &[u8; 32], peer: &[u8; 32]) -> [u8; 32] {
    let (lo, hi) = if own <= peer {
        (own, peer)
    } else {
        (peer, own)
    };
    let (k1, k2) = if a_ik <= b_ik {
        (a_ik, b_ik)
    } else {
        (b_ik, a_ik)
    };
    let mut ikm = Vec::with_capacity(64);
    ikm.extend_from_slice(lo);
    ikm.extend_from_slice(hi);
    let hk = hkdf::Hkdf::<sha2::Sha256>::new(Some(b"nightdrop/mailbox/v2/pair"), &ikm);
    let mut info = Vec::new();
    info.extend_from_slice(k1.as_bytes());
    info.push(0);
    info.extend_from_slice(k2.as_bytes());
    let mut out = [0u8; 32];
    hk.expand(&info, &mut out)
        .expect("32 bytes is a valid HKDF-SHA256 output length");
    out
}

/// What a peer sends to prove it holds `secret`. One-way, so it reveals nothing about it.
pub(super) fn confirm_hash(secret: &[u8; 32]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"nightdrop/mailbox/v2/confirm");
    h.update(secret);
    h.finalize().into()
}

/// The v2 handle for mail **to** `recipient_ik` within the pair, on UTC day `epoch`. Directional:
/// the two people in a chat get different handles, or each would drain the other's mail.
pub(super) fn v2_handle(secret: &[u8; 32], recipient_ik: &str, epoch: u64) -> String {
    let hk = hkdf::Hkdf::<sha2::Sha256>::from_prk(secret).expect("32-byte PRK is valid");
    let mut info = Vec::new();
    info.extend_from_slice(b"nightdrop/mailbox/v2");
    info.extend_from_slice(recipient_ik.as_bytes());
    info.extend_from_slice(&epoch.to_be_bytes());
    let mut out = [0u8; 15];
    hk.expand(&info, &mut out)
        .expect("15 bytes is a valid HKDF-SHA256 output length");
    format!("mbx:{}", base64_handle(&out))
}

/// The current UTC day.
pub(super) fn current_epoch() -> u64 {
    crate::api::now_secs() / EPOCH_SECS
}

/// Encode a contribution (and, once known, our confirmation) for [`Frame::MailboxKey`].
fn encode_payload(own: &[u8; 32], confirm: Option<&[u8; 32]>) -> Vec<u8> {
    let mut p = Vec::with_capacity(MARK_MAILBOX_V2.len() + 64);
    p.extend_from_slice(MARK_MAILBOX_V2);
    p.extend_from_slice(own);
    if let Some(c) = confirm {
        p.extend_from_slice(c);
    }
    p
}

/// Parse a decrypted [`Frame::MailboxKey`] payload. `None` for anything malformed.
fn decode_payload(p: &[u8]) -> Option<([u8; 32], Option<[u8; 32]>)> {
    let rest = p.strip_prefix(MARK_MAILBOX_V2)?;
    match rest.len() {
        32 => Some((rest.try_into().ok()?, None)),
        64 => Some((
            rest[..32].try_into().ok()?,
            Some(rest[32..].try_into().ok()?),
        )),
        _ => None,
    }
}

impl Node {
    /// The handle to post mail for `contact_id` under **right now**: v2 once the pair is
    /// confirmed, v1 otherwise (and for any contact we no longer have a chat with).
    pub(super) fn post_handle(&self, contact_id: &str) -> String {
        if let Some(pair) = self.chats.get(contact_id).and_then(|c| c.mailbox.as_ref()) {
            if let (true, Some(peer)) = (pair.peer_confirmed, pair.peer.as_ref()) {
                let secret = pair_secret(&self.identity_key(), contact_id, &pair.own, peer);
                return v2_handle(&secret, contact_id, current_epoch());
            }
        }
        mailbox_handle(contact_id)
    }

    /// Every handle our mail may sit under: v1, plus yesterday's, today's and tomorrow's v2 handle
    /// for each open chat whose secret we hold — confirmed or not, since the peer may already be
    /// posting to it.
    pub(super) fn drain_handles(&self) -> Vec<String> {
        let me = self.identity_key();
        let mut handles = vec![mailbox_handle(&me)];
        let today = current_epoch();
        for (contact_id, chat) in &self.chats {
            if chat.closed {
                continue;
            }
            let Some(pair) = &chat.mailbox else { continue };
            let Some(peer) = &pair.peer else { continue };
            let secret = pair_secret(&me, contact_id, &pair.own, peer);
            for epoch in [today.saturating_sub(1), today, today + 1] {
                handles.push(v2_handle(&secret, &me, epoch));
            }
        }
        handles
    }

    /// Send our contribution to every open, authorized chat that is not yet confirmed. Once per
    /// run per chat, retried on the next tick if it could not be delivered — the heal for a lost
    /// frame, and the start of the agreement for chats that predate v2.
    pub fn announce_mailbox(&mut self) {
        let ids: Vec<String> = self
            .chats
            .iter()
            .filter(|(id, c)| {
                c.authorized
                    && !c.closed
                    && !c.mailbox.as_ref().is_some_and(|p| p.peer_confirmed)
                    && !self.mailbox_announced.contains(id.as_str())
            })
            .map(|(id, _)| id.clone())
            .collect();
        for id in ids {
            if self.send_mailbox_key(&id) {
                self.mailbox_announced.insert(id);
            }
        }
    }

    /// Send our contribution — with our confirmation once we can compute the secret — on the chat.
    /// Returns whether a relay or the peer took it.
    pub(super) fn send_mailbox_key(&mut self, contact_id: &str) -> bool {
        #[cfg(test)]
        if self.legacy_v1_only {
            return false;
        }
        let me = self.identity_key();
        let (addr, frame) = {
            let Some(chat) = self.chats.get_mut(contact_id) else {
                return false;
            };
            if !chat.authorized || chat.closed {
                return false;
            }
            if chat.mailbox.is_none() {
                chat.mailbox = Some(MailboxPair::fresh());
                self.dirty = true;
            }
            let pair = chat.mailbox.as_mut().expect("set just above");
            let confirm = pair
                .peer
                .map(|peer| confirm_hash(&pair_secret(&me, contact_id, &pair.own, &peer)));
            if confirm.is_some() {
                pair.confirm_sent = true;
            }
            let payload = encode_payload(&pair.own, confirm.as_ref());
            let message = crypto::encrypt(&mut chat.session, &payload);
            (
                chat.peer_address.clone(),
                Frame::MailboxKey {
                    from: me.clone(),
                    message: WireOlm::from_olm(&message),
                },
            )
        };
        self.dirty = true;
        self.deliver(&addr, contact_id, &frame).is_ok()
    }

    /// A [`Frame::MailboxKey`] from `from`. Stores their contribution, checks their confirmation,
    /// and replies with ours when the agreement still needs it. Silent: no history entry.
    pub(super) fn on_mailbox_key(&mut self, from: &str, message: &WireOlm) -> Result<()> {
        #[cfg(test)]
        if self.legacy_v1_only {
            return Ok(());
        }
        let me = self.identity_key();
        let reply = {
            let Some(chat) = self.chats.get_mut(from) else {
                return Ok(());
            };
            if !chat.authorized {
                return Ok(());
            }
            // Undecryptable = ignored, never an error: an error here aborts the whole pump, and the
            // frames queued behind this one would never be processed. It happens legitimately — a
            // reply sealed on a session the peer has just replaced (a re-pair) — and a lost key frame
            // costs nothing, because the next run's announce resends it.
            let Ok(olm) = message.to_olm() else {
                return Ok(());
            };
            let Ok(pt) = crypto::decrypt(&mut chat.session, &olm) else {
                return Ok(());
            };
            let Some((theirs, their_confirm)) = decode_payload(&pt) else {
                return Ok(());
            };
            chat.last_seen = Some(crate::api::now_secs());
            let pair = chat.mailbox.get_or_insert_with(MailboxPair::fresh);
            if pair.peer != Some(theirs) {
                // New or changed: a changed contribution means they lost the old secret (a restore),
                // so stop posting v2 to them at once and re-agree.
                pair.peer = Some(theirs);
                pair.peer_confirmed = false;
                pair.confirm_sent = false;
            }
            let secret = pair_secret(&me, from, &pair.own, &theirs);
            if their_confirm == Some(confirm_hash(&secret)) {
                pair.peer_confirmed = true;
            }
            // Reply when they have not confirmed (they need ours), or when we have not yet sent our
            // confirmation (they need that). A confirm-bearing frame after both sides confirmed
            // triggers nothing, so this cannot ping-pong.
            their_confirm.is_none() || !pair.confirm_sent
        };
        self.dirty = true;
        if reply {
            self.send_mailbox_key(from);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_sides_derive_the_same_secret_in_either_order() {
        let (a, b) = ([1u8; 32], [2u8; 32]);
        assert_eq!(
            pair_secret("alice", "bob", &a, &b),
            pair_secret("bob", "alice", &b, &a)
        );
        assert_ne!(
            pair_secret("alice", "bob", &a, &b),
            pair_secret("alice", "carol", &a, &b),
            "bound to the pair's identity keys"
        );
    }

    #[test]
    fn handles_differ_by_direction_day_and_pair_and_look_like_v1() {
        let s = pair_secret("alice", "bob", &[1; 32], &[2; 32]);
        let to_bob = v2_handle(&s, "bob", 20_000);
        assert_ne!(
            to_bob,
            v2_handle(&s, "alice", 20_000),
            "each direction has its own handle"
        );
        assert_ne!(to_bob, v2_handle(&s, "bob", 20_001), "rotates daily");
        let other = pair_secret("carol", "bob", &[3; 32], &[4; 32]);
        assert_ne!(
            to_bob,
            v2_handle(&other, "bob", 20_000),
            "two senders to one recipient differ"
        );
        let v1 = mailbox_handle("bob");
        assert_eq!(
            to_bob.len(),
            v1.len(),
            "a relay cannot tell v2 from v1 by shape"
        );
        assert!(to_bob.starts_with("mbx:"));
    }

    #[test]
    fn payloads_round_trip_and_reject_garbage() {
        let own = [7u8; 32];
        let c = [9u8; 32];
        assert_eq!(
            decode_payload(&encode_payload(&own, None)),
            Some((own, None))
        );
        assert_eq!(
            decode_payload(&encode_payload(&own, Some(&c))),
            Some((own, Some(c)))
        );
        assert_eq!(decode_payload(b"nightdrop/ctl/mailbox/v2short"), None);
        assert_eq!(decode_payload(&[0u8; 56]), None);
    }
}
