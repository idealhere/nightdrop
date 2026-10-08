import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../l10n/app_localizations.dart';
import '../../app.dart';

/// The user's standing address: a QR code and a link that do not expire. Unlike a one-time
/// invite it can be posted or passed on, so what it leads to is a request, not a chat.
class MyAddressScreen extends StatefulWidget {
  const MyAddressScreen({super.key});

  @override
  State<MyAddressScreen> createState() => _MyAddressScreenState();
}

class _MyAddressScreenState extends State<MyAddressScreen> {
  Future<String>? _address;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _address ??= NightdropScope.of(context).myAddress();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myAddressTitle)),
      body: FutureBuilder<String>(
        future: _address,
        builder: (context, snapshot) {
          final address = snapshot.data;
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.myAddressFailed, textAlign: TextAlign.center),
              ),
            );
          }
          if (address == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l10n.myAddressIntro, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: address, size: 240),
                ),
              ),
              const SizedBox(height: 20),
              SelectableText(
                address,
                key: const ValueKey('my-address'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.icon(
                  key: const ValueKey('my-address-copy'),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(l10n.myAddressCopy),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: address));
                    messenger.showSnackBar(SnackBar(content: Text(l10n.textCopied)));
                  },
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.myAddressWarning,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          );
        },
      ),
    );
  }
}
