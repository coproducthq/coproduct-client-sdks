// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InitError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'InitError()';
}


}

/// @nodoc
class $InitErrorCopyWith<$Res>  {
$InitErrorCopyWith(InitError _, $Res Function(InitError) __);
}


/// Adds pattern-matching-related methods to [InitError].
extension InitErrorPatterns on InitError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( InitError_InvalidKeyType value)?  invalidKeyType,TResult Function( InitError_MalformedSdkKey value)?  malformedSdkKey,TResult Function( InitError_MissingSdkKey value)?  missingSdkKey,TResult Function( InitError_InvalidConfig value)?  invalidConfig,TResult Function( InitError_UnsupportedSchemaVersion value)?  unsupportedSchemaVersion,required TResult orElse(),}){
final _that = this;
switch (_that) {
case InitError_InvalidKeyType() when invalidKeyType != null:
return invalidKeyType(_that);case InitError_MalformedSdkKey() when malformedSdkKey != null:
return malformedSdkKey(_that);case InitError_MissingSdkKey() when missingSdkKey != null:
return missingSdkKey(_that);case InitError_InvalidConfig() when invalidConfig != null:
return invalidConfig(_that);case InitError_UnsupportedSchemaVersion() when unsupportedSchemaVersion != null:
return unsupportedSchemaVersion(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( InitError_InvalidKeyType value)  invalidKeyType,required TResult Function( InitError_MalformedSdkKey value)  malformedSdkKey,required TResult Function( InitError_MissingSdkKey value)  missingSdkKey,required TResult Function( InitError_InvalidConfig value)  invalidConfig,required TResult Function( InitError_UnsupportedSchemaVersion value)  unsupportedSchemaVersion,}){
final _that = this;
switch (_that) {
case InitError_InvalidKeyType():
return invalidKeyType(_that);case InitError_MalformedSdkKey():
return malformedSdkKey(_that);case InitError_MissingSdkKey():
return missingSdkKey(_that);case InitError_InvalidConfig():
return invalidConfig(_that);case InitError_UnsupportedSchemaVersion():
return unsupportedSchemaVersion(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( InitError_InvalidKeyType value)?  invalidKeyType,TResult? Function( InitError_MalformedSdkKey value)?  malformedSdkKey,TResult? Function( InitError_MissingSdkKey value)?  missingSdkKey,TResult? Function( InitError_InvalidConfig value)?  invalidConfig,TResult? Function( InitError_UnsupportedSchemaVersion value)?  unsupportedSchemaVersion,}){
final _that = this;
switch (_that) {
case InitError_InvalidKeyType() when invalidKeyType != null:
return invalidKeyType(_that);case InitError_MalformedSdkKey() when malformedSdkKey != null:
return malformedSdkKey(_that);case InitError_MissingSdkKey() when missingSdkKey != null:
return missingSdkKey(_that);case InitError_InvalidConfig() when invalidConfig != null:
return invalidConfig(_that);case InitError_UnsupportedSchemaVersion() when unsupportedSchemaVersion != null:
return unsupportedSchemaVersion(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String prefix)?  invalidKeyType,TResult Function( String reason)?  malformedSdkKey,TResult Function()?  missingSdkKey,TResult Function( String field,  String reason)?  invalidConfig,TResult Function( int actual,  int supported)?  unsupportedSchemaVersion,required TResult orElse(),}) {final _that = this;
switch (_that) {
case InitError_InvalidKeyType() when invalidKeyType != null:
return invalidKeyType(_that.prefix);case InitError_MalformedSdkKey() when malformedSdkKey != null:
return malformedSdkKey(_that.reason);case InitError_MissingSdkKey() when missingSdkKey != null:
return missingSdkKey();case InitError_InvalidConfig() when invalidConfig != null:
return invalidConfig(_that.field,_that.reason);case InitError_UnsupportedSchemaVersion() when unsupportedSchemaVersion != null:
return unsupportedSchemaVersion(_that.actual,_that.supported);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String prefix)  invalidKeyType,required TResult Function( String reason)  malformedSdkKey,required TResult Function()  missingSdkKey,required TResult Function( String field,  String reason)  invalidConfig,required TResult Function( int actual,  int supported)  unsupportedSchemaVersion,}) {final _that = this;
switch (_that) {
case InitError_InvalidKeyType():
return invalidKeyType(_that.prefix);case InitError_MalformedSdkKey():
return malformedSdkKey(_that.reason);case InitError_MissingSdkKey():
return missingSdkKey();case InitError_InvalidConfig():
return invalidConfig(_that.field,_that.reason);case InitError_UnsupportedSchemaVersion():
return unsupportedSchemaVersion(_that.actual,_that.supported);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String prefix)?  invalidKeyType,TResult? Function( String reason)?  malformedSdkKey,TResult? Function()?  missingSdkKey,TResult? Function( String field,  String reason)?  invalidConfig,TResult? Function( int actual,  int supported)?  unsupportedSchemaVersion,}) {final _that = this;
switch (_that) {
case InitError_InvalidKeyType() when invalidKeyType != null:
return invalidKeyType(_that.prefix);case InitError_MalformedSdkKey() when malformedSdkKey != null:
return malformedSdkKey(_that.reason);case InitError_MissingSdkKey() when missingSdkKey != null:
return missingSdkKey();case InitError_InvalidConfig() when invalidConfig != null:
return invalidConfig(_that.field,_that.reason);case InitError_UnsupportedSchemaVersion() when unsupportedSchemaVersion != null:
return unsupportedSchemaVersion(_that.actual,_that.supported);case _:
  return null;

}
}

}

