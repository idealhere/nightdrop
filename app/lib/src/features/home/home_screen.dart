import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app.dart';
import '../../core/app_config.dart';
import '../../core/app_locale.dart';
import '../../core/app_version.dart';
import '../../core/background_delivery.dart';
import '../../core/nightdrop_core.dart';
import '../../core/models.dart';
import '../../core/privacy_prefs.dart';
import '../../core/profile_name.dart';
import '../backup/backup_actions.dart';
import '../bridges/bridges_screen.dart';
import '../chat/chat_screen.dart';
import '../groups/group_screens.dart';
import 'my_address_screen.dart';
import '../lock/app_lock_settings.dart';
import '../pairing/pairing_screen.dart';
import '../privacy/privacy_screen.dart';
import '../../theme/brand.dart';
import '../../theme/cyberdog.dart';

/// The app's home: four sections — chats, groups, settings, profile — under one compact header.
/// A bar along the bottom on a phone; a rail down the side on a wide window, where a bottom bar
/// would sit a long way from everything else.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _wide = 900.0;

  /// From this width there is room for the list and the open chat side by side.
  static const _desk = 1200.0;

  int _tab = 0;

  /// The Requests line of the top bar: the chat list narrowed to the requests waiting for an
  /// answer. It belongs to the Chats section.
  bool _requestsOnly = false;

  /// The chat open in the pane beside the rail on a wide window: its id and whether it is a
  /// group. Null while the pane shows the section itself.
  (String, bool)? _open;

  final _paneKey = GlobalKey<NavigatorState>();
  final _detailKey = GlobalKey<NavigatorState>();

  /// On a large window the open chat sits beside the list. It has a navigator of its own, so a
  /// chat that closes itself — deleted or left — falls back to the empty state, and whatever the
  /// chat opens (a profile, the verify screen) stays inside the message area.
  Widget _detail(NightdropCore core) {
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final open = _open;
        final exists = open != null &&
            (open.$2
                ? core.groups.any((g) => g.id == open.$1)
                : core.contacts.any((c) => c.id == open.$1));
        return Navigator(
          key: _detailKey,
          pages: [
            const _DetailPage(key: ValueKey('empty'), child: _EmptyDetail()),
            if (open != null && exists)
              _DetailPage(
                key: ValueKey('chat-${open.$1}'),
                child: open.$2
                    ? GroupChatScreen(groupId: open.$1)
                    : ChatScreen(contactId: open.$1),
              ),
          ],
          onDidRemovePage: (page) {
            if (page.key == const ValueKey('empty')) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _open == open) setState(() => _open = null);
            });
          },
        );
      },
    );
  }

  /// On a wide window the rail stays put and everything else happens in the pane beside it, which
  /// has a navigator of its own: a chat opens over the list, and its back arrow — or a chat that
  /// closes itself, deleted or left — returns to the list.
  Widget _pane(NightdropCore core, Widget section) {
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final open = _open;
        final exists = open != null &&
            (open.$2
                ? core.groups.any((g) => g.id == open.$1)
                : core.contacts.any((c) => c.id == open.$1));
        return Navigator(
          key: _paneKey,
          pages: [
            MaterialPage<void>(
              key: const ValueKey('section'),
              child: Material(type: MaterialType.transparency, child: section),
            ),
            if (open != null && exists)
              MaterialPage<void>(
                key: ValueKey('chat-${open.$1}'),
                child: open.$2
                    ? GroupChatScreen(groupId: open.$1)
                    : ChatScreen(contactId: open.$1),
              ),
          ],
          onDidRemovePage: (page) {
            if (page.key == const ValueKey('section')) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _open == open) setState(() => _open = null);
            });
          },
        );
      },
    );
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// The one button for starting something: a chat, a group, or scanning someone's code.
  Future<void> _newAction() async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('new-chat'),
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(l10n.newChat),
              onTap: () => Navigator.pop(context, 'chat'),
            ),
            ListTile(
              key: const ValueKey('new-group'),
              leading: const Icon(Icons.group_add_outlined),
              title: Text(l10n.newGroup),
              onTap: () => Navigator.pop(context, 'group'),
            ),
            ListTile(
              key: const ValueKey('scan-qr'),
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(l10n.scanQr),
              onTap: () => Navigator.pop(context, 'scan'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'chat':
        _push(const PairingScreen());
      case 'group':
        _push(const CreateGroupScreen());
      case 'scan':
        _push(const PairingScreen(initialTab: 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final core = NightdropScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= _wide;
    // Beside the rail, a chat opens in the pane rather than over the whole window.
    void openInPane(String id, bool group) => setState(() => _open = (id, group));
    final desk = width >= _desk;
    // A phone's bottom bar carries the first three; the profile is in its top bar. A side rail
    // has room for all four.
    final sections = [
      (Icons.chat_bubble_outline, Icons.chat_bubble, l10n.chats),
      (Icons.people_outline, Icons.people, AppLocale.pick('Contacts', 'Контакты')),
      (Icons.settings_outlined, Icons.settings, l10n.tabSettings),
      (Icons.person_outline, Icons.person, l10n.tabProfile),
    ];
    final page = switch (_tab) {
      0 => _ChatList(
          groupsOnly: false,
          requestsOnly: _requestsOnly,
          onOpen: wide ? openInPane : null,
          selected: desk ? _open?.$1 : null,
        ),
      1 => _ChatList(
          groupsOnly: false,
          peopleOnly: true,
          onOpen: wide ? openInPane : null,
          selected: desk ? _open?.$1 : null,
        ),
      2 => const _SettingsTab(),
      _ => const _ProfileTab(),
    };
    final content = Column(
      children: [
        if (_tab < 2) ...[
          _OnionBanner(core: core),
          const _BackgroundStoppedBanner(),
          _RelayHealthBanner(core: core),
          _BackupReminderBanner(core: core),
        ],
        Expanded(child: page),
      ],
    );
    // The one button for starting something sits in the top bar, next to the profile.
    final actionButton = Padding(
      padding: const EdgeInsets.only(right: 12, left: 6),
      child: Semantics(
        button: true,
        label: l10n.newChat,
        child: Tooltip(
          message: l10n.newChat,
          child: InkResponse(
            key: const ValueKey('new-action'),
            onTap: _newAction,
            radius: 26,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: CyberDog.outgoing,
                boxShadow: CyberDog.glow,
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
    final profileButton = IconButton(
      key: const ValueKey('profile-button'),
      tooltip: l10n.tabProfile,
      onPressed: () => _push(const _ProfileScreen()),
      icon: const _OwnAvatar(radius: 17),
    );
    if (desk) {
      final rail = NavigationRail(
        backgroundColor: Colors.transparent,
        extended: true,
        minExtendedWidth: 212,
        indicatorColor: CyberDog.accent.withValues(alpha: 0.12),
        selectedIconTheme: const IconThemeData(color: CyberDog.accent),
        selectedLabelTextStyle: const TextStyle(
          color: CyberDog.accentDark,
          fontWeight: FontWeight.w700,
          fontSize: 14.5,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
          fontSize: 14.5,
        ),
        leading: const Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CyberDogLogo(size: 40),
              SizedBox(width: 10),
              BrandTitle(fontSize: 17),
            ],
          ),
        ),
        selectedIndex: _tab,
        // Choosing a section leaves whatever chat was open.
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _open = null;
        }),
        destinations: [
          for (final (icon, selected, label) in sections)
            NavigationRailDestination(
              icon: Icon(icon),
              selectedIcon: Icon(selected),
              label: Text(label),
            ),
        ],
      );
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Surface(child: rail),
                const SizedBox(width: 12),
                if (_tab < 2) ...[
                  SizedBox(
                    width: 380,
                    child: _Surface(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 18, 14, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    sections[_tab].$3,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.5,
                                    ),
                                  ),
                                ),
                                IconButton.filled(
                                  key: const ValueKey('new-action'),
                                  tooltip: l10n.newChat,
                                  onPressed: _newAction,
                                  icon: const Icon(Icons.add_rounded),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: content),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _Surface(child: _detail(core))),
                ] else
                  Expanded(
                    child: _Surface(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: content,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        centerTitle: false,
        titleSpacing: 16,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CyberDogLogo(size: 36),
            SizedBox(width: 8),
            BrandTitle(fontSize: 21),
          ],
        ),
        actions: [if (!wide) profileButton, actionButton],
        // What the lists hold, as a line under the brand: chats, contacts, and the requests
        // waiting for an answer.
        bottom: !wide && _tab < 2
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: _TopTabs(
                  active: _requestsOnly && _tab == 0 ? 2 : _tab,
                  requests: core.incomingRequests.length,
                  onSelect: (i) => setState(() {
                    _tab = i == 1 ? 1 : 0;
                    _requestsOnly = i == 2;
                  }),
                ),
              )
            : null,
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  backgroundColor: Colors.transparent,
                  extended: MediaQuery.sizeOf(context).width >= 1100,
                  selectedIndex: _tab,
                  // Choosing a section leaves whatever chat was open in the pane.
                  onDestinationSelected: (i) => setState(() {
                    _tab = i;
                    _open = null;
                  }),
                  destinations: [
                    for (final (icon, selected, label) in sections)
                      NavigationRailDestination(
                        icon: Icon(icon),
                        selectedIcon: Icon(selected),
                        label: Text(label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1, color: CyberDog.hairline),
                Expanded(
                  child: _pane(
                    core,
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: content,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : content,
      // A floating bar: lifted off the edge, rounded, with a soft shadow.
      bottomNavigationBar: wide
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(color: Color(0x241C3E78), blurRadius: 24, offset: Offset(0, 8)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: NavigationBar(
                    height: 62,
                    backgroundColor: CyberDog.panel,
                    indicatorColor: CyberDog.accent.withValues(alpha: 0.12),
                    // The profile is not along the bottom: shown from a rail, it marks nothing.
                    selectedIndex: _tab > 2 ? 2 : _tab,
                    onDestinationSelected: (i) => setState(() {
                      _tab = i;
                      _requestsOnly = false;
                    }),
                    destinations: [
                      for (final (icon, selected, label) in sections.take(3))
                        NavigationDestination(
                          icon: Icon(icon),
                          selectedIcon: Icon(selected, color: CyberDog.accent),
                          label: label,
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// The line under the brand on a phone: Chats, Contacts, Requests. It shows where one is and how
/// many requests wait, and a tap goes there.
class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.active, required this.requests, required this.onSelect});

  /// 0 chats, 1 contacts, 2 requests.
  final int active;
  final int requests;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(int index, String text, {int count = 0}) {
      final on = active == index;
      return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: InkWell(
            key: ValueKey('top-tab-$index'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(index),
            child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.only(bottom: 8, top: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: on ? CyberDog.accent : Colors.transparent, width: 2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? CyberDog.accent : scheme.onSurfaceVariant,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Badge(label: Text('$count'), backgroundColor: CyberDog.accent),
                ],
              ],
            ),
          ),
          ),
        );
    }

    return Container(
          height: 40,
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CyberDog.hairline)),
          ),
          // Scaled down rather than cut off, should a narrow screen or a large font not fit it.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tab(0, AppLocale.pick('Chats', 'Чаты')),
                tab(1, AppLocale.pick('Contacts', 'Контакты')),
                tab(2, AppLocale.pick('Requests', 'Запросы'), count: requests),
              ],
            ),
          ),
    );
  }
}

