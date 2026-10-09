import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../app.dart';
import '../../core/media_cache.dart';
import '../../core/models.dart';
import '../../core/nightdrop_core.dart';
import '../../core/system_notices.dart';
import '../../theme/cyberdog.dart';
import '../chat/chat_screen.dart'
    show compressImage, formatBytes, formatMessageTime, kMaxMediaBytes;
import '../chat/voice.dart';
import '../pairing/pairing_screen.dart';

/// The name to show for a group member: "You" for us, the contact's name for someone we have a
/// chat with, and a neutral word for a member we are not connected to.
String groupMemberName(BuildContext context, NightdropCore core, String memberId) {
  final l10n = AppLocalizations.of(context)!;
  if (memberId == core.myIdentityKey) return l10n.groupYou;
  final contact = core.contacts.where((c) => c.id == memberId).firstOrNull;
  return contact?.headerName ?? l10n.groupUnknownMember;
}

/// Pick a name and members for a new group. Members come from the chats we already have: a
/// group message travels to each member over the 1:1 chat with them.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  /// The core's limit: ten people, us included.
  static const _maxOthers = 9;

  final _name = TextEditingController();
  final _picked = <String>{};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    final core = NightdropScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final name = _name.text.trim();
      final id = await core.createGroup(name.isEmpty ? l10n.groupLabel : name, _picked.toList());
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => GroupChatScreen(groupId: id)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.groupCouldNotCreate(e.toString()))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final core = NightdropScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.newGroup)),
      body: ListenableBuilder(
        listenable: core,
        builder: (context, _) {
          final contacts = core.contacts;
          final capable = core.groupCapableContacts;
          if (contacts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.groupNoContacts, textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  key: const ValueKey('group-name'),
                  controller: _name,
                  maxLength: 64,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.groupName,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  l10n.groupEveryoneConnected,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              for (final c in contacts)
                CheckboxListTile(
                  value: _picked.contains(c.id),
                  title: Text(c.headerName),
                  subtitle: Text(
                    capable.contains(c.id) ? shortId(c.id) : l10n.groupNeedsNewer,
                    style: capable.contains(c.id)
                        ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                        : null,
                  ),
                  // A member on an older app would silently miss the whole conversation.
                  onChanged: !capable.contains(c.id) ||
                          (!_picked.contains(c.id) && _picked.length >= _maxOthers)
                      ? null
                      : (on) => setState(() {
                            if (on == true) {
                              _picked.add(c.id);
                            } else {
                              _picked.remove(c.id);
                            }
                          }),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('group-create'),
        onPressed: _picked.isEmpty || _busy ? null : _create,
        icon: const Icon(Icons.check),
        label: Text(l10n.groupCreate),
      ),
    );
  }
}

