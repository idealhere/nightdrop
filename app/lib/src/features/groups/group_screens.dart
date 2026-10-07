import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app.dart';
import '../../core/models.dart';
import '../../core/nightdrop_core.dart';
import '../../core/system_notices.dart';
import '../../theme/cyberdog.dart';

/// The name to show for a group member: "You" for us, the contact's name for someone we have a
/// chat with, and a neutral word for a member we are not connected to.
String groupMemberName(BuildContext context, NightdropCore core, String memberId) {
  final l10n = AppLocalizations.of(context)!;
  if (memberId == core.myIdentityKey) return l10n.groupYou;
  final contact = core.contacts.where((c) => c.id == memberId).firstOrNull;
  return contact?.displayName ?? l10n.groupUnknownMember;
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
                  title: Text(c.displayName),
                  subtitle: capable.contains(c.id) ? null : Text(l10n.groupNeedsNewer),
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

  void _showMembers(Group group) {
    final l10n = AppLocalizations.of(context)!;
    final core = NightdropScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(l10n.groupMembersTitle)),
            for (final id in group.members)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(groupMemberName(context, core, id)),
                subtitle: id == group.creator ? Text(l10n.groupCreatorTag) : null,
                trailing: core.contacts.any((c) => c.id == id && c.verified)
                    ? Icon(Icons.verified_user,
                        size: 18, color: Theme.of(context).colorScheme.primary)
                    : null,
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
                  Text(
                    l10n.groupMembersCount(group.members.length),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'members') _showMembers(group);
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
                    return _GroupBubble(
                      message: m,
                      sender: m.fromMe ? '' : groupMemberName(context, core, m.senderId),
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
              else
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('group-input'),
                            controller: _input,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: l10n.messageHint,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: const ValueKey('group-send'),
                          onPressed: _send,
                          icon: const Icon(Icons.arrow_upward),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: CyberDog.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CyberDog.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined, size: 15, color: scheme.secondary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                noticeBody(text),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
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
            Text(
              message.text,
              style: TextStyle(color: mine ? Colors.white : scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