/// The user's own avatar, in the colour chosen in the profile.
class _OwnAvatar extends StatelessWidget {
  const _OwnAvatar({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: PrivacyPrefs.avatarStyle,
        builder: (context, style, _) =>
            CyberDogAvatar(seed: 'me', label: '', radius: radius, palette: style),
      );
}

/// The avatar at the top of the profile: tap it to choose another colour.
class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkResponse(
        key: const ValueKey('change-avatar'),
        radius: 56,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (var i = 0; i < CyberDogAvatar.paletteCount; i++)
                    InkResponse(
                      key: ValueKey('avatar-$i'),
                      radius: 36,
                      onTap: () {
                        PrivacyPrefs.setAvatarStyle(i);
                        Navigator.pop(context);
                      },
                      child: CyberDogAvatar(seed: 'me', label: '', radius: 30, palette: i),
                    ),
                ],
              ),
            ),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const _OwnAvatar(radius: 46),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CyberDog.panel,
                  border: Border.all(color: CyberDog.hairline),
                ),
                child: const Icon(Icons.edit_outlined, size: 16, color: CyberDog.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The profile as a screen of its own, opened from the top bar of a phone.
class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.tabProfile)),
        body: const _ProfileTab(),
      );
}

/// One row of the chat list: a contact or a group, with the last thing said in it.
class _Row {
  const _Row({this.contact, this.group, this.last});

