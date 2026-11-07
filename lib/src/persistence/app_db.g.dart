// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $TabsTable extends Tabs with TableInfo<$TabsTable, Tab> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TabsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFF1E6FF2),
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('📓'),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color, emoji, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tabs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tab> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tab map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tab(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $TabsTable createAlias(String alias) {
    return $TabsTable(attachedDatabase, alias);
  }
}

class Tab extends DataClass implements Insertable<Tab> {
  final int id;
  final String name;
  final int color;
  final String emoji;
  final int position;
  const Tab({
    required this.id,
    required this.name,
    required this.color,
    required this.emoji,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    map['emoji'] = Variable<String>(emoji);
    map['position'] = Variable<int>(position);
    return map;
  }

  TabsCompanion toCompanion(bool nullToAbsent) {
    return TabsCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
      emoji: Value(emoji),
      position: Value(position),
    );
  }

  factory Tab.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tab(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
      emoji: serializer.fromJson<String>(json['emoji']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
      'emoji': serializer.toJson<String>(emoji),
      'position': serializer.toJson<int>(position),
    };
  }

  Tab copyWith({
    int? id,
    String? name,
    int? color,
    String? emoji,
    int? position,
  }) => Tab(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    emoji: emoji ?? this.emoji,
    position: position ?? this.position,
  );
  Tab copyWithCompanion(TabsCompanion data) {
    return Tab(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tab(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('emoji: $emoji, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color, emoji, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tab &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.emoji == this.emoji &&
          other.position == this.position);
}

class TabsCompanion extends UpdateCompanion<Tab> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> color;
  final Value<String> emoji;
  final Value<int> position;
  const TabsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.emoji = const Value.absent(),
    this.position = const Value.absent(),
  });
  TabsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.emoji = const Value.absent(),
    this.position = const Value.absent(),
  });
  static Insertable<Tab> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? color,
    Expression<String>? emoji,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (emoji != null) 'emoji': emoji,
      if (position != null) 'position': position,
    });
  }

  TabsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? color,
    Value<String>? emoji,
    Value<int>? position,
  }) {
    return TabsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      emoji: emoji ?? this.emoji,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TabsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('emoji: $emoji, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $FoldersTable extends Folders with TableInfo<$FoldersTable, Folder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFF5A6B85),
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('📁'),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<int> parentId = GeneratedColumn<int>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    color,
    emoji,
    parentId,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Folder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Folder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Folder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_id'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class Folder extends DataClass implements Insertable<Folder> {
  final int id;
  final String name;
  final int color;
  final String emoji;
  final int? parentId;
  final int position;
  const Folder({
    required this.id,
    required this.name,
    required this.color,
    required this.emoji,
    this.parentId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    map['emoji'] = Variable<String>(emoji);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<int>(parentId);
    }
    map['position'] = Variable<int>(position);
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
      emoji: Value(emoji),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      position: Value(position),
    );
  }

  factory Folder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Folder(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
      emoji: serializer.fromJson<String>(json['emoji']),
      parentId: serializer.fromJson<int?>(json['parentId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
      'emoji': serializer.toJson<String>(emoji),
      'parentId': serializer.toJson<int?>(parentId),
      'position': serializer.toJson<int>(position),
    };
  }

  Folder copyWith({
    int? id,
    String? name,
    int? color,
    String? emoji,
    Value<int?> parentId = const Value.absent(),
    int? position,
  }) => Folder(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    emoji: emoji ?? this.emoji,
    parentId: parentId.present ? parentId.value : this.parentId,
    position: position ?? this.position,
  );
  Folder copyWithCompanion(FoldersCompanion data) {
    return Folder(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Folder(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('emoji: $emoji, ')
          ..write('parentId: $parentId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color, emoji, parentId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Folder &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.emoji == this.emoji &&
          other.parentId == this.parentId &&
          other.position == this.position);
}

class FoldersCompanion extends UpdateCompanion<Folder> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> color;
  final Value<String> emoji;
  final Value<int?> parentId;
  final Value<int> position;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.emoji = const Value.absent(),
    this.parentId = const Value.absent(),
    this.position = const Value.absent(),
  });
  FoldersCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.emoji = const Value.absent(),
    this.parentId = const Value.absent(),
    this.position = const Value.absent(),
  });
  static Insertable<Folder> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? color,
    Expression<String>? emoji,
    Expression<int>? parentId,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (emoji != null) 'emoji': emoji,
      if (parentId != null) 'parent_id': parentId,
      if (position != null) 'position': position,
    });
  }

  FoldersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? color,
    Value<String>? emoji,
    Value<int?>? parentId,
    Value<int>? position,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      emoji: emoji ?? this.emoji,
      parentId: parentId ?? this.parentId,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<int>(parentId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('emoji: $emoji, ')
          ..write('parentId: $parentId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $NotebooksTable extends Notebooks
    with TableInfo<$NotebooksTable, Notebook> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotebooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _coverIdMeta = const VerificationMeta(
    'coverId',
  );
  @override
  late final GeneratedColumn<String> coverId = GeneratedColumn<String>(
    'cover_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverImagePathMeta = const VerificationMeta(
    'coverImagePath',
  );
  @override
  late final GeneratedColumn<String> coverImagePath = GeneratedColumn<String>(
    'cover_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  @override
  late final GeneratedColumn<DateTime> openedAt = GeneratedColumn<DateTime>(
    'opened_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateMeta = const VerificationMeta(
    'template',
  );
  @override
  late final GeneratedColumn<int> template = GeneratedColumn<int>(
    'template',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pageSizeMeta = const VerificationMeta(
    'pageSize',
  );
  @override
  late final GeneratedColumn<int> pageSize = GeneratedColumn<int>(
    'page_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _paperColorMeta = const VerificationMeta(
    'paperColor',
  );
  @override
  late final GeneratedColumn<int> paperColor = GeneratedColumn<int>(
    'paper_color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFFFFFFFF),
  );
  static const VerificationMeta _textIndexMeta = const VerificationMeta(
    'textIndex',
  );
  @override
  late final GeneratedColumn<String> textIndex = GeneratedColumn<String>(
    'text_index',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _tagIdsMeta = const VerificationMeta('tagIds');
  @override
  late final GeneratedColumn<String> tagIds = GeneratedColumn<String>(
    'tag_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _pdfPathMeta = const VerificationMeta(
    'pdfPath',
  );
  @override
  late final GeneratedColumn<String> pdfPath = GeneratedColumn<String>(
    'pdf_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    coverId,
    coverImagePath,
    folderId,
    favorite,
    createdAt,
    modifiedAt,
    openedAt,
    template,
    pageSize,
    paperColor,
    textIndex,
    tagIds,
    pdfPath,
    deleted,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notebooks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Notebook> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('cover_id')) {
      context.handle(
        _coverIdMeta,
        coverId.isAcceptableOrUnknown(data['cover_id']!, _coverIdMeta),
      );
    }
    if (data.containsKey('cover_image_path')) {
      context.handle(
        _coverImagePathMeta,
        coverImagePath.isAcceptableOrUnknown(
          data['cover_image_path']!,
          _coverImagePathMeta,
        ),
      );
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('opened_at')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['opened_at']!, _openedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_openedAtMeta);
    }
    if (data.containsKey('template')) {
      context.handle(
        _templateMeta,
        template.isAcceptableOrUnknown(data['template']!, _templateMeta),
      );
    }
    if (data.containsKey('page_size')) {
      context.handle(
        _pageSizeMeta,
        pageSize.isAcceptableOrUnknown(data['page_size']!, _pageSizeMeta),
      );
    }
    if (data.containsKey('paper_color')) {
      context.handle(
        _paperColorMeta,
        paperColor.isAcceptableOrUnknown(data['paper_color']!, _paperColorMeta),
      );
    }
    if (data.containsKey('text_index')) {
      context.handle(
        _textIndexMeta,
        textIndex.isAcceptableOrUnknown(data['text_index']!, _textIndexMeta),
      );
    }
    if (data.containsKey('tag_ids')) {
      context.handle(
        _tagIdsMeta,
        tagIds.isAcceptableOrUnknown(data['tag_ids']!, _tagIdsMeta),
      );
    }
    if (data.containsKey('pdf_path')) {
      context.handle(
        _pdfPathMeta,
        pdfPath.isAcceptableOrUnknown(data['pdf_path']!, _pdfPathMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Notebook map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Notebook(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      coverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_id'],
      ),
      coverImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_image_path'],
      ),
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}folder_id'],
      ),
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_at'],
      )!,
      template: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}template'],
      )!,
      pageSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_size'],
      )!,
      paperColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paper_color'],
      )!,
      textIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_index'],
      )!,
      tagIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_ids'],
      )!,
      pdfPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pdf_path'],
      ),
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $NotebooksTable createAlias(String alias) {
    return $NotebooksTable(attachedDatabase, alias);
  }
}

