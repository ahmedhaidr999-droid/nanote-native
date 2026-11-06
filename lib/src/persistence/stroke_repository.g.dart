// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stroke_repository.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetStrokeEntityCollection on Isar {
  IsarCollection<StrokeEntity> get strokeEntitys => this.collection();
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

extension StrokeEntityQueryWhereSort
    on QueryBuilder<StrokeEntity, StrokeEntity, QWhere> {
  QueryBuilder<StrokeEntity, StrokeEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension StrokeEntityQueryWhere
    on QueryBuilder<StrokeEntity, StrokeEntity, QWhereClause> {
  QueryBuilder<StrokeEntity, StrokeEntity, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension StrokeEntityQueryFilter
    on QueryBuilder<StrokeEntity, StrokeEntity, QFilterCondition> {
  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> dataEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition>
      dataGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> dataLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> dataBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'data',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition>
      dataStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> dataEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> dataContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> dataMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'data',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition>
      dataIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'data',
        value: '',
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition>
      dataIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'data',
        value: '',
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> pageIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pageId',
        value: value,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition>
      pageIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'pageId',
        value: value,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition>
      pageIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'pageId',
        value: value,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> pageIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'pageId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> zEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'z',
        value: value,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> zGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'z',
        value: value,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> zLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'z',
        value: value,
      ));
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterFilterCondition> zBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'z',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension StrokeEntityQueryObject
    on QueryBuilder<StrokeEntity, StrokeEntity, QFilterCondition> {}

extension StrokeEntityQueryLinks
    on QueryBuilder<StrokeEntity, StrokeEntity, QFilterCondition> {}

extension StrokeEntityQuerySortBy
    on QueryBuilder<StrokeEntity, StrokeEntity, QSortBy> {
  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> sortByData() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.asc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> sortByDataDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.desc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> sortByPageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageId', Sort.asc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> sortByPageIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageId', Sort.desc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> sortByZ() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'z', Sort.asc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> sortByZDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'z', Sort.desc);
    });
  }
}

extension StrokeEntityQuerySortThenBy
    on QueryBuilder<StrokeEntity, StrokeEntity, QSortThenBy> {
  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> thenByData() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.asc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> thenByDataDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.desc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> thenByPageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageId', Sort.asc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> thenByPageIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageId', Sort.desc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> thenByZ() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'z', Sort.asc);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QAfterSortBy> thenByZDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'z', Sort.desc);
    });
  }
}

extension StrokeEntityQueryWhereDistinct
    on QueryBuilder<StrokeEntity, StrokeEntity, QDistinct> {
  QueryBuilder<StrokeEntity, StrokeEntity, QDistinct> distinctByData(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'data', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QDistinct> distinctByPageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pageId');
    });
  }

  QueryBuilder<StrokeEntity, StrokeEntity, QDistinct> distinctByZ() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'z');
    });
  }
}

extension StrokeEntityQueryProperty
    on QueryBuilder<StrokeEntity, StrokeEntity, QQueryProperty> {
  QueryBuilder<StrokeEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<StrokeEntity, String, QQueryOperations> dataProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'data');
    });
  }

  QueryBuilder<StrokeEntity, int, QQueryOperations> pageIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pageId');
    });
  }

  QueryBuilder<StrokeEntity, int, QQueryOperations> zProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'z');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetElementEntityCollection on Isar {
  IsarCollection<ElementEntity> get elementEntitys => this.collection();
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

extension ElementEntityQueryWhereSort
    on QueryBuilder<ElementEntity, ElementEntity, QWhere> {
  QueryBuilder<ElementEntity, ElementEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension ElementEntityQueryWhere
    on QueryBuilder<ElementEntity, ElementEntity, QWhereClause> {
  QueryBuilder<ElementEntity, ElementEntity, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ElementEntityQueryFilter
    on QueryBuilder<ElementEntity, ElementEntity, QFilterCondition> {
  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition> dataEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      dataGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      dataLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition> dataBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'data',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      dataStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      dataEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      dataContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'data',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition> dataMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'data',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      dataIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'data',
        value: '',
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      dataIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'data',
        value: '',
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      pageIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pageId',
        value: value,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      pageIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'pageId',
        value: value,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      pageIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'pageId',
        value: value,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      pageIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'pageId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition> zEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'z',
        value: value,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition>
      zGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'z',
        value: value,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition> zLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'z',
        value: value,
      ));
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterFilterCondition> zBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'z',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ElementEntityQueryObject
    on QueryBuilder<ElementEntity, ElementEntity, QFilterCondition> {}

extension ElementEntityQueryLinks
    on QueryBuilder<ElementEntity, ElementEntity, QFilterCondition> {}

extension ElementEntityQuerySortBy
    on QueryBuilder<ElementEntity, ElementEntity, QSortBy> {
  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> sortByData() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.asc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> sortByDataDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.desc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> sortByPageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageId', Sort.asc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> sortByPageIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageId', Sort.desc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> sortByZ() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'z', Sort.asc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> sortByZDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'z', Sort.desc);
    });
  }
}

extension ElementEntityQuerySortThenBy
    on QueryBuilder<ElementEntity, ElementEntity, QSortThenBy> {
  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> thenByData() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.asc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> thenByDataDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'data', Sort.desc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> thenByPageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageId', Sort.asc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> thenByPageIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageId', Sort.desc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> thenByZ() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'z', Sort.asc);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QAfterSortBy> thenByZDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'z', Sort.desc);
    });
  }
}

extension ElementEntityQueryWhereDistinct
    on QueryBuilder<ElementEntity, ElementEntity, QDistinct> {
  QueryBuilder<ElementEntity, ElementEntity, QDistinct> distinctByData(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'data', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QDistinct> distinctByPageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pageId');
    });
  }

  QueryBuilder<ElementEntity, ElementEntity, QDistinct> distinctByZ() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'z');
    });
  }
}

extension ElementEntityQueryProperty
    on QueryBuilder<ElementEntity, ElementEntity, QQueryProperty> {
  QueryBuilder<ElementEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ElementEntity, String, QQueryOperations> dataProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'data');
    });
  }

  QueryBuilder<ElementEntity, int, QQueryOperations> pageIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pageId');
    });
  }

  QueryBuilder<ElementEntity, int, QQueryOperations> zProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'z');
    });
  }
}