  final Contact? contact;
  final Group? group;

  /// The newest message that is not a system notice, if there is one.
  final Message? last;
}

/// What the list says a message was, without printing more than a line of it. A message that is
/// meant to disappear is never quoted here.
String _preview(AppLocalizations l10n, Message m) {
  final body = m.isDeleted
      ? l10n.messageDeleted
      : m.burnSecs > 0 || m.isBurnExpired || m.isViewedOnce
          ? l10n.previewHidden
          : m.isImage
              ? l10n.previewPhoto
              : m.isAudio
                  ? l10n.previewVoice
                  : m.isVideo
                      ? l10n.video
                      : m.text;
  return m.fromMe ? '${l10n.previewYou} $body' : body;
}

/// Today's messages by the clock, older ones by the date.
String _listTime(DateTime at) {
  final now = DateTime.now();
  final local = at.toLocal();
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return formatMessageTime(at);
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}';
}

/// The chats, newest activity first: everything, or only the groups.
class _ChatList extends StatelessWidget {
  const _ChatList({required this.groupsOnly, this.peopleOnly = false,
    this.requestsOnly = false,
    this.onOpen,
    this.selected,
  });

  /// People without the groups: the Contacts section.
  final bool peopleOnly;

  /// Only the requests waiting for an answer.
  final bool requestsOnly;

  final bool groupsOnly;

  /// On a wide window: open the chat in the pane beside the rail (its id, whether it is a group)
  /// instead of over the whole window. Null on a phone.
  final void Function(String id, bool group)? onOpen;

  /// The chat open beside the list on a large window, to mark its row.
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final core = NightdropScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final requests = groupsOnly ? const <Contact>[] : core.incomingRequests;
        final rows = requestsOnly ? <_Row>[] : <_Row>[
          if (!peopleOnly)
            for (final g in core.groups)
              _Row(
                group: g,
                last: core.groupMessagesFor(g.id).where((m) => !m.system).lastOrNull,
              ),
          if (!groupsOnly)
            for (final c in core.contacts)
              _Row(
                contact: c,
                last: core.messagesFor(c.id).where((m) => !m.system).lastOrNull,
              ),
        ];
        // Newest first; chats with nothing said yet keep their order at the end. The sort is
        // stable only if told to be, so the original position breaks ties.
        final order = {for (var i = 0; i < rows.length; i++) rows[i]: i};
        rows.sort((a, b) {
          final at = a.last?.at, bt = b.last?.at;
          if (at != null && bt != null) return bt.compareTo(at);
          if (at != null) return -1;
          if (bt != null) return 1;
          return order[a]!.compareTo(order[b]!);
        });
        if (requests.isEmpty && rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 168,
                    height: 168,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x5522B4F2), Color(0x1F1F6FFF), Color(0x001F6FFF)],
                        stops: [0, .6, 1],
                      ),
                    ),
                    child: const CyberDogLogo(size: 112),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    requestsOnly
                        ? AppLocale.pick('No requests', 'Запросов нет')
                        : groupsOnly
                            ? l10n.noGroupsYet
                            : l10n.noChatsYet,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    requestsOnly
                        ? AppLocale.pick('Someone who writes to your address appears here.',
                            'Здесь появится тот, кто напишет на ваш адрес.')
                        : AppLocale.pick(
                            'Tap + to start a private chat.', 'Нажмите +, чтобы начать приватный чат.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            for (final r in requests) _RequestTile(request: r, core: core),
            for (final row in rows)
              _ChatTile(
                row: row,
                core: core,
                onOpen: onOpen,
                selected: selected != null && selected == (row.contact?.id ?? row.group?.id),
              ),
          ],
        );
      },
    );
  }
}

