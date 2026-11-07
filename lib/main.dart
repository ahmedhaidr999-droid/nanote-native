import 'dart:async';

import 'package:flutter/material.dart';

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

  // Local-first storage: one Drift (SQLite) database for all tables. On the
  // very first launch this also performs the one-time migration of legacy
  // Isar data (v2.x app) into Drift — see persistence/migration/.
  await AppDb.init();

  // Settings + language before the first frame.
  await SettingsController.I.load();

  // Warm up pen/palette memory.
  unawaited(ToolController.I.ensureLoaded());

  // Purge trash older than the 30-day retention.
  unawaited(LibraryRepository.I.purgeExpiredTrash());

  runApp(const NanoteApp());
}

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
