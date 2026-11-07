import 'dart:async';

import 'package:meta/meta.dart';
import 'package:universal_platform/universal_platform.dart';

/// Test seam: when set, [hasPdfSupport] returns this instead of probing the
/// host platform — lets the app's pipeline tests drive the real controller
/// against a fake platform implementation on any host.
@visibleForTesting
bool? debugOverrideSupported;

Future<bool> hasPdfSupport() async {
  if (debugOverrideSupported != null) return debugOverrideSupported!;
  if (UniversalPlatform.isMacOS ||
      UniversalPlatform.isIOS ||
      UniversalPlatform.isWindows ||
      UniversalPlatform.isWeb ||
      UniversalPlatform.isAndroid) {
    return true;
  }
  return false;
}