/// A chat in the list: avatar, name, the last line, and on the right the time with either the
/// unread count or, for our own last message, whether it was delivered.
class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.row, required this.core, this.onOpen, this.selected = false});

  final _Row row;
  final NightdropCore core;
  final void Function(String id, bool group)? onOpen;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final contact = row.contact;
    final group = row.group;
    final last = row.last;
    final unread =
        contact != null ? core.unreadCount(contact.id) : core.groupUnreadCount(group!.id);
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    final subtitle = last != null
        ? _preview(l10n, last)
        : contact != null
            ? (contact.remoteStorage ? l10n.storedOnServer24h : l10n.storedOnThisDevice)
            : l10n.groupMembersCount(group!.members.length);
    void open() {
      final inPane = onOpen;
      if (inPane != null) {
        inPane(contact?.id ?? group!.id, group != null);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => contact != null
              ? ChatScreen(contactId: contact.id)
              : GroupChatScreen(groupId: group!.id),
        ),
      );
    }

    // Long-press (touch) or right-click (desktop) a chat to delete it.
    void remove() {
      if (contact != null) _confirmDeleteChat(context, core, contact);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
      color: selected ? CyberDog.accent.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
      onTap: open,
      onLongPress: contact != null ? remove : null,
      onSecondaryTap: contact != null ? remove : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            ExcludeSemantics(
              child: CyberDogAvatar(
                seed: contact?.id ?? group!.id,
                label: contact?.headerName ?? group!.name,
                group: group != null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          contact?.headerName ?? group!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            letterSpacing: -.1,
                            fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (contact != null && contact.showIdentityTag) ...[
                        const SizedBox(width: 6),
                        IdentityTag(tag: contact.identityTag),
                      ],
                      if (contact != null && contact.verified) ...[
                        const SizedBox(width: 6),
                        // Present, not prominent: the name is what the row is for.
                        Icon(Icons.verified_user,
                            semanticLabel: l10n.verified,
                            size: 12,
                            color: scheme.onSurfaceVariant),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // An unread chat's last line is in ink, a read one's is muted.
                    style: unread > 0
                        ? muted.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w500)
                        : muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  last != null ? _listTime(last.at) : '',
                  style: muted.copyWith(
                    fontSize: 12,
                    color: unread > 0 ? CyberDog.accent : null,
                    fontWeight: unread > 0 ? FontWeight.w600 : null,
                  ),
                ),
                const SizedBox(height: 5),
                if (unread > 0)
                  Badge(label: Text('$unread'), backgroundColor: CyberDog.accent)
                else if (last != null && last.fromMe && last.delivery.isNotEmpty)
                  Icon(
                    switch (last.delivery) {
                      'delivered' => Icons.done_all,
                      'queued' => Icons.cloud_upload_outlined,
                      'expired' => Icons.error_outline,
                      _ => group != null ? Icons.done : Icons.schedule,
                    },
                    size: 15,
                    // Delivered ticks are in the accent, anything still on its way is muted.
                    color: last.delivery == 'delivered' ? CyberDog.accent : scheme.onSurfaceVariant,
                  )
                else
                  const SizedBox(height: 15),
              ],
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }
}

/// A white glass panel: the sidebar, the list and the message area of a large window.
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: CyberDog.panel.withValues(alpha: 0.82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: CyberDog.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

/// The message area before a chat is chosen.
class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CyberDogLogo(size: 132),
            const SizedBox(height: 18),
            Text(
              AppLocale.pick('Select a chat', 'Выберите чат'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.4),
            ),
            const SizedBox(height: 6),
            Text(
              AppLocale.pick('Your messages are end-to-end encrypted.',
                  'Ваши сообщения защищены сквозным шифрованием.'),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// A page of the message area. Unlike an ordinary page it brings no back arrow and no slide:
/// the chat is beside its list, not on top of it.
class _DetailPage extends Page<void> {
  const _DetailPage({required LocalKey super.key, required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _DetailRoute(this);
}

class _DetailRoute extends PageRoute<void> {
  _DetailRoute(_DetailPage page) : super(settings: page);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get impliesAppBarDismissal => false;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(BuildContext context, Animation<double> a, Animation<double> b) =>
      (settings as _DetailPage).child;
}

/// A small heading between groups of settings.
class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            color: CyberDog.accentLight,
          ),
        ),
      );
}