class Notebook extends DataClass implements Insertable<Notebook> {
  final int id;
  final String title;
  final String? coverId;
  final String? coverImagePath;
  final int? folderId;
  final bool favorite;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime openedAt;
  final int template;
  final int pageSize;
  final int paperColor;
  final String textIndex;

  /// JSON-encoded List<int> (kept as text for debuggability + easy backup
  /// round-tripping).
  final String tagIds;
  final String? pdfPath;
  final bool deleted;
  final DateTime? deletedAt;
  const Notebook({
    required this.id,
    required this.title,
    this.coverId,
    this.coverImagePath,
    this.folderId,
    required this.favorite,
    required this.createdAt,
    required this.modifiedAt,
    required this.openedAt,
    required this.template,
    required this.pageSize,
    required this.paperColor,
    required this.textIndex,
    required this.tagIds,
    this.pdfPath,
    required this.deleted,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || coverId != null) {
      map['cover_id'] = Variable<String>(coverId);
    }
    if (!nullToAbsent || coverImagePath != null) {
      map['cover_image_path'] = Variable<String>(coverImagePath);
    }
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<int>(folderId);
    }
    map['favorite'] = Variable<bool>(favorite);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    map['opened_at'] = Variable<DateTime>(openedAt);
    map['template'] = Variable<int>(template);
    map['page_size'] = Variable<int>(pageSize);
    map['paper_color'] = Variable<int>(paperColor);
    map['text_index'] = Variable<String>(textIndex);
    map['tag_ids'] = Variable<String>(tagIds);
    if (!nullToAbsent || pdfPath != null) {
      map['pdf_path'] = Variable<String>(pdfPath);
    }
    map['deleted'] = Variable<bool>(deleted);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  NotebooksCompanion toCompanion(bool nullToAbsent) {
    return NotebooksCompanion(
      id: Value(id),
      title: Value(title),
      coverId: coverId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverId),
      coverImagePath: coverImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverImagePath),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      favorite: Value(favorite),
      createdAt: Value(createdAt),
      modifiedAt: Value(modifiedAt),
      openedAt: Value(openedAt),
      template: Value(template),
      pageSize: Value(pageSize),
      paperColor: Value(paperColor),
      textIndex: Value(textIndex),
      tagIds: Value(tagIds),
      pdfPath: pdfPath == null && nullToAbsent
          ? const Value.absent()
          : Value(pdfPath),
      deleted: Value(deleted),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Notebook.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Notebook(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      coverId: serializer.fromJson<String?>(json['coverId']),
      coverImagePath: serializer.fromJson<String?>(json['coverImagePath']),
      folderId: serializer.fromJson<int?>(json['folderId']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      openedAt: serializer.fromJson<DateTime>(json['openedAt']),
      template: serializer.fromJson<int>(json['template']),
      pageSize: serializer.fromJson<int>(json['pageSize']),
      paperColor: serializer.fromJson<int>(json['paperColor']),
      textIndex: serializer.fromJson<String>(json['textIndex']),
      tagIds: serializer.fromJson<String>(json['tagIds']),
      pdfPath: serializer.fromJson<String?>(json['pdfPath']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'coverId': serializer.toJson<String?>(coverId),
      'coverImagePath': serializer.toJson<String?>(coverImagePath),
      'folderId': serializer.toJson<int?>(folderId),
      'favorite': serializer.toJson<bool>(favorite),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'openedAt': serializer.toJson<DateTime>(openedAt),
      'template': serializer.toJson<int>(template),
      'pageSize': serializer.toJson<int>(pageSize),
      'paperColor': serializer.toJson<int>(paperColor),
      'textIndex': serializer.toJson<String>(textIndex),
      'tagIds': serializer.toJson<String>(tagIds),
      'pdfPath': serializer.toJson<String?>(pdfPath),
      'deleted': serializer.toJson<bool>(deleted),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Notebook copyWith({
    int? id,
    String? title,
    Value<String?> coverId = const Value.absent(),
    Value<String?> coverImagePath = const Value.absent(),
    Value<int?> folderId = const Value.absent(),
    bool? favorite,
    DateTime? createdAt,
    DateTime? modifiedAt,
    DateTime? openedAt,
    int? template,
    int? pageSize,
    int? paperColor,
    String? textIndex,
    String? tagIds,
    Value<String?> pdfPath = const Value.absent(),
    bool? deleted,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Notebook(
    id: id ?? this.id,
    title: title ?? this.title,
    coverId: coverId.present ? coverId.value : this.coverId,
    coverImagePath: coverImagePath.present
        ? coverImagePath.value
        : this.coverImagePath,
    folderId: folderId.present ? folderId.value : this.folderId,
    favorite: favorite ?? this.favorite,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    openedAt: openedAt ?? this.openedAt,
    template: template ?? this.template,
    pageSize: pageSize ?? this.pageSize,
    paperColor: paperColor ?? this.paperColor,
    textIndex: textIndex ?? this.textIndex,
    tagIds: tagIds ?? this.tagIds,
    pdfPath: pdfPath.present ? pdfPath.value : this.pdfPath,
    deleted: deleted ?? this.deleted,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Notebook copyWithCompanion(NotebooksCompanion data) {
    return Notebook(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      coverId: data.coverId.present ? data.coverId.value : this.coverId,
      coverImagePath: data.coverImagePath.present
          ? data.coverImagePath.value
          : this.coverImagePath,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
      template: data.template.present ? data.template.value : this.template,
      pageSize: data.pageSize.present ? data.pageSize.value : this.pageSize,
      paperColor: data.paperColor.present
          ? data.paperColor.value
          : this.paperColor,
      textIndex: data.textIndex.present ? data.textIndex.value : this.textIndex,
      tagIds: data.tagIds.present ? data.tagIds.value : this.tagIds,
      pdfPath: data.pdfPath.present ? data.pdfPath.value : this.pdfPath,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Notebook(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverId: $coverId, ')
          ..write('coverImagePath: $coverImagePath, ')
          ..write('folderId: $folderId, ')
          ..write('favorite: $favorite, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('openedAt: $openedAt, ')
          ..write('template: $template, ')
          ..write('pageSize: $pageSize, ')
          ..write('paperColor: $paperColor, ')
          ..write('textIndex: $textIndex, ')
          ..write('tagIds: $tagIds, ')
          ..write('pdfPath: $pdfPath, ')
          ..write('deleted: $deleted, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    coverId,
    coverImagePath,
    folderId,
    favorite,
    createdAt,
    modifiedAt,
    openedAt,
    template,
    pageSize,
    paperColor,
    textIndex,
    tagIds,
    pdfPath,
    deleted,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Notebook &&
          other.id == this.id &&
          other.title == this.title &&
          other.coverId == this.coverId &&
          other.coverImagePath == this.coverImagePath &&
          other.folderId == this.folderId &&
          other.favorite == this.favorite &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt &&
          other.openedAt == this.openedAt &&
          other.template == this.template &&
          other.pageSize == this.pageSize &&
          other.paperColor == this.paperColor &&
          other.textIndex == this.textIndex &&
          other.tagIds == this.tagIds &&
          other.pdfPath == this.pdfPath &&
          other.deleted == this.deleted &&
          other.deletedAt == this.deletedAt);
}

class NotebooksCompanion extends UpdateCompanion<Notebook> {
  final Value<int> id;
  final Value<String> title;
  final Value<String?> coverId;
  final Value<String?> coverImagePath;
  final Value<int?> folderId;
  final Value<bool> favorite;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  final Value<DateTime> openedAt;
  final Value<int> template;
  final Value<int> pageSize;
  final Value<int> paperColor;
  final Value<String> textIndex;
  final Value<String> tagIds;
  final Value<String?> pdfPath;
  final Value<bool> deleted;
  final Value<DateTime?> deletedAt;
  const NotebooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.coverId = const Value.absent(),
    this.coverImagePath = const Value.absent(),
    this.folderId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.template = const Value.absent(),
    this.pageSize = const Value.absent(),
    this.paperColor = const Value.absent(),
    this.textIndex = const Value.absent(),
    this.tagIds = const Value.absent(),
    this.pdfPath = const Value.absent(),
    this.deleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
  });
  NotebooksCompanion.insert({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.coverId = const Value.absent(),
    this.coverImagePath = const Value.absent(),
    this.folderId = const Value.absent(),
    this.favorite = const Value.absent(),
    required DateTime createdAt,
    required DateTime modifiedAt,
    required DateTime openedAt,
    this.template = const Value.absent(),
    this.pageSize = const Value.absent(),
    this.paperColor = const Value.absent(),
    this.textIndex = const Value.absent(),
    this.tagIds = const Value.absent(),
    this.pdfPath = const Value.absent(),
    this.deleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
  }) : createdAt = Value(createdAt),
       modifiedAt = Value(modifiedAt),
       openedAt = Value(openedAt);
  static Insertable<Notebook> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? coverId,
    Expression<String>? coverImagePath,
    Expression<int>? folderId,
    Expression<bool>? favorite,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<DateTime>? openedAt,
    Expression<int>? template,
    Expression<int>? pageSize,
    Expression<int>? paperColor,
    Expression<String>? textIndex,
    Expression<String>? tagIds,
    Expression<String>? pdfPath,
    Expression<bool>? deleted,
    Expression<DateTime>? deletedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (coverId != null) 'cover_id': coverId,
      if (coverImagePath != null) 'cover_image_path': coverImagePath,
      if (folderId != null) 'folder_id': folderId,
      if (favorite != null) 'favorite': favorite,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (openedAt != null) 'opened_at': openedAt,
      if (template != null) 'template': template,
      if (pageSize != null) 'page_size': pageSize,
      if (paperColor != null) 'paper_color': paperColor,
      if (textIndex != null) 'text_index': textIndex,
      if (tagIds != null) 'tag_ids': tagIds,
      if (pdfPath != null) 'pdf_path': pdfPath,
      if (deleted != null) 'deleted': deleted,
      if (deletedAt != null) 'deleted_at': deletedAt,
    });
  }

  NotebooksCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String?>? coverId,
    Value<String?>? coverImagePath,
    Value<int?>? folderId,
    Value<bool>? favorite,
    Value<DateTime>? createdAt,
    Value<DateTime>? modifiedAt,
    Value<DateTime>? openedAt,
    Value<int>? template,
    Value<int>? pageSize,
    Value<int>? paperColor,
    Value<String>? textIndex,
    Value<String>? tagIds,
    Value<String?>? pdfPath,
    Value<bool>? deleted,
    Value<DateTime?>? deletedAt,
  }) {
    return NotebooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      coverId: coverId ?? this.coverId,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      folderId: folderId ?? this.folderId,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      openedAt: openedAt ?? this.openedAt,
      template: template ?? this.template,
      pageSize: pageSize ?? this.pageSize,
      paperColor: paperColor ?? this.paperColor,
      textIndex: textIndex ?? this.textIndex,
      tagIds: tagIds ?? this.tagIds,
      pdfPath: pdfPath ?? this.pdfPath,
      deleted: deleted ?? this.deleted,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverId.present) {
      map['cover_id'] = Variable<String>(coverId.value);
    }
    if (coverImagePath.present) {
      map['cover_image_path'] = Variable<String>(coverImagePath.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<DateTime>(openedAt.value);
    }
    if (template.present) {
      map['template'] = Variable<int>(template.value);
    }
    if (pageSize.present) {
      map['page_size'] = Variable<int>(pageSize.value);
    }
    if (paperColor.present) {
      map['paper_color'] = Variable<int>(paperColor.value);
    }
    if (textIndex.present) {
      map['text_index'] = Variable<String>(textIndex.value);
    }
    if (tagIds.present) {
      map['tag_ids'] = Variable<String>(tagIds.value);
    }
    if (pdfPath.present) {
      map['pdf_path'] = Variable<String>(pdfPath.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotebooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverId: $coverId, ')
          ..write('coverImagePath: $coverImagePath, ')
          ..write('folderId: $folderId, ')
          ..write('favorite: $favorite, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('openedAt: $openedAt, ')
          ..write('template: $template, ')
          ..write('pageSize: $pageSize, ')
          ..write('paperColor: $paperColor, ')
          ..write('textIndex: $textIndex, ')
          ..write('tagIds: $tagIds, ')
          ..write('pdfPath: $pdfPath, ')
          ..write('deleted: $deleted, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }
}

class $PagesTable extends Pages with TableInfo<$PagesTable, Page> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _notebookIdMeta = const VerificationMeta(
    'notebookId',
  );
  @override
  late final GeneratedColumn<int> notebookId = GeneratedColumn<int>(
    'notebook_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bookmarkedMeta = const VerificationMeta(
    'bookmarked',
  );
  @override
  late final GeneratedColumn<bool> bookmarked = GeneratedColumn<bool>(
    'bookmarked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("bookmarked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _templateMeta = const VerificationMeta(
    'template',
  );
  @override
  late final GeneratedColumn<int> template = GeneratedColumn<int>(
    'template',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pageSizeMeta = const VerificationMeta(
    'pageSize',
  );
  @override
  late final GeneratedColumn<int> pageSize = GeneratedColumn<int>(
    'page_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _paperColorMeta = const VerificationMeta(
    'paperColor',
  );
  @override
  late final GeneratedColumn<int> paperColor = GeneratedColumn<int>(
    'paper_color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFFFFFFFF),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    notebookId,
    position,
    title,
    bookmarked,
    template,
    pageSize,
    paperColor,
    createdAt,
    modifiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Page> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('notebook_id')) {
      context.handle(
        _notebookIdMeta,
        notebookId.isAcceptableOrUnknown(data['notebook_id']!, _notebookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_notebookIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('bookmarked')) {
      context.handle(
        _bookmarkedMeta,
        bookmarked.isAcceptableOrUnknown(data['bookmarked']!, _bookmarkedMeta),
      );
    }
    if (data.containsKey('template')) {
      context.handle(
        _templateMeta,
        template.isAcceptableOrUnknown(data['template']!, _templateMeta),
      );
    }
    if (data.containsKey('page_size')) {
      context.handle(
        _pageSizeMeta,
        pageSize.isAcceptableOrUnknown(data['page_size']!, _pageSizeMeta),
      );
    }
    if (data.containsKey('paper_color')) {
      context.handle(
        _paperColorMeta,
        paperColor.isAcceptableOrUnknown(data['paper_color']!, _paperColorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Page map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Page(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      notebookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}notebook_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      bookmarked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}bookmarked'],
      )!,
      template: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}template'],
      )!,
      pageSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_size'],
      )!,
      paperColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paper_color'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
    );
  }

  @override
  $PagesTable createAlias(String alias) {
    return $PagesTable(attachedDatabase, alias);
  }
}

class Page extends DataClass implements Insertable<Page> {
  final int id;
  final int notebookId;
  final int position;
  final String title;
  final bool bookmarked;
  final int template;
  final int pageSize;
  final int paperColor;
  final DateTime createdAt;
  final DateTime modifiedAt;
  const Page({
    required this.id,
    required this.notebookId,
    required this.position,
    required this.title,
    required this.bookmarked,
    required this.template,
    required this.pageSize,
    required this.paperColor,
    required this.createdAt,
    required this.modifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['notebook_id'] = Variable<int>(notebookId);
    map['position'] = Variable<int>(position);
    map['title'] = Variable<String>(title);
    map['bookmarked'] = Variable<bool>(bookmarked);
    map['template'] = Variable<int>(template);
    map['page_size'] = Variable<int>(pageSize);
    map['paper_color'] = Variable<int>(paperColor);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    return map;
  }

  PagesCompanion toCompanion(bool nullToAbsent) {
    return PagesCompanion(
      id: Value(id),
      notebookId: Value(notebookId),
      position: Value(position),
      title: Value(title),
      bookmarked: Value(bookmarked),
      template: Value(template),
      pageSize: Value(pageSize),
      paperColor: Value(paperColor),
      createdAt: Value(createdAt),
      modifiedAt: Value(modifiedAt),
    );
  }

  factory Page.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Page(
      id: serializer.fromJson<int>(json['id']),
      notebookId: serializer.fromJson<int>(json['notebookId']),
      position: serializer.fromJson<int>(json['position']),
      title: serializer.fromJson<String>(json['title']),
      bookmarked: serializer.fromJson<bool>(json['bookmarked']),
      template: serializer.fromJson<int>(json['template']),
      pageSize: serializer.fromJson<int>(json['pageSize']),
      paperColor: serializer.fromJson<int>(json['paperColor']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'notebookId': serializer.toJson<int>(notebookId),
      'position': serializer.toJson<int>(position),
      'title': serializer.toJson<String>(title),
      'bookmarked': serializer.toJson<bool>(bookmarked),
      'template': serializer.toJson<int>(template),
      'pageSize': serializer.toJson<int>(pageSize),
      'paperColor': serializer.toJson<int>(paperColor),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
    };
  }

  Page copyWith({
    int? id,
    int? notebookId,
    int? position,
    String? title,
    bool? bookmarked,
    int? template,
    int? pageSize,
    int? paperColor,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) => Page(
    id: id ?? this.id,
    notebookId: notebookId ?? this.notebookId,
    position: position ?? this.position,
    title: title ?? this.title,
    bookmarked: bookmarked ?? this.bookmarked,
    template: template ?? this.template,
    pageSize: pageSize ?? this.pageSize,
    paperColor: paperColor ?? this.paperColor,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
  );
  Page copyWithCompanion(PagesCompanion data) {
    return Page(
      id: data.id.present ? data.id.value : this.id,
      notebookId: data.notebookId.present
          ? data.notebookId.value
          : this.notebookId,
      position: data.position.present ? data.position.value : this.position,
      title: data.title.present ? data.title.value : this.title,
      bookmarked: data.bookmarked.present
          ? data.bookmarked.value
          : this.bookmarked,
      template: data.template.present ? data.template.value : this.template,
      pageSize: data.pageSize.present ? data.pageSize.value : this.pageSize,
      paperColor: data.paperColor.present
          ? data.paperColor.value
          : this.paperColor,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Page(')
          ..write('id: $id, ')
          ..write('notebookId: $notebookId, ')
          ..write('position: $position, ')
          ..write('title: $title, ')
          ..write('bookmarked: $bookmarked, ')
          ..write('template: $template, ')
          ..write('pageSize: $pageSize, ')
          ..write('paperColor: $paperColor, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    notebookId,
    position,
    title,
    bookmarked,
    template,
    pageSize,
    paperColor,
    createdAt,
    modifiedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Page &&
          other.id == this.id &&
          other.notebookId == this.notebookId &&
          other.position == this.position &&
          other.title == this.title &&
          other.bookmarked == this.bookmarked &&
          other.template == this.template &&
          other.pageSize == this.pageSize &&
          other.paperColor == this.paperColor &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt);
}

class PagesCompanion extends UpdateCompanion<Page> {
  final Value<int> id;
  final Value<int> notebookId;
  final Value<int> position;
  final Value<String> title;
  final Value<bool> bookmarked;
  final Value<int> template;
  final Value<int> pageSize;
  final Value<int> paperColor;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  const PagesCompanion({
    this.id = const Value.absent(),
    this.notebookId = const Value.absent(),
    this.position = const Value.absent(),
    this.title = const Value.absent(),
    this.bookmarked = const Value.absent(),
    this.template = const Value.absent(),
    this.pageSize = const Value.absent(),
    this.paperColor = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
  });
  PagesCompanion.insert({
    this.id = const Value.absent(),
    required int notebookId,
    this.position = const Value.absent(),
    this.title = const Value.absent(),
    this.bookmarked = const Value.absent(),
    this.template = const Value.absent(),
    this.pageSize = const Value.absent(),
    this.paperColor = const Value.absent(),
    required DateTime createdAt,
    required DateTime modifiedAt,
  }) : notebookId = Value(notebookId),
       createdAt = Value(createdAt),
       modifiedAt = Value(modifiedAt);
  static Insertable<Page> custom({
    Expression<int>? id,
    Expression<int>? notebookId,
    Expression<int>? position,
    Expression<String>? title,
    Expression<bool>? bookmarked,
    Expression<int>? template,
    Expression<int>? pageSize,
    Expression<int>? paperColor,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (notebookId != null) 'notebook_id': notebookId,
      if (position != null) 'position': position,
      if (title != null) 'title': title,
      if (bookmarked != null) 'bookmarked': bookmarked,
      if (template != null) 'template': template,
      if (pageSize != null) 'page_size': pageSize,
      if (paperColor != null) 'paper_color': paperColor,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
    });
  }

  PagesCompanion copyWith({
    Value<int>? id,
    Value<int>? notebookId,
    Value<int>? position,
    Value<String>? title,
    Value<bool>? bookmarked,
    Value<int>? template,
    Value<int>? pageSize,
    Value<int>? paperColor,
    Value<DateTime>? createdAt,
    Value<DateTime>? modifiedAt,
  }) {
    return PagesCompanion(
      id: id ?? this.id,
      notebookId: notebookId ?? this.notebookId,
      position: position ?? this.position,
      title: title ?? this.title,
      bookmarked: bookmarked ?? this.bookmarked,
      template: template ?? this.template,
      pageSize: pageSize ?? this.pageSize,
      paperColor: paperColor ?? this.paperColor,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (notebookId.present) {
      map['notebook_id'] = Variable<int>(notebookId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (bookmarked.present) {
      map['bookmarked'] = Variable<bool>(bookmarked.value);
    }
    if (template.present) {
      map['template'] = Variable<int>(template.value);
    }
    if (pageSize.present) {
      map['page_size'] = Variable<int>(pageSize.value);
    }
    if (paperColor.present) {
      map['paper_color'] = Variable<int>(paperColor.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PagesCompanion(')
          ..write('id: $id, ')
          ..write('notebookId: $notebookId, ')
          ..write('position: $position, ')
          ..write('title: $title, ')
          ..write('bookmarked: $bookmarked, ')
          ..write('template: $template, ')
          ..write('pageSize: $pageSize, ')
          ..write('paperColor: $paperColor, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFF9333EA),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final int id;
  final String name;
  final int color;
  const Tag({required this.id, required this.name, required this.color});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(id: Value(id), name: Value(name), color: Value(color));
  }

  factory Tag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
    };
  }

  Tag copyWith({int? id, String? name, int? color}) => Tag(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
  );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> color;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
  });
  TagsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
  });
  static Insertable<Tag> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? color,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
    });
  }

  TagsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? color,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color')
          ..write(')'))
        .toString();
  }
}

class $RecordingsTable extends Recordings
    with TableInfo<$RecordingsTable, Recording> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _notebookIdMeta = const VerificationMeta(
    'notebookId',
  );
  @override
  late final GeneratedColumn<int> notebookId = GeneratedColumn<int>(
    'notebook_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageIdMeta = const VerificationMeta('pageId');
  @override
  late final GeneratedColumn<int> pageId = GeneratedColumn<int>(
    'page_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    notebookId,
    pageId,
    path,
    durationMs,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recordings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Recording> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('notebook_id')) {
      context.handle(
        _notebookIdMeta,
        notebookId.isAcceptableOrUnknown(data['notebook_id']!, _notebookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_notebookIdMeta);
    }
    if (data.containsKey('page_id')) {
      context.handle(
        _pageIdMeta,
        pageId.isAcceptableOrUnknown(data['page_id']!, _pageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pageIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Recording map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Recording(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      notebookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}notebook_id'],
      )!,
      pageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RecordingsTable createAlias(String alias) {
    return $RecordingsTable(attachedDatabase, alias);
  }
}

class Recording extends DataClass implements Insertable<Recording> {
  final int id;
  final int notebookId;
  final int pageId;
  final String path;
  final int durationMs;
  final DateTime createdAt;
  const Recording({
    required this.id,
    required this.notebookId,
    required this.pageId,
    required this.path,
    required this.durationMs,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['notebook_id'] = Variable<int>(notebookId);
    map['page_id'] = Variable<int>(pageId);
    map['path'] = Variable<String>(path);
    map['duration_ms'] = Variable<int>(durationMs);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RecordingsCompanion toCompanion(bool nullToAbsent) {
    return RecordingsCompanion(
      id: Value(id),
      notebookId: Value(notebookId),
      pageId: Value(pageId),
      path: Value(path),
      durationMs: Value(durationMs),
      createdAt: Value(createdAt),
    );
  }

  factory Recording.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Recording(
      id: serializer.fromJson<int>(json['id']),
      notebookId: serializer.fromJson<int>(json['notebookId']),
      pageId: serializer.fromJson<int>(json['pageId']),
      path: serializer.fromJson<String>(json['path']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'notebookId': serializer.toJson<int>(notebookId),
      'pageId': serializer.toJson<int>(pageId),
      'path': serializer.toJson<String>(path),
      'durationMs': serializer.toJson<int>(durationMs),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Recording copyWith({
    int? id,
    int? notebookId,
    int? pageId,
    String? path,
    int? durationMs,
    DateTime? createdAt,
  }) => Recording(
    id: id ?? this.id,
    notebookId: notebookId ?? this.notebookId,
    pageId: pageId ?? this.pageId,
    path: path ?? this.path,
    durationMs: durationMs ?? this.durationMs,
    createdAt: createdAt ?? this.createdAt,
  );
  Recording copyWithCompanion(RecordingsCompanion data) {
    return Recording(
      id: data.id.present ? data.id.value : this.id,
      notebookId: data.notebookId.present
          ? data.notebookId.value
          : this.notebookId,
      pageId: data.pageId.present ? data.pageId.value : this.pageId,
      path: data.path.present ? data.path.value : this.path,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Recording(')
          ..write('id: $id, ')
          ..write('notebookId: $notebookId, ')
          ..write('pageId: $pageId, ')
          ..write('path: $path, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, notebookId, pageId, path, durationMs, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Recording &&
          other.id == this.id &&
          other.notebookId == this.notebookId &&
          other.pageId == this.pageId &&
          other.path == this.path &&
          other.durationMs == this.durationMs &&
          other.createdAt == this.createdAt);
}

class RecordingsCompanion extends UpdateCompanion<Recording> {
  final Value<int> id;
  final Value<int> notebookId;
  final Value<int> pageId;
  final Value<String> path;
  final Value<int> durationMs;
  final Value<DateTime> createdAt;
  const RecordingsCompanion({
    this.id = const Value.absent(),
    this.notebookId = const Value.absent(),
    this.pageId = const Value.absent(),
    this.path = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  RecordingsCompanion.insert({
    this.id = const Value.absent(),
    required int notebookId,
    required int pageId,
    this.path = const Value.absent(),
    this.durationMs = const Value.absent(),
    required DateTime createdAt,
  }) : notebookId = Value(notebookId),
       pageId = Value(pageId),
       createdAt = Value(createdAt);
  static Insertable<Recording> custom({
    Expression<int>? id,
    Expression<int>? notebookId,
    Expression<int>? pageId,
    Expression<String>? path,
    Expression<int>? durationMs,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (notebookId != null) 'notebook_id': notebookId,
      if (pageId != null) 'page_id': pageId,
      if (path != null) 'path': path,
      if (durationMs != null) 'duration_ms': durationMs,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  RecordingsCompanion copyWith({
    Value<int>? id,
    Value<int>? notebookId,
    Value<int>? pageId,
    Value<String>? path,
    Value<int>? durationMs,
    Value<DateTime>? createdAt,
  }) {
    return RecordingsCompanion(
      id: id ?? this.id,
      notebookId: notebookId ?? this.notebookId,
      pageId: pageId ?? this.pageId,
      path: path ?? this.path,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (notebookId.present) {
      map['notebook_id'] = Variable<int>(notebookId.value);
    }
    if (pageId.present) {
      map['page_id'] = Variable<int>(pageId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordingsCompanion(')
          ..write('id: $id, ')
          ..write('notebookId: $notebookId, ')
          ..write('pageId: $pageId, ')
          ..write('path: $path, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $StrokesTable extends Strokes with TableInfo<$StrokesTable, StrokeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StrokesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _pageIdMeta = const VerificationMeta('pageId');
  @override
  late final GeneratedColumn<int> pageId = GeneratedColumn<int>(
    'page_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _zMeta = const VerificationMeta('z');
  @override
  late final GeneratedColumn<int> z = GeneratedColumn<int>(
    'z',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [id, pageId, z, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'strokes';
  @override
  VerificationContext validateIntegrity(
    Insertable<StrokeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('page_id')) {
      context.handle(
        _pageIdMeta,
        pageId.isAcceptableOrUnknown(data['page_id']!, _pageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pageIdMeta);
    }
    if (data.containsKey('z')) {
      context.handle(_zMeta, z.isAcceptableOrUnknown(data['z']!, _zMeta));
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StrokeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StrokeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      pageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_id'],
      )!,
      z: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}z'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  $StrokesTable createAlias(String alias) {
    return $StrokesTable(attachedDatabase, alias);
  }
}

class StrokeRow extends DataClass implements Insertable<StrokeRow> {
  final int id;
  final int pageId;
  final int z;
  final String data;
  const StrokeRow({
    required this.id,
    required this.pageId,
    required this.z,
    required this.data,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['page_id'] = Variable<int>(pageId);
    map['z'] = Variable<int>(z);
    map['data'] = Variable<String>(data);
    return map;
  }

  StrokesCompanion toCompanion(bool nullToAbsent) {
    return StrokesCompanion(
      id: Value(id),
      pageId: Value(pageId),
      z: Value(z),
      data: Value(data),
    );
  }

  factory StrokeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StrokeRow(
      id: serializer.fromJson<int>(json['id']),
      pageId: serializer.fromJson<int>(json['pageId']),
      z: serializer.fromJson<int>(json['z']),
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'pageId': serializer.toJson<int>(pageId),
      'z': serializer.toJson<int>(z),
      'data': serializer.toJson<String>(data),
    };
  }

  StrokeRow copyWith({int? id, int? pageId, int? z, String? data}) => StrokeRow(
    id: id ?? this.id,
    pageId: pageId ?? this.pageId,
    z: z ?? this.z,
    data: data ?? this.data,
  );
  StrokeRow copyWithCompanion(StrokesCompanion data) {
    return StrokeRow(
      id: data.id.present ? data.id.value : this.id,
      pageId: data.pageId.present ? data.pageId.value : this.pageId,
      z: data.z.present ? data.z.value : this.z,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StrokeRow(')
          ..write('id: $id, ')
          ..write('pageId: $pageId, ')
          ..write('z: $z, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, pageId, z, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StrokeRow &&
          other.id == this.id &&
          other.pageId == this.pageId &&
          other.z == this.z &&
          other.data == this.data);
}

class StrokesCompanion extends UpdateCompanion<StrokeRow> {
  final Value<int> id;
  final Value<int> pageId;
  final Value<int> z;
  final Value<String> data;
  const StrokesCompanion({
    this.id = const Value.absent(),
    this.pageId = const Value.absent(),
    this.z = const Value.absent(),
    this.data = const Value.absent(),
  });
  StrokesCompanion.insert({
    this.id = const Value.absent(),
    required int pageId,
    this.z = const Value.absent(),
    this.data = const Value.absent(),
  }) : pageId = Value(pageId);
  static Insertable<StrokeRow> custom({
    Expression<int>? id,
    Expression<int>? pageId,
    Expression<int>? z,
    Expression<String>? data,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pageId != null) 'page_id': pageId,
      if (z != null) 'z': z,
      if (data != null) 'data': data,
    });
  }

  StrokesCompanion copyWith({
    Value<int>? id,
    Value<int>? pageId,
    Value<int>? z,
    Value<String>? data,
  }) {
    return StrokesCompanion(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      z: z ?? this.z,
      data: data ?? this.data,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (pageId.present) {
      map['page_id'] = Variable<int>(pageId.value);
    }
    if (z.present) {
      map['z'] = Variable<int>(z.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StrokesCompanion(')
          ..write('id: $id, ')
          ..write('pageId: $pageId, ')
          ..write('z: $z, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }
}

class $ElementsTable extends Elements
    with TableInfo<$ElementsTable, ElementRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ElementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _pageIdMeta = const VerificationMeta('pageId');
  @override
  late final GeneratedColumn<int> pageId = GeneratedColumn<int>(
    'page_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _zMeta = const VerificationMeta('z');
  @override
  late final GeneratedColumn<int> z = GeneratedColumn<int>(
    'z',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [id, pageId, z, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'elements';
  @override
  VerificationContext validateIntegrity(
    Insertable<ElementRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('page_id')) {
      context.handle(
        _pageIdMeta,
        pageId.isAcceptableOrUnknown(data['page_id']!, _pageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pageIdMeta);
    }
    if (data.containsKey('z')) {
      context.handle(_zMeta, z.isAcceptableOrUnknown(data['z']!, _zMeta));
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ElementRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ElementRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      pageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_id'],
      )!,
      z: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}z'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  $ElementsTable createAlias(String alias) {
    return $ElementsTable(attachedDatabase, alias);
  }
}

class ElementRow extends DataClass implements Insertable<ElementRow> {
  final int id;
  final int pageId;
  final int z;
  final String data;
  const ElementRow({
    required this.id,
    required this.pageId,
    required this.z,
    required this.data,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['page_id'] = Variable<int>(pageId);
    map['z'] = Variable<int>(z);
    map['data'] = Variable<String>(data);
    return map;
  }

  ElementsCompanion toCompanion(bool nullToAbsent) {
    return ElementsCompanion(
      id: Value(id),
      pageId: Value(pageId),
      z: Value(z),
      data: Value(data),
    );
  }

  factory ElementRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ElementRow(
      id: serializer.fromJson<int>(json['id']),
      pageId: serializer.fromJson<int>(json['pageId']),
      z: serializer.fromJson<int>(json['z']),
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'pageId': serializer.toJson<int>(pageId),
      'z': serializer.toJson<int>(z),
      'data': serializer.toJson<String>(data),
    };
  }

  ElementRow copyWith({int? id, int? pageId, int? z, String? data}) =>
      ElementRow(
        id: id ?? this.id,
        pageId: pageId ?? this.pageId,
        z: z ?? this.z,
        data: data ?? this.data,
      );
  ElementRow copyWithCompanion(ElementsCompanion data) {
    return ElementRow(
      id: data.id.present ? data.id.value : this.id,
      pageId: data.pageId.present ? data.pageId.value : this.pageId,
      z: data.z.present ? data.z.value : this.z,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ElementRow(')
          ..write('id: $id, ')
          ..write('pageId: $pageId, ')
          ..write('z: $z, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, pageId, z, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ElementRow &&
          other.id == this.id &&
          other.pageId == this.pageId &&
          other.z == this.z &&
          other.data == this.data);
}

class ElementsCompanion extends UpdateCompanion<ElementRow> {
  final Value<int> id;
  final Value<int> pageId;
  final Value<int> z;
  final Value<String> data;
  const ElementsCompanion({
    this.id = const Value.absent(),
    this.pageId = const Value.absent(),
    this.z = const Value.absent(),
    this.data = const Value.absent(),
  });
  ElementsCompanion.insert({
    this.id = const Value.absent(),
    required int pageId,
    this.z = const Value.absent(),
    this.data = const Value.absent(),
  }) : pageId = Value(pageId);
  static Insertable<ElementRow> custom({
    Expression<int>? id,
    Expression<int>? pageId,
    Expression<int>? z,
    Expression<String>? data,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pageId != null) 'page_id': pageId,
      if (z != null) 'z': z,
      if (data != null) 'data': data,
    });
  }

  ElementsCompanion copyWith({
    Value<int>? id,
    Value<int>? pageId,
    Value<int>? z,
    Value<String>? data,
  }) {
    return ElementsCompanion(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      z: z ?? this.z,
      data: data ?? this.data,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (pageId.present) {
      map['page_id'] = Variable<int>(pageId.value);
    }
    if (z.present) {
      map['z'] = Variable<int>(z.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ElementsCompanion(')
          ..write('id: $id, ')
          ..write('pageId: $pageId, ')
          ..write('z: $z, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $TabsTable tabs = $TabsTable(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $NotebooksTable notebooks = $NotebooksTable(this);
  late final $PagesTable pages = $PagesTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $RecordingsTable recordings = $RecordingsTable(this);
  late final $StrokesTable strokes = $StrokesTable(this);
  late final $ElementsTable elements = $ElementsTable(this);
  late final Index idxStrokesPage = Index(
    'idx_strokes_page',
    'CREATE INDEX idx_strokes_page ON strokes (page_id, z)',
  );
  late final Index idxElementsPage = Index(
    'idx_elements_page',
    'CREATE INDEX idx_elements_page ON elements (page_id, z)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tabs,
    folders,
    notebooks,
    pages,
    tags,
    recordings,
    strokes,
    elements,
    idxStrokesPage,
    idxElementsPage,
  ];
}

typedef $$TabsTableCreateCompanionBuilder = TabsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> color,
  Value<String> emoji,
  Value<int> position,
});
typedef $$TabsTableUpdateCompanionBuilder = TabsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> color,
  Value<String> emoji,
  Value<int> position,
});

class $$TabsTableFilterComposer extends Composer<_$AppDb, $TabsTable> {
  $$TabsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TabsTableOrderingComposer extends Composer<_$AppDb, $TabsTable> {
  $$TabsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TabsTableAnnotationComposer extends Composer<_$AppDb, $TabsTable> {
  $$TabsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$TabsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $TabsTable,
          Tab,
          $$TabsTableFilterComposer,
          $$TabsTableOrderingComposer,
          $$TabsTableAnnotationComposer,
          $$TabsTableCreateCompanionBuilder,
          $$TabsTableUpdateCompanionBuilder,
          (Tab, BaseReferences<_$AppDb, $TabsTable, Tab>),
          Tab,
          PrefetchHooks Function()
        > {
  $$TabsTableTableManager(_$AppDb db, $TabsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TabsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TabsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TabsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => TabsCompanion(
                id: id,
                name: name,
                color: color,
                emoji: emoji,
                position: position,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => TabsCompanion.insert(
                id: id,
                name: name,
                color: color,
                emoji: emoji,
                position: position,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TabsTable, Tab>(table),
                  BaseReferences<_$AppDb, $TabsTable, Tab>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TabsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $TabsTable,
      Tab,
      $$TabsTableFilterComposer,
      $$TabsTableOrderingComposer,
      $$TabsTableAnnotationComposer,
      $$TabsTableCreateCompanionBuilder,
      $$TabsTableUpdateCompanionBuilder,
      (Tab, BaseReferences<_$AppDb, $TabsTable, Tab>),
      Tab,
      PrefetchHooks Function()
    >;
typedef $$FoldersTableCreateCompanionBuilder = FoldersCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> color,
  Value<String> emoji,
  Value<int?> parentId,
  Value<int> position,
});
typedef $$FoldersTableUpdateCompanionBuilder = FoldersCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> color,
  Value<String> emoji,
  Value<int?> parentId,
  Value<int> position,
});

class $$FoldersTableFilterComposer extends Composer<_$AppDb, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoldersTableOrderingComposer extends Composer<_$AppDb, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AppDb, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<int> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $FoldersTable,
          Folder,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (Folder, BaseReferences<_$AppDb, $FoldersTable, Folder>),
          Folder,
          PrefetchHooks Function()
        > {
  $$FoldersTableTableManager(_$AppDb db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                name: name,
                color: color,
                emoji: emoji,
                parentId: parentId,
                position: position,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                name: name,
                color: color,
                emoji: emoji,
                parentId: parentId,
                position: position,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FoldersTable, Folder>(table),
                  BaseReferences<_$AppDb, $FoldersTable, Folder>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $FoldersTable,
      Folder,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (Folder, BaseReferences<_$AppDb, $FoldersTable, Folder>),
      Folder,
      PrefetchHooks Function()
    >;
typedef $$NotebooksTableCreateCompanionBuilder = NotebooksCompanion Function({
  Value<int> id,
  Value<String> title,
  Value<String?> coverId,
  Value<String?> coverImagePath,
  Value<int?> folderId,
  Value<bool> favorite,
  required DateTime createdAt,
  required DateTime modifiedAt,
  required DateTime openedAt,
  Value<int> template,
  Value<int> pageSize,
  Value<int> paperColor,
  Value<String> textIndex,
  Value<String> tagIds,
  Value<String?> pdfPath,
  Value<bool> deleted,
  Value<DateTime?> deletedAt,
});
typedef $$NotebooksTableUpdateCompanionBuilder = NotebooksCompanion Function({
  Value<int> id,
  Value<String> title,
  Value<String?> coverId,
  Value<String?> coverImagePath,
  Value<int?> folderId,
  Value<bool> favorite,
  Value<DateTime> createdAt,
  Value<DateTime> modifiedAt,
  Value<DateTime> openedAt,
  Value<int> template,
  Value<int> pageSize,
  Value<int> paperColor,
  Value<String> textIndex,
  Value<String> tagIds,
  Value<String?> pdfPath,
  Value<bool> deleted,
  Value<DateTime?> deletedAt,
});

class $$NotebooksTableFilterComposer
    extends Composer<_$AppDb, $NotebooksTable> {
  $$NotebooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverId => $composableBuilder(
    column: $table.coverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverImagePath => $composableBuilder(
    column: $table.coverImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageSize => $composableBuilder(
    column: $table.pageSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paperColor => $composableBuilder(
    column: $table.paperColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textIndex => $composableBuilder(
    column: $table.textIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagIds => $composableBuilder(
    column: $table.tagIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pdfPath => $composableBuilder(
    column: $table.pdfPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotebooksTableOrderingComposer
    extends Composer<_$AppDb, $NotebooksTable> {
  $$NotebooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverId => $composableBuilder(
    column: $table.coverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverImagePath => $composableBuilder(
    column: $table.coverImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageSize => $composableBuilder(
    column: $table.pageSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paperColor => $composableBuilder(
    column: $table.paperColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textIndex => $composableBuilder(
    column: $table.textIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagIds => $composableBuilder(
    column: $table.tagIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pdfPath => $composableBuilder(
    column: $table.pdfPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotebooksTableAnnotationComposer
    extends Composer<_$AppDb, $NotebooksTable> {
  $$NotebooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverId =>
      $composableBuilder(column: $table.coverId, builder: (column) => column);

  GeneratedColumn<String> get coverImagePath => $composableBuilder(
    column: $table.coverImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);

  GeneratedColumn<int> get template =>
      $composableBuilder(column: $table.template, builder: (column) => column);

  GeneratedColumn<int> get pageSize =>
      $composableBuilder(column: $table.pageSize, builder: (column) => column);

  GeneratedColumn<int> get paperColor => $composableBuilder(
    column: $table.paperColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get textIndex =>
      $composableBuilder(column: $table.textIndex, builder: (column) => column);

  GeneratedColumn<String> get tagIds =>
      $composableBuilder(column: $table.tagIds, builder: (column) => column);

  GeneratedColumn<String> get pdfPath =>
      $composableBuilder(column: $table.pdfPath, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$NotebooksTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $NotebooksTable,
          Notebook,
          $$NotebooksTableFilterComposer,
          $$NotebooksTableOrderingComposer,
          $$NotebooksTableAnnotationComposer,
          $$NotebooksTableCreateCompanionBuilder,
          $$NotebooksTableUpdateCompanionBuilder,
          (Notebook, BaseReferences<_$AppDb, $NotebooksTable, Notebook>),
          Notebook,
          PrefetchHooks Function()
        > {
  $$NotebooksTableTableManager(_$AppDb db, $NotebooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotebooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotebooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotebooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverId = const Value.absent(),
                Value<String?> coverImagePath = const Value.absent(),
                Value<int?> folderId = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<DateTime> openedAt = const Value.absent(),
                Value<int> template = const Value.absent(),
                Value<int> pageSize = const Value.absent(),
                Value<int> paperColor = const Value.absent(),
                Value<String> textIndex = const Value.absent(),
                Value<String> tagIds = const Value.absent(),
                Value<String?> pdfPath = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
              }) => NotebooksCompanion(
                id: id,
                title: title,
                coverId: coverId,
                coverImagePath: coverImagePath,
                folderId: folderId,
                favorite: favorite,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                openedAt: openedAt,
                template: template,
                pageSize: pageSize,
                paperColor: paperColor,
                textIndex: textIndex,
                tagIds: tagIds,
                pdfPath: pdfPath,
                deleted: deleted,
                deletedAt: deletedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverId = const Value.absent(),
                Value<String?> coverImagePath = const Value.absent(),
                Value<int?> folderId = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                required DateTime createdAt,
                required DateTime modifiedAt,
                required DateTime openedAt,
                Value<int> template = const Value.absent(),
                Value<int> pageSize = const Value.absent(),
                Value<int> paperColor = const Value.absent(),
                Value<String> textIndex = const Value.absent(),
                Value<String> tagIds = const Value.absent(),
                Value<String?> pdfPath = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
              }) => NotebooksCompanion.insert(
                id: id,
                title: title,
                coverId: coverId,
                coverImagePath: coverImagePath,
                folderId: folderId,
                favorite: favorite,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                openedAt: openedAt,
                template: template,
                pageSize: pageSize,
                paperColor: paperColor,
                textIndex: textIndex,
                tagIds: tagIds,
                pdfPath: pdfPath,
                deleted: deleted,
                deletedAt: deletedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NotebooksTable, Notebook>(table),
                  BaseReferences<_$AppDb, $NotebooksTable, Notebook>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotebooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $NotebooksTable,
      Notebook,
      $$NotebooksTableFilterComposer,
      $$NotebooksTableOrderingComposer,
      $$NotebooksTableAnnotationComposer,
      $$NotebooksTableCreateCompanionBuilder,
      $$NotebooksTableUpdateCompanionBuilder,
      (Notebook, BaseReferences<_$AppDb, $NotebooksTable, Notebook>),
      Notebook,
      PrefetchHooks Function()
    >;
typedef $$PagesTableCreateCompanionBuilder = PagesCompanion Function({
  Value<int> id,
  required int notebookId,
  Value<int> position,
  Value<String> title,
  Value<bool> bookmarked,
  Value<int> template,
  Value<int> pageSize,
  Value<int> paperColor,
  required DateTime createdAt,
  required DateTime modifiedAt,
});
typedef $$PagesTableUpdateCompanionBuilder = PagesCompanion Function({
  Value<int> id,
  Value<int> notebookId,
  Value<int> position,
  Value<String> title,
  Value<bool> bookmarked,
  Value<int> template,
  Value<int> pageSize,
  Value<int> paperColor,
  Value<DateTime> createdAt,
  Value<DateTime> modifiedAt,
});

class $$PagesTableFilterComposer extends Composer<_$AppDb, $PagesTable> {
  $$PagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notebookId => $composableBuilder(
    column: $table.notebookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get bookmarked => $composableBuilder(
    column: $table.bookmarked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageSize => $composableBuilder(
    column: $table.pageSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paperColor => $composableBuilder(
    column: $table.paperColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PagesTableOrderingComposer extends Composer<_$AppDb, $PagesTable> {
  $$PagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notebookId => $composableBuilder(
    column: $table.notebookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get bookmarked => $composableBuilder(
    column: $table.bookmarked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageSize => $composableBuilder(
    column: $table.pageSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paperColor => $composableBuilder(
    column: $table.paperColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PagesTableAnnotationComposer extends Composer<_$AppDb, $PagesTable> {
  $$PagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get notebookId => $composableBuilder(
    column: $table.notebookId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get bookmarked => $composableBuilder(
    column: $table.bookmarked,
    builder: (column) => column,
  );

  GeneratedColumn<int> get template =>
      $composableBuilder(column: $table.template, builder: (column) => column);

  GeneratedColumn<int> get pageSize =>
      $composableBuilder(column: $table.pageSize, builder: (column) => column);

  GeneratedColumn<int> get paperColor => $composableBuilder(
    column: $table.paperColor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );
}

class $$PagesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $PagesTable,
          Page,
          $$PagesTableFilterComposer,
          $$PagesTableOrderingComposer,
          $$PagesTableAnnotationComposer,
          $$PagesTableCreateCompanionBuilder,
          $$PagesTableUpdateCompanionBuilder,
          (Page, BaseReferences<_$AppDb, $PagesTable, Page>),
          Page,
          PrefetchHooks Function()
        > {
  $$PagesTableTableManager(_$AppDb db, $PagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> notebookId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<bool> bookmarked = const Value.absent(),
                Value<int> template = const Value.absent(),
                Value<int> pageSize = const Value.absent(),
                Value<int> paperColor = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
              }) => PagesCompanion(
                id: id,
                notebookId: notebookId,
                position: position,
                title: title,
                bookmarked: bookmarked,
                template: template,
                pageSize: pageSize,
                paperColor: paperColor,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int notebookId,
                Value<int> position = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<bool> bookmarked = const Value.absent(),
                Value<int> template = const Value.absent(),
                Value<int> pageSize = const Value.absent(),
                Value<int> paperColor = const Value.absent(),
                required DateTime createdAt,
                required DateTime modifiedAt,
              }) => PagesCompanion.insert(
                id: id,
                notebookId: notebookId,
                position: position,
                title: title,
                bookmarked: bookmarked,
                template: template,
                pageSize: pageSize,
                paperColor: paperColor,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PagesTable, Page>(table),
                  BaseReferences<_$AppDb, $PagesTable, Page>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $PagesTable,
      Page,
      $$PagesTableFilterComposer,
      $$PagesTableOrderingComposer,
      $$PagesTableAnnotationComposer,
      $$PagesTableCreateCompanionBuilder,
      $$PagesTableUpdateCompanionBuilder,
      (Page, BaseReferences<_$AppDb, $PagesTable, Page>),
      Page,
      PrefetchHooks Function()
    >;
typedef $$TagsTableCreateCompanionBuilder = TagsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> color,
});
typedef $$TagsTableUpdateCompanionBuilder = TagsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> color,
});

class $$TagsTableFilterComposer extends Composer<_$AppDb, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagsTableOrderingComposer extends Composer<_$AppDb, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer extends Composer<_$AppDb, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $TagsTable,
          Tag,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (Tag, BaseReferences<_$AppDb, $TagsTable, Tag>),
          Tag,
          PrefetchHooks Function()
        > {
  $$TagsTableTableManager(_$AppDb db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> color = const Value.absent(),
          }) => TagsCompanion(id: id, name: name, color: color),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> color = const Value.absent(),
          }) => TagsCompanion.insert(id: id, name: name, color: color),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TagsTable, Tag>(table),
                  BaseReferences<_$AppDb, $TagsTable, Tag>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $TagsTable,
      Tag,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (Tag, BaseReferences<_$AppDb, $TagsTable, Tag>),
      Tag,
      PrefetchHooks Function()
    >;
typedef $$RecordingsTableCreateCompanionBuilder = RecordingsCompanion Function({
  Value<int> id,
  required int notebookId,
  required int pageId,
  Value<String> path,
  Value<int> durationMs,
  required DateTime createdAt,
});
typedef $$RecordingsTableUpdateCompanionBuilder = RecordingsCompanion Function({
  Value<int> id,
  Value<int> notebookId,
  Value<int> pageId,
  Value<String> path,
  Value<int> durationMs,
  Value<DateTime> createdAt,
});

class $$RecordingsTableFilterComposer
    extends Composer<_$AppDb, $RecordingsTable> {
  $$RecordingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notebookId => $composableBuilder(
    column: $table.notebookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecordingsTableOrderingComposer
    extends Composer<_$AppDb, $RecordingsTable> {
  $$RecordingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notebookId => $composableBuilder(
    column: $table.notebookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecordingsTableAnnotationComposer
    extends Composer<_$AppDb, $RecordingsTable> {
  $$RecordingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get notebookId => $composableBuilder(
    column: $table.notebookId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageId =>
      $composableBuilder(column: $table.pageId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$RecordingsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $RecordingsTable,
          Recording,
          $$RecordingsTableFilterComposer,
          $$RecordingsTableOrderingComposer,
          $$RecordingsTableAnnotationComposer,
          $$RecordingsTableCreateCompanionBuilder,
          $$RecordingsTableUpdateCompanionBuilder,
          (Recording, BaseReferences<_$AppDb, $RecordingsTable, Recording>),
          Recording,
          PrefetchHooks Function()
        > {
  $$RecordingsTableTableManager(_$AppDb db, $RecordingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecordingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecordingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecordingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> notebookId = const Value.absent(),
                Value<int> pageId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => RecordingsCompanion(
                id: id,
                notebookId: notebookId,
                pageId: pageId,
                path: path,
                durationMs: durationMs,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int notebookId,
                required int pageId,
                Value<String> path = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                required DateTime createdAt,
              }) => RecordingsCompanion.insert(
                id: id,
                notebookId: notebookId,
                pageId: pageId,
                path: path,
                durationMs: durationMs,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecordingsTable, Recording>(table),
                  BaseReferences<_$AppDb, $RecordingsTable, Recording>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecordingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $RecordingsTable,
      Recording,
      $$RecordingsTableFilterComposer,
      $$RecordingsTableOrderingComposer,
      $$RecordingsTableAnnotationComposer,
      $$RecordingsTableCreateCompanionBuilder,
      $$RecordingsTableUpdateCompanionBuilder,
      (Recording, BaseReferences<_$AppDb, $RecordingsTable, Recording>),
      Recording,
      PrefetchHooks Function()
    >;
typedef $$StrokesTableCreateCompanionBuilder = StrokesCompanion Function({
  Value<int> id,
  required int pageId,
  Value<int> z,
  Value<String> data,
});
typedef $$StrokesTableUpdateCompanionBuilder = StrokesCompanion Function({
  Value<int> id,
  Value<int> pageId,
  Value<int> z,
  Value<String> data,
});

class $$StrokesTableFilterComposer extends Composer<_$AppDb, $StrokesTable> {
  $$StrokesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get z => $composableBuilder(
    column: $table.z,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StrokesTableOrderingComposer extends Composer<_$AppDb, $StrokesTable> {
  $$StrokesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get z => $composableBuilder(
    column: $table.z,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StrokesTableAnnotationComposer
    extends Composer<_$AppDb, $StrokesTable> {
  $$StrokesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get pageId =>
      $composableBuilder(column: $table.pageId, builder: (column) => column);

  GeneratedColumn<int> get z =>
      $composableBuilder(column: $table.z, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $$StrokesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $StrokesTable,
          StrokeRow,
          $$StrokesTableFilterComposer,
          $$StrokesTableOrderingComposer,
          $$StrokesTableAnnotationComposer,
          $$StrokesTableCreateCompanionBuilder,
          $$StrokesTableUpdateCompanionBuilder,
          (StrokeRow, BaseReferences<_$AppDb, $StrokesTable, StrokeRow>),
          StrokeRow,
          PrefetchHooks Function()
        > {
  $$StrokesTableTableManager(_$AppDb db, $StrokesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StrokesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StrokesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StrokesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> pageId = const Value.absent(),
            Value<int> z = const Value.absent(),
            Value<String> data = const Value.absent(),
          }) => StrokesCompanion(id: id, pageId: pageId, z: z, data: data),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int pageId,
                Value<int> z = const Value.absent(),
                Value<String> data = const Value.absent(),
              }) => StrokesCompanion.insert(
                id: id,
                pageId: pageId,
                z: z,
                data: data,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StrokesTable, StrokeRow>(table),
                  BaseReferences<_$AppDb, $StrokesTable, StrokeRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StrokesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $StrokesTable,
      StrokeRow,
      $$StrokesTableFilterComposer,
      $$StrokesTableOrderingComposer,
      $$StrokesTableAnnotationComposer,
      $$StrokesTableCreateCompanionBuilder,
      $$StrokesTableUpdateCompanionBuilder,
      (StrokeRow, BaseReferences<_$AppDb, $StrokesTable, StrokeRow>),
      StrokeRow,
      PrefetchHooks Function()
    >;
typedef $$ElementsTableCreateCompanionBuilder = ElementsCompanion Function({
  Value<int> id,
  required int pageId,
  Value<int> z,
  Value<String> data,
});
typedef $$ElementsTableUpdateCompanionBuilder = ElementsCompanion Function({
  Value<int> id,
  Value<int> pageId,
  Value<int> z,
  Value<String> data,
});

class $$ElementsTableFilterComposer extends Composer<_$AppDb, $ElementsTable> {
  $$ElementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get z => $composableBuilder(
    column: $table.z,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ElementsTableOrderingComposer
    extends Composer<_$AppDb, $ElementsTable> {
  $$ElementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get z => $composableBuilder(
    column: $table.z,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ElementsTableAnnotationComposer
    extends Composer<_$AppDb, $ElementsTable> {
  $$ElementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get pageId =>
      $composableBuilder(column: $table.pageId, builder: (column) => column);

  GeneratedColumn<int> get z =>
      $composableBuilder(column: $table.z, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $$ElementsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ElementsTable,
          ElementRow,
          $$ElementsTableFilterComposer,
          $$ElementsTableOrderingComposer,
          $$ElementsTableAnnotationComposer,
          $$ElementsTableCreateCompanionBuilder,
          $$ElementsTableUpdateCompanionBuilder,
          (ElementRow, BaseReferences<_$AppDb, $ElementsTable, ElementRow>),
          ElementRow,
          PrefetchHooks Function()
        > {
  $$ElementsTableTableManager(_$AppDb db, $ElementsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ElementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ElementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ElementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> pageId = const Value.absent(),
            Value<int> z = const Value.absent(),
            Value<String> data = const Value.absent(),
          }) => ElementsCompanion(id: id, pageId: pageId, z: z, data: data),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int pageId,
                Value<int> z = const Value.absent(),
                Value<String> data = const Value.absent(),
              }) => ElementsCompanion.insert(
                id: id,
                pageId: pageId,
                z: z,
                data: data,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ElementsTable, ElementRow>(table),
                  BaseReferences<_$AppDb, $ElementsTable, ElementRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ElementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ElementsTable,
      ElementRow,
      $$ElementsTableFilterComposer,
      $$ElementsTableOrderingComposer,
      $$ElementsTableAnnotationComposer,
      $$ElementsTableCreateCompanionBuilder,
      $$ElementsTableUpdateCompanionBuilder,
      (ElementRow, BaseReferences<_$AppDb, $ElementsTable, ElementRow>),
      ElementRow,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$TabsTableTableManager get tabs => $$TabsTableTableManager(_db, _db.tabs);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$NotebooksTableTableManager get notebooks =>
      $$NotebooksTableTableManager(_db, _db.notebooks);
  $$PagesTableTableManager get pages =>
      $$PagesTableTableManager(_db, _db.pages);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$RecordingsTableTableManager get recordings =>
      $$RecordingsTableTableManager(_db, _db.recordings);
  $$StrokesTableTableManager get strokes =>
      $$StrokesTableTableManager(_db, _db.strokes);
  $$ElementsTableTableManager get elements =>
      $$ElementsTableTableManager(_db, _db.elements);
}
