import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's process, as distinct from its screen. Android only has anything to say here; on
/// desktop the window *is* the process.
///
/// See `MainActivity` for why the Flutter engine can outlive the screen at all.
class AppProcess {
  AppProcess._();

  static const _channel = MethodChannel('app.nightdrop/process');

  static bool get _android => !kIsWeb && io.Platform.isAndroid;

  /// Whether the engine — and with it the Tor core and its notifications — should keep running
  /// after the screen is closed (swiped away). True exactly while background delivery is on.
  static Future<void> setKeepAlive(bool keep) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('setKeepAlive', keep);
    } catch (_) {
      // No channel (tests): nothing outlives anything there.
    }
  }

  /// End the app (issue #15). The caller must already have shut the core down — this does not
  /// wait for anything, it only closes the task and ends the process.
  static Future<void> exit() async {
    if (_android) {
      try {
        await _channel.invokeMethod<void>('exit');
        return;
      } catch (_) {
        // Fall through: better to end the process from here than to leave it running.
      }
    }
    if (!kIsWeb) exitProcess();
  }

  /// Split out so tests can see that Exit reached the end without actually ending the test run.
  @visibleForTesting
  static void Function() exitProcess = () => io.exit(0);
}
