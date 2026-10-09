import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app.dart';
import '../../theme/cyberdog.dart';
import 'verify_screen.dart';

/// Who you are talking to, on one screen: their name and rank, the fact that the chat is
/// encrypted, whether you have checked them, and the button to do so.
class ContactProfileScreen extends StatelessWidget {
  const ContactProfileScreen({super.key, required this.contactId});

  final String contactId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final contact =
        NightdropScope.of(context).contacts.where((c) => c.id == contactId).firstOrNull;
    if (contact == null) {
      return Scaffold(appBar: AppBar(title: Text(l10n.profileTitle)));
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(child: CyberDogAvatar(seed: contact.id, label: contact.headerName, radius: 40)),
          const SizedBox(height: 16),
          Text(
            contact.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              UserRankBadge(rank: contact.rank),
              if (contact.identityTag.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  contact.identityTag,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          _Fact(icon: Icons.lock_outline, text: l10n.encryptionOn),
          _Fact(
            icon: contact.verified ? Icons.verified_user : Icons.shield_outlined,
            text: contact.verified ? l10n.contactVerified : l10n.contactNotVerified,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VerifyScreen(contactId: contact.id, name: contact.theirName),
              ),
            ),
            icon: const Icon(Icons.qr_code_2),
            label: Text(l10n.verifyContact),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CyberDog.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CyberDog.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.secondary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