/// A rounded panel holding a few related rows, with a hairline between them.
class _Panel extends StatelessWidget {
  const _Panel(this.rows);

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Material(
          color: CyberDog.panel.withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CyberDog.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56, color: CyberDog.hairline),
                rows[i],
              ],
            ],
          ),
        ),
      );
}

/// One row of a settings panel: an icon, what it is, and a chevron saying it opens something.
class _Item extends StatelessWidget {
  const _Item(this.icon, this.title, this.onTap, {this.danger = false, this.chevron = true});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  /// Drawn in the error colour: an action that cannot be undone.
  final bool danger;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: danger ? scheme.error : CyberDog.accentLight),
      title: Text(title, style: danger ? TextStyle(color: scheme.error) : null),
      trailing: chevron
          ? Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant)
          : null,
      onTap: onTap,
    );
  }
}

/// Settings — the only place they live. Everyday ones first; what matters only on the Tor
/// transport, or to someone running their own relay, is folded away under "Advanced".
class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final core = NightdropScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    void push(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Section(l10n.settingsSectionPrivacy),
        _Panel([
          _Item(Icons.lock_outline, l10n.privacyMenu, () => push(const PrivacyScreen())),
          _Item(Icons.pin_outlined, l10n.appLockMenu, () => showAppLockSettings(context, core)),
          _Item(Icons.shield_outlined, l10n.duressMenu, () => showDuressSettings(context, core)),
          if (BackgroundDelivery.supported)
            _Item(Icons.notifications_none, l10n.backgroundDeliveryMenu,
                () => _backgroundDeliverySettings(context)),
        ]),
        _Section(l10n.settingsSectionData),
        _Panel([
          _Item(Icons.save_alt, l10n.saveBackupFile, () => createAndSaveBackup(context, core)),
          _Item(Icons.cloud_upload_outlined, l10n.backUpToServer24h,
              () => _createServerBackup(context, core)),
          _Item(Icons.merge_type, l10n.mergeChatBackupMenu, () => mergeChatBackup(context, core)),
        ]),
        _Section(l10n.settingsSectionApp),
        _Panel([
          _Item(Icons.language, l10n.switchLanguage, AppLocale.toggle, chevron: false),
          _Item(Icons.info_outline, l10n.aboutMenu, () => _showAbout(context)),
        ]),
        const SizedBox(height: 18),
        _Panel([
          ExpansionTile(
            key: const ValueKey('settings-advanced'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.tune, color: CyberDog.accentLight),
            title: Text(l10n.settingsSectionAdvanced),
            children: [
              _Item(Icons.visibility_off_outlined, l10n.coverTrafficMenu,
                  () => _coverTrafficSettings(context, core)),
              _Item(Icons.local_fire_department_outlined, l10n.burnReceiptsMenu,
                  () => _burnReceiptSettings(context, core)),
              _Item(Icons.hub_outlined, l10n.myRelaysMenu, () => _editRelays(context, core)),
              _Item(Icons.alt_route, l10n.bridgesMenu, () => push(const BridgesScreen())),
              _Item(Icons.restart_alt, l10n.resetTorMenu,
                  () => _confirmResetTor(context, core)),
            ],
          ),
        ]),
      ],
    );
  }
}

/// Who you are here: the name you chose, your ID, the address others can reach you at — and the
/// two ways out.
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final core = NightdropScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    void push(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 28),
        const _AvatarChoice(),
        const SizedBox(height: 14),
        ValueListenableBuilder<String>(
          valueListenable: ProfileName.current,
          builder: (context, name, _) => Text(
            plainName(name),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 8),
        const Center(child: UserRankBadge(rank: UserRankBadge.defaultRank)),
        const SizedBox(height: 8),
        Text(
          core.identity?.id ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        _Panel([
          _Item(Icons.qr_code_2, l10n.myAddressTitle, () => push(const MyAddressScreen())),
          _Item(Icons.badge_outlined, l10n.myNameMenu, () => _editMyName(context, core)),
          _Item(Icons.fingerprint, l10n.myIdentity, () => _showMyIdentity(context, core)),
        ]),
        const SizedBox(height: 18),
        // The harmless way out above the destructive one, so it is the one found first.
        _Panel([
          _Item(Icons.logout, l10n.exitMenu, () => _confirmExit(context, core), chevron: false),
          _Item(Icons.delete_forever_outlined, l10n.logoutDeleteMenu,
              () => _confirmLogout(context, core),
              danger: true, chevron: false),
        ]),
      ],
    );
  }
}

/// Cover traffic (#4). Opt-in, and the dialog carries the limit as prominently as the benefit:
/// this is chaff, not constant-rate transmission, so it raises the cost of traffic analysis
/// without ending it. A user who believes it makes them untrackable is worse off than one who
/// knows what it actually buys. See `docs/design/cover-traffic.md` §4.
/// Manually reset the Tor connection. Confirmed first because it drops the connection and
/// reconnects, which takes a minute or two — but it is the only remedy for a guard set that has
/// churned out of the network, and until this existed a user in that state could only reinstall.
///
/// Says plainly what it does and does not touch: the identity and chats are untouched, and the
/// `.onion` address is kept, so nobody loses contacts by trying it.
Future<void> _confirmResetTor(BuildContext context, NightdropCore core) async {
  final l10n = AppLocalizations.of(context)!;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.resetTorTitle),
      content: Text(l10n.resetTorBody),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.resetTorConfirm)),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(l10n.resetTorRunning)));
  await core.resetTorConnection();
}

