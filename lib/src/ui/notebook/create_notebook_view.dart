import 'package:flutter/material.dart';

import '../../controllers/library_controller.dart';
import '../../i18n/strings.dart';
import '../library/library_dialogs.dart';

/// Full-screen notebook creation flow ('/create'). Same fields as the quick
/// sheet (reuses [NotebookFormFields]); pops with the created notebook.
class CreateNotebookView extends StatefulWidget {
  const CreateNotebookView({super.key, this.folderId});

  final int? folderId;

  @override
  State<CreateNotebookView> createState() => _CreateNotebookViewState();
}

class _CreateNotebookViewState extends State<CreateNotebookView> {
  final GlobalKey<NotebookFormFieldsState> _formKey =
      GlobalKey<NotebookFormFieldsState>();

  bool _valid = false;
  int? _folderId;
  bool _resolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    _folderId = widget.folderId ??
        (args is int ? args : null) ??
        LibraryController.I.currentFolderId;
  }

  Future<void> _create() async {
    final state = _formKey.currentState;
    if (state == null || !state.canCreate) return;
    final nb = await LibraryController.I.createNotebook(
      title: state.title,
      coverId: state.coverId,
      coverImagePath: state.coverImagePath,
      folderId: _folderId ?? LibraryController.I.currentFolderId,
      template: state.template,
      pageSize: state.pageSize,
      paperColor: state.paperColor,
    );
    if (mounted) Navigator.pop(context, nb);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('newNotebook')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.t('cancel')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          NotebookFormFields(
            key: _formKey,
            onValidityChanged: (v) => setState(() => _valid = v),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _valid ? _create : null,
              child: Text(S.t('create')),
            ),
          ),
        ),
      ),
    );
  }
}