/// A group conversation: text messages, each under its sender's name.
class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _shown = 0;

  /// The composer is showing the voice recorder.
  bool _recordingVoice = false;

  Future<void> _sendVoice(Uint8List audio) async {
    final l10n = AppLocalizations.of(context)!;
    final core = NightdropScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _recordingVoice = false);
    try {
      await core.sendGroupMedia(widget.groupId, audio, kVoiceMime, kVoiceKind);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.groupCouldNotSend(e.toString()))));
    }
  }

  void _voiceCancelled(String? error) {
    setState(() => _recordingVoice = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final core = NightdropScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _input.clear();
    try {
      await core.sendGroupMessage(widget.groupId, text);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.groupCouldNotSend(e.toString()))));
    }
  }

  /// Pick a photo and send it to the group, recompressed like a photo in a 1:1 chat.
  Future<void> _attachPhoto() async {
    final l10n = AppLocalizations.of(context)!;
    final core = NightdropScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = (await FilePicker.pickFiles(type: FileType.image))?.files.single;
    final path = picked?.path;
    if (picked == null || path == null) return;
    if (picked.size > kMaxMediaBytes) {
      messenger.showSnackBar(SnackBar(
          content: Text(l10n.fileTooLarge(formatBytes(picked.size), formatBytes(kMaxMediaBytes)))));
      return;
    }
    try {
      var bytes = await File(path).readAsBytes();
      var mime = 'image/gif';
      // Animated GIFs are left alone; everything else becomes a smaller JPEG off the UI thread.
      if ((picked.extension ?? '').toLowerCase() != 'gif') {
        bytes = await compute(compressImage, bytes);
        mime = 'image/jpeg';
      }
      await core.sendGroupMedia(widget.groupId, bytes, mime, 'image');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.groupCouldNotSend(e.toString()))));
    }
  }

  /// Long-press on a message: copy its text, or delete our own recent one for everyone.
  Future<void> _showMessageMenu(Message message, {required bool canDelete}) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.canCopy)
              ListTile(
                key: const ValueKey('message-copy'),
                leading: const Icon(Icons.copy_outlined),
                title: Text(l10n.copyText),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            if (canDelete)
              ListTile(
                key: const ValueKey('message-delete'),
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.deleteForEveryone),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      messenger.showSnackBar(SnackBar(content: Text(l10n.textCopied)));
    } else if (action == 'delete' && mounted) {
      await _offerDelete(message);
    }
  }

  /// Confirm, then delete one of our own recent messages for everyone.
  Future<void> _offerDelete(Message message) async {
    final l10n = AppLocalizations.of(context)!;
    final core = NightdropScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteForEveryoneTitle),
        content: Text(l10n.groupUnsendBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('group-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await core.unsendGroupMessage(widget.groupId, message.unsendId);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.couldNotDelete(e.toString()))));
    }
  }

  /// Keep the newest message in view when the history grows.
  void _followNewMessages(int count) {
    if (count == _shown) return;
    _shown = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _confirm({
    required String title,
    required String body,
    required String action,
    required Future<void> Function() run,
    bool leaveScreen = false,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await run();
    if (leaveScreen) navigator.pop();
  }

  /// Run a group change and show the reason if it fails.
  Future<void> _change(Future<void> Function() run) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await run();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.groupCouldNotChange(e.toString()))));
    }
  }

  Future<void> _pickTimer(Group group) async {
    final l10n = AppLocalizations.of(context)!;
    final core = NightdropScope.of(context);
    final options = <String, int>{
      l10n.disappearingOff: 0,
      l10n.disappearing5Minutes: 300,
      l10n.disappearing1Hour: 3600,
      l10n.disappearing1Day: 86400,
      l10n.disappearing1Week: 604800,
    };
    final secs = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.disappearingMessages),
              subtitle: Text(l10n.groupTimerHint),
            ),
            for (final e in options.entries)
              ListTile(
                title: Text(e.key),
                trailing: group.disappearingSecs == e.value ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, e.value),
              ),
          ],
        ),
      ),
    );
    if (secs == null || secs == group.disappearingSecs) return;
    await _change(() => core.setGroupDisappearing(group.id, secs));
  }

  /// What the add-member sheet returns for "invite with a code" instead of a contact id.
  static const _inviteByCode = '\u0000invite-by-code';

  /// The contacts the creator can still add: new enough for groups and not already in.
  Future<void> _addMember(Group group) async {
    final l10n = AppLocalizations.of(context)!;
    final core = NightdropScope.of(context);
    final candidates = [
      for (final c in core.contacts)
        if (!group.members.contains(c.id) && core.groupCapableContacts.contains(c.id)) c,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(l10n.groupAddMember)),
            // Someone who is not a contact yet: one code pairs with them and adds them.
            ListTile(
              key: const ValueKey('group-invite-code'),
              leading: const Icon(Icons.qr_code_2),
              title: Text(l10n.groupInviteByCode),
              subtitle: Text(l10n.groupInviteByCodeHint),
              onTap: () => Navigator.pop(context, _inviteByCode),
            ),
            if (candidates.isEmpty)
              ListTile(title: Text(l10n.groupNobodyToAdd))
            else
              for (final c in candidates)
                ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: Text(c.headerName),
                  subtitle: Text(
                    shortId(c.id),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  onTap: () => Navigator.pop(context, c.id),
                ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == _inviteByCode) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PairingScreen(groupId: group.id)),
      );
      return;
    }
    await _change(() => core.addGroupMembers(group.id, [picked]));
  }

  void _showMembers(Group group) {
    final l10n = AppLocalizations.of(context)!;
    final core = NightdropScope.of(context);
    // Only the person who created the group changes who is in it.
    final manages = !group.left && group.creator == core.myIdentityKey;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(l10n.groupMembersTitle)),
            for (final id in group.members)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(groupMemberName(sheet, core, id))),
                    if (core.contacts.any((c) => c.id == id && c.verified)) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified_user,
                          size: 16, color: Theme.of(sheet).colorScheme.primary),
                    ],
                  ],
                ),
                // The ID is what tells two members with the same name apart.
                subtitle: Text(
                  id == group.creator ? '${shortId(id)} · ${l10n.groupCreatorTag}' : shortId(id),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: manages && id != core.myIdentityKey
                    ? IconButton(
                        key: ValueKey('group-remove-$id'),
                        tooltip: l10n.groupRemoveMember,
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () {
                          Navigator.pop(sheet);
                          _confirm(
                            title: l10n.groupRemoveMember,
                            body: l10n.groupRemoveBody(groupMemberName(context, core, id)),
                            action: l10n.groupRemoveMember,
                            run: () => _change(() => core.removeGroupMember(group.id, id)),
                          );
                        },
                      )
                    : null,
              ),
            if (!manages && !group.left)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(
                  l10n.groupOnlyCreatorManages,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(sheet).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (manages && group.members.length < 10)
              ListTile(
                key: const ValueKey('group-add-member'),
                leading: const Icon(Icons.person_add_alt),
                title: Text(l10n.groupAddMember),
                onTap: () {
                  Navigator.pop(sheet);
                  _addMember(group);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final core = NightdropScope.of(context);
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final group = core.groups.where((g) => g.id == widget.groupId).firstOrNull;
        if (group == null) {
          return Scaffold(appBar: AppBar(title: Text(l10n.groupLabel)));
        }
        final messages = core.groupMessagesFor(group.id);
        _followNewMessages(messages.length);
        // Reading it is seeing it: clear the badge once this frame is built.
        WidgetsBinding.instance.addPostFrameCallback((_) => core.markGroupRead(group.id));
        return Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showMembers(group),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(group.name, overflow: TextOverflow.ellipsis),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.groupMembersCount(group.members.length),
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                      if (group.disappearingSecs > 0) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.timer_outlined, size: 13, color: scheme.onSurfaceVariant),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'members') _showMembers(group);
                  if (value == 'timer') _pickTimer(group);
                  if (value == 'leave') {
                    _confirm(
                      title: l10n.groupLeave,
                      body: l10n.groupLeaveBody,
                      action: l10n.groupLeave,
                      run: () => core.leaveGroup(group.id),
                    );
                  }
                  if (value == 'delete') {
                    _confirm(
                      title: l10n.groupDelete,
                      body: l10n.groupDeleteBody,
                      action: l10n.delete,
                      run: () => core.deleteGroup(group.id),
                      leaveScreen: true,
                    );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'members', child: Text(l10n.groupMembersTitle)),
                  if (!group.left)
                    PopupMenuItem(value: 'timer', child: Text(l10n.disappearingMessages)),
                  if (!group.left) PopupMenuItem(value: 'leave', child: Text(l10n.groupLeave)),
                  PopupMenuItem(value: 'delete', child: Text(l10n.groupDelete)),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    if (m.system) return _Notice(text: m.text);
                    return GestureDetector(
                      onLongPress: m.canCopy || (m.canUnsend && !group.left)
                          ? () => _showMessageMenu(m, canDelete: m.canUnsend && !group.left)
                          : null,
                      child: _GroupBubble(
                        message: m,
                        sender: m.fromMe || !_startsRun(messages, i)
                            ? ''
                            : '${groupMemberName(context, core, m.senderId)} · '
                                '${shortId(m.senderId)}',
                      ),
                    );
                  },
                ),
              ),
              if (group.left)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.groupLeftBanner,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              else if (_recordingVoice)
                VoiceRecordingBar(onDone: _sendVoice, onCancel: _voiceCancelled)
              else
                SafeArea(
                  top: false,
                  child: Padding(
                    // The same row as a 1:1 chat: attach, field, microphone, send.
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: l10n.groupAttachPhoto,
                          style: _composerTile,
                          onPressed: _attachPhoto,
                          icon: const Icon(Icons.attach_file),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('group-input'),
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: l10n.messageHint,
                              filled: true,
                              fillColor: CyberDog.panel,
                              border: _fieldBorder(CyberDog.hairline),
                              enabledBorder: _fieldBorder(CyberDog.hairline),
                              focusedBorder: _fieldBorder(CyberDog.hairlineBright, width: 1.4),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: l10n.voiceRecord,
                          style: _composerTile,
                          onPressed: () => setState(() => _recordingVoice = true),
                          icon: const Icon(Icons.mic_none),
                        ),
                        const SizedBox(width: 6),
                        CyberDogSendButton(
                          key: const ValueKey('group-send'),
                          onPressed: _send,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The composer's square buttons and field outline, as in a 1:1 chat.
final _composerTile = IconButton.styleFrom(
  backgroundColor: CyberDog.panel,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: const BorderSide(color: CyberDog.hairline),
  ),
);

OutlineInputBorder _fieldBorder(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );

/// Whether message [i] is the first of a run from its sender: the one that carries the name.
bool _startsRun(List<Message> messages, int i) {
  if (i == 0) return true;
  final before = messages[i - 1];
  return before.system || before.fromMe || before.senderId != messages[i].senderId;
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: CyberDog.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CyberDog.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              noticeMarker(text).startsWith('⏱') ? Icons.timer_outlined : Icons.group_outlined,
              size: 13,
              color: scheme.secondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                noticeBody(text),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupBubble extends StatelessWidget {
  const _GroupBubble({required this.message, required this.sender});

  final Message message;

  /// Shown above someone else's message; empty for our own.
  final String sender;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final mine = message.fromMe;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          gradient: mine ? CyberDog.outgoing : null,
          color: mine ? null : CyberDog.panel,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: CyberDog.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sender.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  sender,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: CyberDog.accentLight,
                  ),
                ),
              ),
            if (message.isDeleted)
              Text(
                l10n.messageDeleted,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: (mine ? Colors.white : scheme.onSurface).withValues(alpha: 0.6),
                ),
              )
            else if (message.isImage && message.mediaId.isNotEmpty)
              _GroupPhoto(mediaId: message.mediaId)
            else if (message.isAudio && message.mediaId.isNotEmpty)
              VoiceBubble(mediaId: message.mediaId, mine: mine, bytes: message.mediaSize)
            else
              Text(
                message.text,
                style: TextStyle(color: mine ? Colors.white : scheme.onSurface),
              ),
            const SizedBox(height: 3),
            // The time, and on our own messages whether it has reached the group: one tick once
            // it is sent, two when every member's device has it. There is no "read".
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mine && !message.isDeleted && message.delivery.isNotEmpty) ...[
                  Tooltip(
                    message: message.delivery == 'delivered'
                        ? l10n.groupDeliveredToAll
                        : l10n.deliverySent,
                    child: Icon(
                      message.delivery == 'delivered' ? Icons.done_all : Icons.done,
                      key: ValueKey('group-delivery-${message.delivery}'),
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  formatMessageTime(message.at),
                  style: TextStyle(
                    fontSize: 10,
                    color: (mine ? Colors.white : scheme.onSurfaceVariant).withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A photo in a group bubble: decrypted once, kept in the shared [MediaCache], and opened full
/// screen on tap.
class _GroupPhoto extends StatelessWidget {
  const _GroupPhoto({required this.mediaId});

  final String mediaId;

  @override
  Widget build(BuildContext context) {
    final core = NightdropScope.of(context);
    final bytes = MediaCache.bytes.putIfAbsent(
      mediaId,
      () async => Uint8List.fromList(await core.mediaBytes(mediaId)),
    );
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return SizedBox(
            width: 220,
            height: 160,
            child: Center(
              child: snapshot.hasError
                  ? const Icon(Icons.broken_image_outlined)
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => GestureDetector(
              onTap: () => Navigator.pop(context),
              child: InteractiveViewer(child: Image.memory(data)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(data, width: 220, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        );
      },
    );
  }
}