Future<void> _coverTrafficSettings(BuildContext context, NightdropCore core) async {
  final l10n = AppLocalizations.of(context)!;
  final on = await core.coverTrafficEnabled();
  if (!context.mounted) return;
  final theme = Theme.of(context);
  final turnOn = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.coverTrafficTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.coverTrafficBody),
            const SizedBox(height: 16),
            Text(
              l10n.coverTrafficLimit,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(!on),
          child: Text(on ? l10n.turnOff : l10n.turnOn),
        ),
      ],
    ),
  );
  if (turnOn == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  await core.setCoverTraffic(turnOn);
  messenger.showSnackBar(SnackBar(
    content: Text(turnOn ? l10n.coverTrafficOn : l10n.coverTrafficOff),
  ));
}

/// Turn burn-view receipts on or off (`docs/design/burn-messages.md`).
///
/// Off by default and the recipient's own choice, because it discloses *their* reading behaviour
/// to someone else. The dialog states the cost before the switch, not after: the sender's copy
/// disappearing at the moment of reading **is** the receipt, so there is no version of this where
/// they get the early deletion and not the timing.
Future<void> _burnReceiptSettings(BuildContext context, NightdropCore core) async {
  final l10n = AppLocalizations.of(context)!;
  final on = await core.burnReceiptsEnabled();
  if (!context.mounted) return;
  final theme = Theme.of(context);
  final turnOn = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.burnReceiptsTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.burnReceiptsBody),
            const SizedBox(height: 16),
            Text(
              l10n.burnReceiptsLimit,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(!on),
          child: Text(on ? l10n.turnOff : l10n.turnOn),
        ),
      ],
    ),
  );
  if (turnOn == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  await core.setBurnReceipts(turnOn);
  messenger.showSnackBar(SnackBar(
    content: Text(turnOn ? l10n.burnReceiptsOn : l10n.burnReceiptsOff),
  ));
}

/// A dismissible banner shown while this device's onion descriptor is still publishing to Tor
/// (the ~1–3 min after launch), during which peers can't reach us to pair. Polls [onionReady]
/// and disappears once we're reachable.
class _OnionBanner extends StatefulWidget {
  const _OnionBanner({required this.core});

  final NightdropCore core;

  @override
  State<_OnionBanner> createState() => _OnionBannerState();
}

