#!/usr/bin/env python3
"""Extract the Isar schema constants + closures from the legacy generated
code so the new app can READ the old on-device Isar database during the
one-time v1.0.0 migration. Output: a single standalone Dart library."""
import re
import sys

SRC = [
    ('/home/z/my-project/android-src/lib/src/persistence/library_repository.g.dart',
     ['TabEntity', 'FolderEntity', 'NotebookEntity', 'PageEntity', 'TagEntity', 'RecordingEntity']),
    ('/home/z/my-project/android-src/lib/src/persistence/stroke_repository.g.dart',
     ['StrokeEntity', 'ElementEntity']),
]
OUT = '/home/z/my-project/nanote/lib/src/persistence/migration/isar_legacy.dart'

def top_level_blocks(lines):
    """Yield (start, end) of top-level declarations."""
    start = None
    for i, line in enumerate(lines):
        if start is None:
            if line and not line.startswith((' ', '\t', ')', '}', '/')):
                start = i
        else:
            # top-level decl ends at a line that is exactly '}' or ');'
            if line == '}' or line == ');':
                yield (start, i)
                start = None
    if start is not None:
        yield (start, len(lines) - 1)

header = '''// ---------------------------------------------------------------------------
// LEGACY ISAR SCHEMAS — extracted verbatim from the isar_generator 3.1.0+1
// output of the v2.x codebase. Used ONLY by the one-time migration that
// reads the old on-device Isar database (see migrator.dart). Never used for
// writing; the app's own storage is Drift/SQLite.
// ---------------------------------------------------------------------------
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, unused_element, type_annotate_public_apis
import 'package:isar/isar.dart';

import '../entities.dart';

'''

parts = [header]
for path, names in SRC:
    with open(path) as f:
        lines = f.read().split('\n')
    blocks = list(top_level_blocks(lines))
    wanted = []
    for (s, e) in blocks:
        text = '\n'.join(lines[s:e + 1])
        for n in names:
            camel = n[0].lower() + n[1:]
            if text.startswith(f'const {n}Schema = CollectionSchema(') or \
               re.match(rf'^[\w <>,\?\(\)]* _{camel}\w*(<[^>]*>)?\(', text):
                wanted.append(text)
                break
    parts.append('\n\n'.join(wanted) + '\n')

out = '\n'.join(parts)
with open(OUT, 'w') as f:
    f.write(out)

# sanity report
n_schemas = out.count('= CollectionSchema(')
n_funcs = len(re.findall(r'^[\w <>,\?\(\)]* _\w+\(', out, re.M))
print(f'wrote {OUT}: {len(out.splitlines())} lines, {n_schemas} schemas, {n_funcs} closures')
for n in ['TabEntity','FolderEntity','NotebookEntity','PageEntity','TagEntity','RecordingEntity','StrokeEntity','ElementEntity']:
    has_schema = f'const {n}Schema = CollectionSchema(' in out
    print(f'  {n}: schema={has_schema}')
