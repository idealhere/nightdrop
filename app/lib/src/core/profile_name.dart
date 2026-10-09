import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// The name the user wants to go by. Names are per-chat in the core; this remembers one preferred
/// name on the device so new chats start with it instead of the default. Empty means "not set".
class ProfileName {
  ProfileName._();

  static final ValueNotifier<String> current = ValueNotifier<String>('');

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/profile_name');

  /// Restore the saved name. Any failure keeps it unset: a name must never block startup.
  static Future<void> load() async {
    try {
      current.value = (await (await _file()).readAsString()).trim();
    } catch (_) {}
  }

  static Future<void> set(String name) async {
    current.value = name.trim();
    try {
      await (await _file()).writeAsString(current.value);
    } catch (_) {}
  }
}