/// @nodoc


class InitError_InvalidKeyType extends InitError {
  const InitError_InvalidKeyType({required this.prefix}): super._();
  

 final  String prefix;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitError_InvalidKeyTypeCopyWith<InitError_InvalidKeyType> get copyWith => _$InitError_InvalidKeyTypeCopyWithImpl<InitError_InvalidKeyType>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError_InvalidKeyType&&(identical(other.prefix, prefix) || other.prefix == prefix));
}


@override
int get hashCode => Object.hash(runtimeType,prefix);

@override
String toString() {
  return 'InitError.invalidKeyType(prefix: $prefix)';
}


}

/// @nodoc
abstract mixin class $InitError_InvalidKeyTypeCopyWith<$Res> implements $InitErrorCopyWith<$Res> {
  factory $InitError_InvalidKeyTypeCopyWith(InitError_InvalidKeyType value, $Res Function(InitError_InvalidKeyType) _then) = _$InitError_InvalidKeyTypeCopyWithImpl;
@useResult
$Res call({
 String prefix
});




}
/// @nodoc
class _$InitError_InvalidKeyTypeCopyWithImpl<$Res>
    implements $InitError_InvalidKeyTypeCopyWith<$Res> {
  _$InitError_InvalidKeyTypeCopyWithImpl(this._self, this._then);

  final InitError_InvalidKeyType _self;
  final $Res Function(InitError_InvalidKeyType) _then;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? prefix = null,}) {
  return _then(InitError_InvalidKeyType(
prefix: null == prefix ? _self.prefix : prefix // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class InitError_MalformedSdkKey extends InitError {
  const InitError_MalformedSdkKey({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitError_MalformedSdkKeyCopyWith<InitError_MalformedSdkKey> get copyWith => _$InitError_MalformedSdkKeyCopyWithImpl<InitError_MalformedSdkKey>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError_MalformedSdkKey&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'InitError.malformedSdkKey(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $InitError_MalformedSdkKeyCopyWith<$Res> implements $InitErrorCopyWith<$Res> {
  factory $InitError_MalformedSdkKeyCopyWith(InitError_MalformedSdkKey value, $Res Function(InitError_MalformedSdkKey) _then) = _$InitError_MalformedSdkKeyCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$InitError_MalformedSdkKeyCopyWithImpl<$Res>
    implements $InitError_MalformedSdkKeyCopyWith<$Res> {
  _$InitError_MalformedSdkKeyCopyWithImpl(this._self, this._then);

  final InitError_MalformedSdkKey _self;
  final $Res Function(InitError_MalformedSdkKey) _then;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(InitError_MalformedSdkKey(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class InitError_MissingSdkKey extends InitError {
  const InitError_MissingSdkKey(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError_MissingSdkKey);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'InitError.missingSdkKey()';
}


}




/// @nodoc


class InitError_InvalidConfig extends InitError {
  const InitError_InvalidConfig({required this.field, required this.reason}): super._();
  

 final  String field;
 final  String reason;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitError_InvalidConfigCopyWith<InitError_InvalidConfig> get copyWith => _$InitError_InvalidConfigCopyWithImpl<InitError_InvalidConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError_InvalidConfig&&(identical(other.field, field) || other.field == field)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,field,reason);

@override
String toString() {
  return 'InitError.invalidConfig(field: $field, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $InitError_InvalidConfigCopyWith<$Res> implements $InitErrorCopyWith<$Res> {
  factory $InitError_InvalidConfigCopyWith(InitError_InvalidConfig value, $Res Function(InitError_InvalidConfig) _then) = _$InitError_InvalidConfigCopyWithImpl;
@useResult
$Res call({
 String field, String reason
});




}
/// @nodoc
class _$InitError_InvalidConfigCopyWithImpl<$Res>
    implements $InitError_InvalidConfigCopyWith<$Res> {
  _$InitError_InvalidConfigCopyWithImpl(this._self, this._then);

  final InitError_InvalidConfig _self;
  final $Res Function(InitError_InvalidConfig) _then;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field = null,Object? reason = null,}) {
  return _then(InitError_InvalidConfig(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class InitError_UnsupportedSchemaVersion extends InitError {
  const InitError_UnsupportedSchemaVersion({required this.actual, required this.supported}): super._();
  

 final  int actual;
 final  int supported;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitError_UnsupportedSchemaVersionCopyWith<InitError_UnsupportedSchemaVersion> get copyWith => _$InitError_UnsupportedSchemaVersionCopyWithImpl<InitError_UnsupportedSchemaVersion>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError_UnsupportedSchemaVersion&&(identical(other.actual, actual) || other.actual == actual)&&(identical(other.supported, supported) || other.supported == supported));
}


@override
int get hashCode => Object.hash(runtimeType,actual,supported);

@override
String toString() {
  return 'InitError.unsupportedSchemaVersion(actual: $actual, supported: $supported)';
}


}

/// @nodoc
abstract mixin class $InitError_UnsupportedSchemaVersionCopyWith<$Res> implements $InitErrorCopyWith<$Res> {
  factory $InitError_UnsupportedSchemaVersionCopyWith(InitError_UnsupportedSchemaVersion value, $Res Function(InitError_UnsupportedSchemaVersion) _then) = _$InitError_UnsupportedSchemaVersionCopyWithImpl;
@useResult
$Res call({
 int actual, int supported
});




}
/// @nodoc
class _$InitError_UnsupportedSchemaVersionCopyWithImpl<$Res>
    implements $InitError_UnsupportedSchemaVersionCopyWith<$Res> {
  _$InitError_UnsupportedSchemaVersionCopyWithImpl(this._self, this._then);

  final InitError_UnsupportedSchemaVersion _self;
  final $Res Function(InitError_UnsupportedSchemaVersion) _then;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? actual = null,Object? supported = null,}) {
  return _then(InitError_UnsupportedSchemaVersion(
actual: null == actual ? _self.actual : actual // ignore: cast_nullable_to_non_nullable
as int,supported: null == supported ? _self.supported : supported // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