class _OnionBannerState extends State<_OnionBanner> {
  bool _ready = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  Future<void> _check() async {
    final ready = await widget.core.onionReady();
    if (!mounted) return;
    if (ready != _ready) setState(() => _ready = ready);
    if (ready) _timer?.cancel(); // reachable — no need to keep polling
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.publishingAddressTor,
                style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Warns when one of the user's **own** advertised extra relays (#17) has stopped answering —
/// i.e. a self-hosted relay is down, so contacts' offline mail routed through it may be stuck.
/// Nudges the user to add a backup relay so delivery stays redundant. Polls on the same cadence
/// as the onion banner (relay health is refreshed by the background poller).
/// "Android stopped background delivery" — shown when the SYSTEM ended the foreground service,
/// never when the user did.
///
/// Exists because the failure it reports is invisible by construction: the app stops receiving,
/// the notification disappears among fifty others, and nothing else changes. On 2026-08-09 the
/// service was ended by Android's six-hour `dataSync` budget at 03:08 and the phone received
/// nothing for the next five hours — discovered from `dumpsys batterystats`, which is not
/// somewhere a user is going to look. The service type was changed to one with no such budget, so
/// this should stay hidden; it is here so that if some future budget ends the service anyway, the
/// user is told instead of quietly going offline.
class _BackgroundStoppedBanner extends StatefulWidget {
  const _BackgroundStoppedBanner();

  @override
  State<_BackgroundStoppedBanner> createState() => _BackgroundStoppedBannerState();
}

class _BackgroundStoppedBannerState extends State<_BackgroundStoppedBanner> {
  bool _stopped = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // Reading it clears it, so this shows once per occurrence rather than until dismissed.
    final stopped = await BackgroundDelivery.takeStoppedBySystem();
    if (!mounted || !stopped) return;
    setState(() => _stopped = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_stopped) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.sync_problem, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.backgroundStoppedBySystem,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 12.5),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: scheme.onErrorContainer),
              onPressed: () => setState(() => _stopped = false),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelayHealthBanner extends StatefulWidget {
  const _RelayHealthBanner({required this.core});

  final NightdropCore core;

  @override
  State<_RelayHealthBanner> createState() => _RelayHealthBannerState();
}

class _RelayHealthBannerState extends State<_RelayHealthBanner> {
  List<RelayHealth> _health = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _check());
  }

  Future<void> _check() async {
    final health = await widget.core.relayHealth();
    if (!mounted) return;
    setState(() => _health = health);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final offline = _health.where((h) => !h.reachable).toList();
    if (offline.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final hasBackup = _health.any((h) => h.reachable);
    final names = offline.map((h) => h.address).join(', ');
    final message = offline.length == 1
        ? l10n.relayOfflineOne(names)
        : l10n.relayOfflineMany(names);
    final advice = hasBackup
        ? l10n.relayAdviceHasBackup
        : l10n.relayAdviceNoBackup;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.wifi_off, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$message$advice',
                style:
                    TextStyle(color: scheme.onErrorContainer, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _editRelays(context, widget.core),
              child: Text(l10n.relaysShort),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupReminderBanner extends StatefulWidget {
  const _BackupReminderBanner({required this.core});

  final NightdropCore core;

  @override
  State<_BackupReminderBanner> createState() => _BackupReminderBannerState();
}

class _BackupReminderBannerState extends State<_BackupReminderBanner> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final show = await widget.core.shouldSuggestBackup();
    if (mounted) setState(() => _show = show);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.backup_outlined,
                size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.backupReminderBody,
                style:
                    TextStyle(color: scheme.onSecondaryContainer, fontSize: 12.5),
              ),
            ),
            TextButton(
              onPressed: () async {
                await widget.core.snoozeBackupReminder();
                if (mounted) setState(() => _show = false);
              },
              child: Text(l10n.later),
            ),
            FilledButton(
              onPressed: () async {
                await createAndSaveBackup(context, widget.core);
                // recordBackupDone (on success) makes this false; re-check either way.
                await _refresh();
              },
              child: Text(l10n.backUp),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirm and delete a chat from the list (long-press on touch, right-click on desktop). The
/// deletion is optimistic — the chat disappears at once while the peer is signalled in the
/// background — so we stay on the list, no navigation needed.
Future<void> _confirmDeleteChat(
    BuildContext context, NightdropCore core, Contact contact) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deleteThisChat),
      content: Text(l10n.deleteChatBody(contact.theirName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.deleteChat),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await core.deleteChat(contact.id);
}

/// Opt-in Android background delivery (§11.8, #13): a switch that, when on, runs a foreground
/// service (persistent notification) so messages keep arriving while the app is backgrounded.
Future<void> _backgroundDeliverySettings(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final enabled = await BackgroundDelivery.isEnabled();
  if (!context.mounted) return;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      var value = enabled;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.backgroundDelivery),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.backgroundDeliveryBody),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.enabled),
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, value),
              child: Text(l10n.save),
            ),
          ],
        ),
      );
    },
  );
  if (result == null) return;
  if (result) {
    final granted = await BackgroundDelivery.ensurePermission();
    if (!granted) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.notificationPermissionRequired),
      ));
      return;
    }
  }
  await BackgroundDelivery.setEnabled(result);
  messenger.showSnackBar(SnackBar(
    content: Text(result ? l10n.backgroundDeliveryOn : l10n.backgroundDeliveryOff),
  ));
}

/// Edit our advertised **extra** relay set (#17). These are announced to contacts so their
/// offline mail is fanned out to them in addition to the shared primary relay — more paths to
/// reach us if one relay is down or censored. One relay address per line.
Future<void> _editRelays(BuildContext context, NightdropCore core) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final current = await core.myRelays();
  if (!context.mounted) return;
  final controller = TextEditingController(text: current.join('\n'));
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // scrollable keeps the description + text field in a scroll view and the Cancel/Save
      // actions fixed below, so on mobile the keyboard can't push the field under the buttons
      // or overflow the dialog.
      scrollable: true,
      title: Text(l10n.myRelays),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.editRelaysBody),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'abcd…xyz.onion\n10.0.0.5:9080',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  if (saved != true) return;
  final relays = controller.text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  try {
    await core.setMyRelays(relays);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.couldNotSaveRelays(e.toString()))));
    return;
  }
  messenger.showSnackBar(SnackBar(
    content: Text(relays.isEmpty
        ? l10n.usingDefaultRelayOnly
        : l10n.advertisingExtraRelays(relays.length)),
  ));
}

/// Enable an opt-in server backup (§7c): store an encrypted copy on the relay and force the
/// "record this password" + exact-expiry acknowledgment the invariant requires.
Future<void> _createServerBackup(BuildContext context, NightdropCore core) async {
  final l10n = AppLocalizations.of(context)!;
  final full = await pickBackupMode(context);
  if (full == null || !context.mounted) return;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final ServerBackup info;
  try {
    // Argon2 derivation + the Tor upload take a moment — show a loader.
    info = await runWithLoader(
      context,
      l10n.backingUpToServer,
      () => core.createServerBackup(24, full),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.couldNotBackUpToServer(e.toString()))),
    );
    return;
  }
  if (!context.mounted) return;
  final expiry = info.expiresAt.toLocal();
  final expiryText =
      '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')} '
      '${expiry.hour.toString().padLeft(2, '0')}:${expiry.minute.toString().padLeft(2, '0')}';
  // Same confirm-by-retype gate as the file backup (§7). The server copy is already stored, so this
  // can't un-store it — but it forces the user to actually record the password while it's still on
  // screen, before it's gone for good.
  await acknowledgeRecoveryPassword(
    context,
    password: info.password,
    intro: l10n.serverBackupIntro,
    footer: l10n.serverBackupFooter(expiryText),
  );
  await core.recordBackupDone(); // stop the backup-reminder nudge
}

