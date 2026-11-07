// ---------------------------------------------------------------------------
// LEGACY ISAR SCHEMAS — extracted verbatim from the isar_generator 3.1.0+1
// output of the v2.x codebase. Used ONLY by the one-time migration that
// reads the old on-device Isar database (see migrator.dart). Never used for
// writing; the app's own storage is Drift/SQLite.
// ---------------------------------------------------------------------------
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, unused_element, type_annotate_public_apis
import 'package:isar/isar.dart';

import '../entities.dart';


const TabEntitySchema = CollectionSchema(
  name: r'TabEntity',
  id: 4220665327236150087,
  properties: {
    r'color': PropertySchema(
      id: 0,
      name: r'color',
      type: IsarType.long,
    ),
    r'emoji': PropertySchema(
      id: 1,
      name: r'emoji',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 2,
      name: r'name',
      type: IsarType.string,
    ),
    r'position': PropertySchema(
      id: 3,
      name: r'position',
      type: IsarType.long,
    )
  },
  estimateSize: _tabEntityEstimateSize,
  serialize: _tabEntitySerialize,
  deserialize: _tabEntityDeserialize,
  deserializeProp: _tabEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _tabEntityGetId,
  getLinks: _tabEntityGetLinks,
  attach: _tabEntityAttach,
  version: '3.1.0+1',
);

int _tabEntityEstimateSize(
  TabEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.emoji.length * 3;
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _tabEntitySerialize(
  TabEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.color);
  writer.writeString(offsets[1], object.emoji);
  writer.writeString(offsets[2], object.name);
  writer.writeLong(offsets[3], object.position);
}

TabEntity _tabEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = TabEntity();
  object.color = reader.readLong(offsets[0]);
  object.emoji = reader.readString(offsets[1]);
  object.id = id;
  object.name = reader.readString(offsets[2]);
  object.position = reader.readLong(offsets[3]);
  return object;
}

P _tabEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _tabEntityGetId(TabEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _tabEntityGetLinks(TabEntity object) {
  return [];
}

void _tabEntityAttach(IsarCollection<dynamic> col, Id id, TabEntity object) {
  object.id = id;
}

const FolderEntitySchema = CollectionSchema(
  name: r'FolderEntity',
  id: 1865616643271602644,
  properties: {
    r'color': PropertySchema(
      id: 0,
      name: r'color',
      type: IsarType.long,
    ),
    r'emoji': PropertySchema(
      id: 1,
      name: r'emoji',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 2,
      name: r'name',
      type: IsarType.string,
    ),
    r'parentId': PropertySchema(
      id: 3,
      name: r'parentId',
      type: IsarType.long,
    ),
    r'position': PropertySchema(
      id: 4,
      name: r'position',
      type: IsarType.long,
    )
  },
  estimateSize: _folderEntityEstimateSize,
  serialize: _folderEntitySerialize,
  deserialize: _folderEntityDeserialize,
  deserializeProp: _folderEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _folderEntityGetId,
  getLinks: _folderEntityGetLinks,
  attach: _folderEntityAttach,
  version: '3.1.0+1',
);

int _folderEntityEstimateSize(
  FolderEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.emoji.length * 3;
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _folderEntitySerialize(
  FolderEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.color);
  writer.writeString(offsets[1], object.emoji);
  writer.writeString(offsets[2], object.name);
  writer.writeLong(offsets[3], object.parentId);
  writer.writeLong(offsets[4], object.position);
}

FolderEntity _folderEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = FolderEntity();
  object.color = reader.readLong(offsets[0]);
  object.emoji = reader.readString(offsets[1]);
  object.id = id;
  object.name = reader.readString(offsets[2]);
  object.parentId = reader.readLongOrNull(offsets[3]);
  object.position = reader.readLong(offsets[4]);
  return object;
}

