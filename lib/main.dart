import 'dart:async';
import 'dart:convert' show base64Decode;
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
    // Embedded 3-page test PDF (reportlab, real text) — no external
    // storage needed.
    const pdfB64 =
        'JVBERi0xLjMKJZOMi54gUmVwb3J0TGFiIEdlbmVyYXRlZCBQREYgZG9jdW1lbnQgKG9wZW5zb3VyY2UpCjEgMCBvYmoKPDwKL0YxIDIgMCBSIC9GMiAzIDAgUgo+PgplbmRvYmoKMiAwIG9iago8PAovQmFzZUZvbnQgL0hlbHZldGljYSAvRW5jb2RpbmcgL1dpbkFuc2lFbmNvZGluZyAvTmFtZSAvRjEgL1N1YnR5cGUgL1R5cGUxIC9UeXBlIC9Gb250Cj4+CmVuZG9iagozIDAgb2JqCjw8Ci9CYXNlRm9udCAvVGltZXMtUm9tYW4gL0VuY29kaW5nIC9XaW5BbnNpRW5jb2RpbmcgL05hbWUgL0YyIC9TdWJ0eXBlIC9UeXBlMSAvVHlwZSAvRm9udAo+PgplbmRvYmoKNCAwIG9iago8PAovQ29udGVudHMgMTAgMCBSIC9NZWRpYUJveCBbIDAgMCA1OTUuMjc1NiA4NDEuODg5OCBdIC9QYXJlbnQgOSAwIFIgL1Jlc291cmNlcyA8PAovRm9udCAxIDAgUiAvUHJvY1NldCBbIC9QREYgL1RleHQgL0ltYWdlQiAvSW1hZ2VDIC9JbWFnZUkgXQo+PiAvUm90YXRlIDAgL1RyYW5zIDw8Cgo+PiAKICAvVHlwZSAvUGFnZQo+PgplbmRvYmoKNSAwIG9iago8PAovQ29udGVudHMgMTEgMCBSIC9NZWRpYUJveCBbIDAgMCA1OTUuMjc1NiA4NDEuODg5OCBdIC9QYXJlbnQgOSAwIFIgL1Jlc291cmNlcyA8PAovRm9udCAxIDAgUiAvUHJvY1NldCBbIC9QREYgL1RleHQgL0ltYWdlQiAvSW1hZ2VDIC9JbWFnZUkgXQo+PiAvUm90YXRlIDAgL1RyYW5zIDw8Cgo+PiAKICAvVHlwZSAvUGFnZQo+PgplbmRvYmoKNiAwIG9iago8PAovQ29udGVudHMgMTIgMCBSIC9NZWRpYUJveCBbIDAgMCA1OTUuMjc1NiA4NDEuODg5OCBdIC9QYXJlbnQgOSAwIFIgL1Jlc291cmNlcyA8PAovRm9udCAxIDAgUiAvUHJvY1NldCBbIC9QREYgL1RleHQgL0ltYWdlQiAvSW1hZ2VDIC9JbWFnZUkgXQo+PiAvUm90YXRlIDAgL1RyYW5zIDw8Cgo+PiAKICAvVHlwZSAvUGFnZQo+PgplbmRvYmoKNyAwIG9iago8PAovUGFnZU1vZGUgL1VzZU5vbmUgL1BhZ2VzIDkgMCBSIC9UeXBlIC9DYXRhbG9nCj4+CmVuZG9iago4IDAgb2JqCjw8Ci9BdXRob3IgKGFub255bW91cykgL0NyZWF0aW9uRGF0ZSAoRDoyMDI2MTEwNjE3Mjg1OSswMCcwMCcpIC9DcmVhdG9yIChhbm9ueW1vdXMpIC9LZXl3b3JkcyAoKSAvTW9kRGF0ZSAoRDoyMDI2MTEwNjE3Mjg1OSswMCcwMCcpIC9Qcm9kdWNlciAoUmVwb3J0TGFiIFBERiBMaWJyYXJ5IC0gXChvcGVuc291cmNlXCkpIAogIC9TdWJqZWN0ICh1bnNwZWNpZmllZCkgL1RpdGxlICh1bnRpdGxlZCkgL1RyYXBwZWQgL0ZhbHNlCj4+CmVuZG9iago5IDAgb2JqCjw8Ci9Db3VudCAzIC9LaWRzIFsgNCAwIFIgNSAwIFIgNiAwIFIgXSAvVHlwZSAvUGFnZXMKPj4KZW5kb2JqCjEwIDAgb2JqCjw8Ci9GaWx0ZXIgWyAvQVNDSUk4NURlY29kZSAvRmxhdGVEZWNvZGUgXSAvTGVuZ3RoIDIxNAo+PgpzdHJlYW0KR2FzMyw1bWtJXyYtXkZvVnRgby07NENJIkVATCtvS2paTUVlJE1oYlArJjFJNGhcK1hcLkJNcExBQzxcNW9iVzxSayVsQFouS1xOIkxKOydVRC5nKiVBIUZtUEJUSF0rSEwjL0wkPjEvIWI7STwkXzJSYz45J2FfMWVNZ1hlI1VkMT5fSWVBblZRKD8tcWtCIzVUQSlHIz41K1NAYHAyIk0uUUpqNCpbVjFBckckPV11KHRATkUwLjVGYlBwbUZjOFAnLStvTXVJNydBYSE0WjMjKVp+PmVuZHN0cmVhbQplbmRvYmoKMTEgMCBvYmoKPDwKL0ZpbHRlciBbIC9BU0NJSTg1RGVjb2RlIC9GbGF0ZURlY29kZSBdIC9MZW5ndGggMjEyCj4+CnN0cmVhbQpHYXMzLDlhXGBrJi1fIipWZyhqVzs0Q0J1RUBMK29LalpNRWUrRDY7Mithb3JIPUlcMCtZa19bb0FHJCJFPlVIS1RuIyM8QFM4czc9OTRSUSQub18sMllscWxtdSE+Uk1kbkdwbCg0NFNGOVBdOlNHUUtzMypKK08nXXQ6TT0uT3VTOC4tTyEnPk5GZFJrZ0ZgMi42ImQ3S1lHVWI6KjdFVjpjNTxHY2wrKm8/YVlSX2JnNDtYZ0dbaixzaFtiRVVnXSxvWDVQJylvQ1k6XEducjp+PmVuZHN0cmVhbQplbmRvYmoKMTIgMCBvYmoKPDwKL0ZpbHRlciBbIC9BU0NJSTg1RGVjb2RlIC9GbGF0ZURlY29kZSBdIC9MZW5ndGggMjE0Cj4+CnN0cmVhbQpHYXMzLDVuOEsjJi1eRURWdGBvLUpKPHFQUVI5OmFAOkNsZFRnNkgmZkc3PVtEYWUvQChjMDlFMS1iU3ErUyVuPlNQKj9iMSNFVioocGpFO18/PXQ5JTFXPTdhaCZhVk9bVGtcYCs3MURObDtANGp1RSlaRGZJVVs6YWt1TzllU1I5SUdrQ1VhIVomRlUhUWUhImA2TTsrIlstMExiNk8yLV5KP3RtLDQ2XFFtbUVwRVlhOkgyLU9tXjpfZT9aZ1RnWyU5Q0BiW201S15WIVAsIW8qPH4+ZW5kc3RyZWFtCmVuZG9iagp4cmVmCjAgMTMKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDYxIDAwMDAwIG4gCjAwMDAwMDAxMDIgMDAwMDAgbiAKMDAwMDAwMDIwOSAwMDAwMCBuIAowMDAwMDAwMzE4IDAwMDAwIG4gCjAwMDAwMDA1MjIgMDAwMDAgbiAKMDAwMDAwMDcyNiAwMDAwMCBuIAowMDAwMDAwOTMwIDAwMDAwIG4gCjAwMDAwMDA5OTggMDAwMDAgbiAKMDAwMDAwMTI1OSAwMDAwMCBuIAowMDAwMDAxMzMwIDAwMDAwIG4gCjAwMDAwMDE2MzUgMDAwMDAgbiAKMDAwMDAwMTkzOCAwMDAwMCBuIAp0cmFpbGVyCjw8Ci9JRCAKWzxmNjI1YjkzNmU3ODkzOTY1MDU4YTdiMWM1ZmU4NmQ2YT48ZjYyNWI5MzZlNzg5Mzk2NTA1OGE3YjFjNWZlODZkNmE+XQolIFJlcG9ydExhYiBnZW5lcmF0ZWQgUERGIGRvY3VtZW50IC0tIGRpZ2VzdCAob3BlbnNvdXJjZSkKCi9JbmZvIDggMCBSCi9Sb290IDcgMCBSCi9TaXplIDEzCj4+CnN0YXJ0eHJlZgoyMjQzCiUlRU9GCg==';
    final tmpDir = Directory.systemTemp;
    final f = File('${tmpDir.path}/diag_test.pdf');
    await f.writeAsBytes(base64Decode(pdfB64), flush: true);
    debugPrint('DIAG: wrote ${f.path} (${await f.length()} bytes)');
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