/// Show this device's own anonymous identity (the id others key you by).
/// "My name" — the name new chats start with. Existing chats that still use the previous
/// preferred name (or the default) follow the change; a chat renamed by hand keeps its own name.
Future<void> _editMyName(BuildContext context, NightdropCore core) async {
  final l10n = AppLocalizations.of(context)!;
  final previous = ProfileName.current.value;
  final controller = TextEditingController(text: previous == kDefaultName ? '' : previous);
  final entered = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(l10n.myNameMenu),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.myNameBody),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  if (entered == null) return;
  final name = entered.trim().isEmpty ? kDefaultName : entered.trim();
  await ProfileName.set(name);
  for (final c in core.contacts) {
    final followsSetting = c.myName == kDefaultName || (previous.isNotEmpty && c.myName == previous);
    if (followsSetting && c.myName != name) core.setMyNameInChat(c.id, name);
  }
}

Future<void> _showMyIdentity(BuildContext context, NightdropCore core) async {
  final l10n = AppLocalizations.of(context)!;
  final id = core.identity?.id ?? '(none)';
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.myIdentity),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.myIdentityBody),
          const SizedBox(height: 12),
          SelectableText(id, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(l10n.close)),
      ],
    ),
  );
}

/// Minimal about dialog: icon, app name, version, copyright + license. Deliberately a custom
/// dialog rather than Flutter's `showAboutDialog`, which auto-adds a "View licenses" button (the
/// full bundled-package license list) and a "Powered by Flutter" footer we don't want here.
void _showAbout(BuildContext context) {
  // The number after "+" in the pubspec version never changes between our builds, so it says
  // nothing about which build this is. Preview builds pass their real build number instead; it
  // matches the number in the downloaded file's name.
  const build = String.fromEnvironment('CYBERDOG_BUILD');
  final parts = kAppVersion.split('+');
  final number = build.isNotEmpty ? build : (parts.length == 2 ? parts[1] : '');
  final version = number.isEmpty
      ? parts[0]
      : '${parts[0]} (${AppLocale.pick('build', 'сборка')} $number)';
  final l10n = AppLocalizations.of(context)!;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset('assets/icons/icon-512.png', width: 56, height: 56),
          const SizedBox(width: 16),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppConfig.current.appName,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text('${AppLocale.pick('Version', 'Версия')} $version',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                const Text('© 2026 CyberDog'),
                const Text('AGPL-3.0-or-later'),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(l10n.close)),
      ],
    ),
  );
}

/// Confirm, then disconnect from Tor and close the app (issue #15). The identity is untouched.
Future<void> _confirmExit(BuildContext context, NightdropCore core) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.exitTitle),
      content: Text(l10n.exitBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.exitConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  // The shutdown waits for Tor to let go — a few seconds at worst — so say what is happening
  // rather than leave a frozen-looking screen. Not dismissible: there is nothing to go back to.
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator()),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.exitDisconnecting)),
          ],
        ),
      ),
    ),
  ));
  await core.exitApp();
}

/// Confirm and perform a logout / identity termination, spelling out the consequences.
Future<void> _confirmLogout(BuildContext context, NightdropCore core) async {
  // Grab the app-level messenger up front: the home screen is about to be replaced by onboarding,
  // but the root ScaffoldMessenger survives, so a follow-up notice still shows (and capturing it
  // before any await avoids using a stale BuildContext across the async gap).
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.logoutTitle),
      content: Text(l10n.logoutBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.logoutDelete),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  // _Root routes back to onboarding; logout returns how many contacts couldn't be told the chat
  // was deleted (§1.3) so we can be honest that a few peers may still message a dead identity.
  final notNotified = await core.logout();
  if (notNotified > 0) {
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.logoutNotNotified(notNotified)),
    ));
  }
}

/// An inbound chat request: approve to start chatting, or decline to drop it (§5).
/// Approval is sent over Tor and can take a few seconds, so the tile shows progress and
/// disables its buttons while it is in flight (no accidental double-approvals).
class _RequestTile extends StatefulWidget {
  const _RequestTile({required this.request, required this.core});

  final Contact request;
  final NightdropCore core;

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  bool _busy = false;

  Future<void> _decide(bool accept) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await widget.core.authorize(widget.request.id, accept);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(accept
                  ? l10n.couldNotApprove(cleanCoreError(e))
                  : l10n.couldNotDecline(cleanCoreError(e)))),
        );
      }
    }
    // On success the tile disappears (it's no longer a pending request); no need to reset.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.secondaryContainer,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1)),
        title: Text(l10n.chatRequest),
        subtitle: Text(
          _busy
              ? l10n.approvingOverTor
              : l10n.requestFrom(shortId(widget.request.id)),
        ),
        trailing: _busy
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.decline,
                    icon: const Icon(Icons.close),
                    onPressed: () => _decide(false),
                  ),
                  IconButton(
                    tooltip: l10n.approve,
                    icon: const Icon(Icons.check),
                    onPressed: () => _decide(true),
                  ),
                ],
              ),
      ),
    );
  }
}