P _folderEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLongOrNull(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _folderEntityGetId(FolderEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _folderEntityGetLinks(FolderEntity object) {
  return [];
}

void _folderEntityAttach(
    IsarCollection<dynamic> col, Id id, FolderEntity object) {
  object.id = id;
}

const NotebookEntitySchema = CollectionSchema(
  name: r'NotebookEntity',
  id: -429147861698866060,
  properties: {
    r'coverId': PropertySchema(
      id: 0,
      name: r'coverId',
      type: IsarType.string,
    ),
    r'coverImagePath': PropertySchema(
      id: 1,
      name: r'coverImagePath',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 2,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'deleted': PropertySchema(
      id: 3,
      name: r'deleted',
      type: IsarType.bool,
    ),
    r'deletedAt': PropertySchema(
      id: 4,
      name: r'deletedAt',
      type: IsarType.dateTime,
    ),
    r'favorite': PropertySchema(
      id: 5,
      name: r'favorite',
      type: IsarType.bool,
    ),
    r'folderId': PropertySchema(
      id: 6,
      name: r'folderId',
      type: IsarType.long,
    ),
    r'modifiedAt': PropertySchema(
      id: 7,
      name: r'modifiedAt',
      type: IsarType.dateTime,
    ),
    r'openedAt': PropertySchema(
      id: 8,
      name: r'openedAt',
      type: IsarType.dateTime,
    ),
    r'pageSize': PropertySchema(
      id: 9,
      name: r'pageSize',
      type: IsarType.long,
    ),
    r'paperColor': PropertySchema(
      id: 10,
      name: r'paperColor',
      type: IsarType.long,
    ),
    r'pdfPath': PropertySchema(
      id: 11,
      name: r'pdfPath',
      type: IsarType.string,
    ),
    r'tagIds': PropertySchema(
      id: 12,
      name: r'tagIds',
      type: IsarType.longList,
    ),
    r'template': PropertySchema(
      id: 13,
      name: r'template',
      type: IsarType.long,
    ),
    r'textIndex': PropertySchema(
      id: 14,
      name: r'textIndex',
      type: IsarType.string,
    ),
    r'title': PropertySchema(
      id: 15,
      name: r'title',
      type: IsarType.string,
    )
  },
  estimateSize: _notebookEntityEstimateSize,
  serialize: _notebookEntitySerialize,
  deserialize: _notebookEntityDeserialize,
  deserializeProp: _notebookEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _notebookEntityGetId,
  getLinks: _notebookEntityGetLinks,
  attach: _notebookEntityAttach,
  version: '3.1.0+1',
);

int _notebookEntityEstimateSize(
  NotebookEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.coverId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.coverImagePath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.pdfPath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.tagIds.length * 8;
  bytesCount += 3 + object.textIndex.length * 3;
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _notebookEntitySerialize(
  NotebookEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.coverId);
  writer.writeString(offsets[1], object.coverImagePath);
  writer.writeDateTime(offsets[2], object.createdAt);
  writer.writeBool(offsets[3], object.deleted);
  writer.writeDateTime(offsets[4], object.deletedAt);
  writer.writeBool(offsets[5], object.favorite);
  writer.writeLong(offsets[6], object.folderId);
  writer.writeDateTime(offsets[7], object.modifiedAt);
  writer.writeDateTime(offsets[8], object.openedAt);
  writer.writeLong(offsets[9], object.pageSize);
  writer.writeLong(offsets[10], object.paperColor);
  writer.writeString(offsets[11], object.pdfPath);
  writer.writeLongList(offsets[12], object.tagIds);
  writer.writeLong(offsets[13], object.template);
  writer.writeString(offsets[14], object.textIndex);
  writer.writeString(offsets[15], object.title);
}

NotebookEntity _notebookEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = NotebookEntity();
  object.coverId = reader.readStringOrNull(offsets[0]);
  object.coverImagePath = reader.readStringOrNull(offsets[1]);
  object.createdAt = reader.readDateTime(offsets[2]);
  object.deleted = reader.readBool(offsets[3]);
  object.deletedAt = reader.readDateTimeOrNull(offsets[4]);
  object.favorite = reader.readBool(offsets[5]);
  object.folderId = reader.readLongOrNull(offsets[6]);
  object.id = id;
  object.modifiedAt = reader.readDateTime(offsets[7]);
  object.openedAt = reader.readDateTime(offsets[8]);
  object.pageSize = reader.readLong(offsets[9]);
  object.paperColor = reader.readLong(offsets[10]);
  object.pdfPath = reader.readStringOrNull(offsets[11]);
  object.tagIds = reader.readLongList(offsets[12]) ?? [];
  object.template = reader.readLong(offsets[13]);
  object.textIndex = reader.readString(offsets[14]);
  object.title = reader.readString(offsets[15]);
  return object;
}

P _notebookEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readDateTime(offset)) as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 5:
      return (reader.readBool(offset)) as P;
    case 6:
      return (reader.readLongOrNull(offset)) as P;
    case 7:
      return (reader.readDateTime(offset)) as P;
    case 8:
      return (reader.readDateTime(offset)) as P;
    case 9:
      return (reader.readLong(offset)) as P;
    case 10:
      return (reader.readLong(offset)) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readLongList(offset) ?? []) as P;
    case 13:
      return (reader.readLong(offset)) as P;
    case 14:
      return (reader.readString(offset)) as P;
    case 15:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _notebookEntityGetId(NotebookEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _notebookEntityGetLinks(NotebookEntity object) {
  return [];
}

void _notebookEntityAttach(
    IsarCollection<dynamic> col, Id id, NotebookEntity object) {
  object.id = id;
}

const PageEntitySchema = CollectionSchema(
  name: r'PageEntity',
  id: 7780399719172098451,
  properties: {
    r'bookmarked': PropertySchema(
      id: 0,
      name: r'bookmarked',
      type: IsarType.bool,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'modifiedAt': PropertySchema(
      id: 2,
      name: r'modifiedAt',
      type: IsarType.dateTime,
    ),
    r'notebookId': PropertySchema(
      id: 3,
      name: r'notebookId',
      type: IsarType.long,
    ),
    r'pageSize': PropertySchema(
      id: 4,
      name: r'pageSize',
      type: IsarType.long,
    ),
    r'paperColor': PropertySchema(
      id: 5,
      name: r'paperColor',
      type: IsarType.long,
    ),
    r'position': PropertySchema(
      id: 6,
      name: r'position',
      type: IsarType.long,
    ),
    r'template': PropertySchema(
      id: 7,
      name: r'template',
      type: IsarType.long,
    ),
    r'title': PropertySchema(
      id: 8,
      name: r'title',
      type: IsarType.string,
    )
  },
  estimateSize: _pageEntityEstimateSize,
  serialize: _pageEntitySerialize,
  deserialize: _pageEntityDeserialize,
  deserializeProp: _pageEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _pageEntityGetId,
  getLinks: _pageEntityGetLinks,
  attach: _pageEntityAttach,
  version: '3.1.0+1',
);

int _pageEntityEstimateSize(
  PageEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _pageEntitySerialize(
  PageEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.bookmarked);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeDateTime(offsets[2], object.modifiedAt);
  writer.writeLong(offsets[3], object.notebookId);
  writer.writeLong(offsets[4], object.pageSize);
  writer.writeLong(offsets[5], object.paperColor);
  writer.writeLong(offsets[6], object.position);
  writer.writeLong(offsets[7], object.template);
  writer.writeString(offsets[8], object.title);
}

PageEntity _pageEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PageEntity();
  object.bookmarked = reader.readBool(offsets[0]);
  object.createdAt = reader.readDateTime(offsets[1]);
  object.id = id;
  object.modifiedAt = reader.readDateTime(offsets[2]);
  object.notebookId = reader.readLong(offsets[3]);
  object.pageSize = reader.readLong(offsets[4]);
  object.paperColor = reader.readLong(offsets[5]);
  object.position = reader.readLong(offsets[6]);
  object.template = reader.readLong(offsets[7]);
  object.title = reader.readString(offsets[8]);
  return object;
}

P _pageEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readDateTime(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    case 7:
      return (reader.readLong(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _pageEntityGetId(PageEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _pageEntityGetLinks(PageEntity object) {
  return [];
}

void _pageEntityAttach(IsarCollection<dynamic> col, Id id, PageEntity object) {
  object.id = id;
}

const TagEntitySchema = CollectionSchema(
  name: r'TagEntity',
  id: -1285872882773628843,
  properties: {
    r'color': PropertySchema(
      id: 0,
      name: r'color',
      type: IsarType.long,
    ),
    r'name': PropertySchema(
      id: 1,
      name: r'name',
      type: IsarType.string,
    )
  },
  estimateSize: _tagEntityEstimateSize,
  serialize: _tagEntitySerialize,
  deserialize: _tagEntityDeserialize,
  deserializeProp: _tagEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _tagEntityGetId,
  getLinks: _tagEntityGetLinks,
  attach: _tagEntityAttach,
  version: '3.1.0+1',
);

int _tagEntityEstimateSize(
  TagEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _tagEntitySerialize(
  TagEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.color);
  writer.writeString(offsets[1], object.name);
}

TagEntity _tagEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = TagEntity();
  object.color = reader.readLong(offsets[0]);
  object.id = id;
  object.name = reader.readString(offsets[1]);
  return object;
}

P _tagEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _tagEntityGetId(TagEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _tagEntityGetLinks(TagEntity object) {
  return [];
}

void _tagEntityAttach(IsarCollection<dynamic> col, Id id, TagEntity object) {
  object.id = id;
}

const RecordingEntitySchema = CollectionSchema(
  name: r'RecordingEntity',
  id: -6075811757528234417,
  properties: {
    r'createdAt': PropertySchema(
      id: 0,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'durationMs': PropertySchema(
      id: 1,
      name: r'durationMs',
      type: IsarType.long,
    ),
    r'notebookId': PropertySchema(
      id: 2,
      name: r'notebookId',
      type: IsarType.long,
    ),
    r'pageId': PropertySchema(
      id: 3,
      name: r'pageId',
      type: IsarType.long,
    ),
    r'path': PropertySchema(
      id: 4,
      name: r'path',
      type: IsarType.string,
    )
  },
  estimateSize: _recordingEntityEstimateSize,
  serialize: _recordingEntitySerialize,
  deserialize: _recordingEntityDeserialize,
  deserializeProp: _recordingEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _recordingEntityGetId,
  getLinks: _recordingEntityGetLinks,
  attach: _recordingEntityAttach,
  version: '3.1.0+1',
);

int _recordingEntityEstimateSize(
  RecordingEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.path.length * 3;
  return bytesCount;
}

void _recordingEntitySerialize(
  RecordingEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.createdAt);
  writer.writeLong(offsets[1], object.durationMs);
  writer.writeLong(offsets[2], object.notebookId);
  writer.writeLong(offsets[3], object.pageId);
  writer.writeString(offsets[4], object.path);
}

RecordingEntity _recordingEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = RecordingEntity();
  object.createdAt = reader.readDateTime(offsets[0]);
  object.durationMs = reader.readLong(offsets[1]);
  object.id = id;
  object.notebookId = reader.readLong(offsets[2]);
  object.pageId = reader.readLong(offsets[3]);
  object.path = reader.readString(offsets[4]);
  return object;
}

P _recordingEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _recordingEntityGetId(RecordingEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _recordingEntityGetLinks(RecordingEntity object) {
  return [];
}

void _recordingEntityAttach(
    IsarCollection<dynamic> col, Id id, RecordingEntity object) {
  object.id = id;
}

const StrokeEntitySchema = CollectionSchema(
  name: r'StrokeEntity',
  id: 1652844139129545802,
  properties: {
    r'data': PropertySchema(
      id: 0,
      name: r'data',
      type: IsarType.string,
    ),
    r'pageId': PropertySchema(
      id: 1,
      name: r'pageId',
      type: IsarType.long,
    ),
    r'z': PropertySchema(
      id: 2,
      name: r'z',
      type: IsarType.long,
    )
  },
  estimateSize: _strokeEntityEstimateSize,
  serialize: _strokeEntitySerialize,
  deserialize: _strokeEntityDeserialize,
  deserializeProp: _strokeEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _strokeEntityGetId,
  getLinks: _strokeEntityGetLinks,
  attach: _strokeEntityAttach,
  version: '3.1.0+1',
);

int _strokeEntityEstimateSize(
  StrokeEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.data.length * 3;
  return bytesCount;
}

void _strokeEntitySerialize(
  StrokeEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.data);
  writer.writeLong(offsets[1], object.pageId);
  writer.writeLong(offsets[2], object.z);
}

StrokeEntity _strokeEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = StrokeEntity();
  object.data = reader.readString(offsets[0]);
  object.id = id;
  object.pageId = reader.readLong(offsets[1]);
  object.z = reader.readLong(offsets[2]);
  return object;
}

P _strokeEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _strokeEntityGetId(StrokeEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _strokeEntityGetLinks(StrokeEntity object) {
  return [];
}

void _strokeEntityAttach(
    IsarCollection<dynamic> col, Id id, StrokeEntity object) {
  object.id = id;
}

const ElementEntitySchema = CollectionSchema(
  name: r'ElementEntity',
  id: -1714169614459029146,
  properties: {
    r'data': PropertySchema(
      id: 0,
      name: r'data',
      type: IsarType.string,
    ),
    r'pageId': PropertySchema(
      id: 1,
      name: r'pageId',
      type: IsarType.long,
    ),
    r'z': PropertySchema(
      id: 2,
      name: r'z',
      type: IsarType.long,
    )
  },
  estimateSize: _elementEntityEstimateSize,
  serialize: _elementEntitySerialize,
  deserialize: _elementEntityDeserialize,
  deserializeProp: _elementEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _elementEntityGetId,
  getLinks: _elementEntityGetLinks,
  attach: _elementEntityAttach,
  version: '3.1.0+1',
);

int _elementEntityEstimateSize(
  ElementEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.data.length * 3;
  return bytesCount;
}

void _elementEntitySerialize(
  ElementEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.data);
  writer.writeLong(offsets[1], object.pageId);
  writer.writeLong(offsets[2], object.z);
}

ElementEntity _elementEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ElementEntity();
  object.data = reader.readString(offsets[0]);
  object.id = id;
  object.pageId = reader.readLong(offsets[1]);
  object.z = reader.readLong(offsets[2]);
  return object;
}

P _elementEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _elementEntityGetId(ElementEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _elementEntityGetLinks(ElementEntity object) {
  return [];
}

void _elementEntityAttach(
    IsarCollection<dynamic> col, Id id, ElementEntity object) {
  object.id = id;
}
