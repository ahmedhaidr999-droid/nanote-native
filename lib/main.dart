import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'src/controllers/library_controller.dart';
import 'src/controllers/settings_controller.dart';
import 'src/controllers/tool_controller.dart';
import 'src/i18n/strings.dart';
import 'src/persistence/app_db.dart';
import 'src/persistence/library_repository.dart';
import 'src/theme/nanote_theme.dart';
import 'src/ui/library/library_view.dart';
import 'src/ui/notebook/create_notebook_view.dart';
import 'src/ui/settings/pen_manager_view.dart';
import 'src/ui/settings/settings_view.dart';
import 'src/ui/settings/sticker_manager_view.dart';
import 'src/workspace/document_workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // DIAGNOSTIC BUILD (temporary — not for release): surface every
  // framework error into logcat with full stack traces.
  FlutterError.onError = (details) {
    debugPrint('DIAG-FLUTTER-ERROR: ${details.exception}');
    debugPrint('DIAG-STACK: ${details.stack}');
  };
  PlatformDispatcher.instance.onError = (e, s) {
    debugPrint('DIAG-ZONE-ERROR: $e');
    debugPrint('DIAG-STACK: $s');
    return true;
  };

  // Local-first storage: one Isar instance for all schemas.
  await AppDb.init();

  // Settings + language before the first frame.
  await SettingsController.I.load();

  // Warm up pen/palette memory.
  unawaited(ToolController.I.ensureLoaded());

  // Purge trash older than the 30-day retention.
  unawaited(LibraryRepository.I.purgeExpiredTrash());

  // DIAGNOSTIC BUILD: auto-import /sdcard/Download/test.pdf as a PDF
  // notebook on a fresh install and open the workspace right away (the
  // "gray screen on any PDF" reproduction path).
  unawaited(_diagnosticAutoImport());

  runApp(const NanoteApp());
}

Future<void> _diagnosticAutoImport() async {
  try {
    await Future<void>.delayed(const Duration(seconds: 3));
    debugPrint('DIAG: auto-import starting');
    var path = '/sdcard/Android/data/com.nanote.native/files/test.pdf';
    var f = File(path);
    if (!await f.exists()) {
      path = '/sdcard/Download/test.pdf';
      f = File(path);
    }
    if (!await f.exists()) {
      debugPrint('DIAG: no test.pdf found — skipping');
      return;
    }
    final controller = LibraryController.I;
    await controller.reload();
    if (controller.notebooks.isNotEmpty) {
      debugPrint('DIAG: notebooks already exist — skipping import');
      return;
    }
    debugPrint('DIAG: importing pdf');
    final nb = await controller.importPdf(f);
    debugPrint('DIAG: imported notebook id=${nb?.id} pages=${nb?.pdfPath}');
    if (nb != null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      debugPrint('DIAG: navigating to workspace');
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        await Navigator.of(ctx).pushNamed('/notebook', arguments: nb.id);
        debugPrint('DIAG: workspace route pushed');
      } else {
        debugPrint('DIAG: no navigator context!');
      }
    }
  } catch (e, s) {
    debugPrint('DIAG-IMPORT-ERROR: $e');
    debugPrint('DIAG-STACK: $s');
  }
}

/// DIAGNOSTIC BUILD: navigator key so the auto-import can open the
/// workspace without UI interaction.
final navigatorKey = GlobalKey<NavigatorState>();

class NanoteApp extends StatelessWidget {
  const NanoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SettingsController.I,
        S.lang,
      ]),
      builder: (context, _) {
        final settings = SettingsController.I.settings;
        final mode = switch (settings.themeMode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        return MaterialApp(
          title: 'Nanote Native',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: NanoteTheme.light(),
          darkTheme: NanoteTheme.dark(),
          themeMode: mode,
          locale: S.isAr ? const Locale('ar') : const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          builder: (context, child) => Directionality(
            textDirection: S.textDirection,
            child: child!,
          ),
          initialRoute: '/',
          onGenerateRoute: (route) {
            switch (route.name) {
              case '/':
                return MaterialPageRoute(
                  builder: (_) => const LibraryView(),
                );
              case '/create':
                final arg = route.arguments;
                return MaterialPageRoute(
                  builder: (_) => CreateNotebookView(
                    folderId: arg is int ? arg : null,
                  ),
                );
              case '/notebook':
                final id = route.arguments;
                if (id is! int) {
                  return MaterialPageRoute(
                    builder: (_) => const LibraryView(),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => DocumentWorkspace(notebookId: id),
                );
              case '/settings':
                return MaterialPageRoute(
                  builder: (_) => const SettingsView(),
                );
              case '/pen':
                return MaterialPageRoute(
                  builder: (_) => const PenManagerView(),
                );
              case '/stickers':
                return MaterialPageRoute(
                  builder: (_) => const StickerManagerView(),
                );
            }
            return null;
          },
        );
      },
    );
  }
}
