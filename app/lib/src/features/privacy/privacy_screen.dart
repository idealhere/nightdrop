import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/privacy_prefs.dart';

/// The short list of privacy choices a person actually makes. Everything else the app does on
/// its own and is not offered as a switch.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyMenu)),
      body: ListView(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: PrivacyPrefs.hideIncomingPhotos,
            builder: (context, on, _) => SwitchListTile(
              title: Text(l10n.hidePhotosTitle),
              subtitle: Text(l10n.hidePhotosBody),
              value: on,
              onChanged: PrivacyPrefs.setHideIncomingPhotos,
            ),
          ),
        ],
      ),
    );
  }
}
