import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/privacy_prefs.dart';

/// The short list of privacy choices a person actually makes, plus the things the app simply
/// never does. A row is a switch only when there is something to switch.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static String _detailLabel(AppLocalizations l10n, NotificationDetail level) => switch (level) {
        NotificationDetail.full => l10n.notifyFull,
        NotificationDetail.private => l10n.notifyPrivate,
        NotificationDetail.hidden => l10n.notifyHidden,
      };

  Future<void> _pickDetail(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showModalBottomSheet<NotificationDetail>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n.notifyQuestion)),
            for (final level in NotificationDetail.values)
              ListTile(
                title: Text(_detailLabel(l10n, level)),
                trailing: PrivacyPrefs.notificationDetail.value == level
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, level),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await PrivacyPrefs.setNotificationDetail(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyMenu)),
      body: ListView(
        children: [
          ListTile(
            title: Text(l10n.disappearingMessages),
            subtitle: Text(l10n.privacyDisappearingHint),
          ),
          ValueListenableBuilder<NotificationDetail>(
            valueListenable: PrivacyPrefs.notificationDetail,
            builder: (context, level, _) => ListTile(
              title: Text(l10n.notifyTitle),
              subtitle: Text(_detailLabel(l10n, level)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickDetail(context),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: PrivacyPrefs.hideIncomingPhotos,
            builder: (context, on, _) => SwitchListTile(
              title: Text(l10n.hidePhotosTitle),
              subtitle: Text(l10n.hidePhotosBody),
              value: on,
              onChanged: PrivacyPrefs.setHideIncomingPhotos,
            ),
          ),
          ListTile(
            title: Text(l10n.activityTitle),
            subtitle: Text(l10n.activityBody),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.activityNotSent, style: TextStyle(color: scheme.secondary)),
                const SizedBox(width: 6),
                Icon(Icons.check, size: 18, color: scheme.secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
