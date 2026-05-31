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

 String get field0;
/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitErrorCopyWith<InitError> get copyWith => _$InitErrorCopyWithImpl<InitError>(this as InitError, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'InitError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $InitErrorCopyWith<$Res>  {
  factory $InitErrorCopyWith(InitError value, $Res Function(InitError) _then) = _$InitErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$InitErrorCopyWithImpl<$Res>
    implements $InitErrorCopyWith<$Res> {
  _$InitErrorCopyWithImpl(this._self, this._then);

  final InitError _self;
  final $Res Function(InitError) _then;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field0 = null,}) {
  return _then(_self.copyWith(
field0: null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( InitError_Transport value)?  transport,TResult Function( InitError_SecureStore value)?  secureStore,TResult Function( InitError_Cache value)?  cache,required TResult orElse(),}){
final _that = this;
switch (_that) {
case InitError_Transport() when transport != null:
return transport(_that);case InitError_SecureStore() when secureStore != null:
return secureStore(_that);case InitError_Cache() when cache != null:
return cache(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( InitError_Transport value)  transport,required TResult Function( InitError_SecureStore value)  secureStore,required TResult Function( InitError_Cache value)  cache,}){
final _that = this;
switch (_that) {
case InitError_Transport():
return transport(_that);case InitError_SecureStore():
return secureStore(_that);case InitError_Cache():
return cache(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( InitError_Transport value)?  transport,TResult? Function( InitError_SecureStore value)?  secureStore,TResult? Function( InitError_Cache value)?  cache,}){
final _that = this;
switch (_that) {
case InitError_Transport() when transport != null:
return transport(_that);case InitError_SecureStore() when secureStore != null:
return secureStore(_that);case InitError_Cache() when cache != null:
return cache(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  transport,TResult Function( String field0)?  secureStore,TResult Function( String field0)?  cache,required TResult orElse(),}) {final _that = this;
switch (_that) {
case InitError_Transport() when transport != null:
return transport(_that.field0);case InitError_SecureStore() when secureStore != null:
return secureStore(_that.field0);case InitError_Cache() when cache != null:
return cache(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  transport,required TResult Function( String field0)  secureStore,required TResult Function( String field0)  cache,}) {final _that = this;
switch (_that) {
case InitError_Transport():
return transport(_that.field0);case InitError_SecureStore():
return secureStore(_that.field0);case InitError_Cache():
return cache(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  transport,TResult? Function( String field0)?  secureStore,TResult? Function( String field0)?  cache,}) {final _that = this;
switch (_that) {
case InitError_Transport() when transport != null:
return transport(_that.field0);case InitError_SecureStore() when secureStore != null:
return secureStore(_that.field0);case InitError_Cache() when cache != null:
return cache(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class InitError_Transport extends InitError {
  const InitError_Transport(this.field0): super._();
  

@override final  String field0;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitError_TransportCopyWith<InitError_Transport> get copyWith => _$InitError_TransportCopyWithImpl<InitError_Transport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError_Transport&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'InitError.transport(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $InitError_TransportCopyWith<$Res> implements $InitErrorCopyWith<$Res> {
  factory $InitError_TransportCopyWith(InitError_Transport value, $Res Function(InitError_Transport) _then) = _$InitError_TransportCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$InitError_TransportCopyWithImpl<$Res>
    implements $InitError_TransportCopyWith<$Res> {
  _$InitError_TransportCopyWithImpl(this._self, this._then);

  final InitError_Transport _self;
  final $Res Function(InitError_Transport) _then;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(InitError_Transport(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class InitError_SecureStore extends InitError {
  const InitError_SecureStore(this.field0): super._();
  

@override final  String field0;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitError_SecureStoreCopyWith<InitError_SecureStore> get copyWith => _$InitError_SecureStoreCopyWithImpl<InitError_SecureStore>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError_SecureStore&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'InitError.secureStore(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $InitError_SecureStoreCopyWith<$Res> implements $InitErrorCopyWith<$Res> {
  factory $InitError_SecureStoreCopyWith(InitError_SecureStore value, $Res Function(InitError_SecureStore) _then) = _$InitError_SecureStoreCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$InitError_SecureStoreCopyWithImpl<$Res>
    implements $InitError_SecureStoreCopyWith<$Res> {
  _$InitError_SecureStoreCopyWithImpl(this._self, this._then);

  final InitError_SecureStore _self;
  final $Res Function(InitError_SecureStore) _then;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(InitError_SecureStore(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class InitError_Cache extends InitError {
  const InitError_Cache(this.field0): super._();
  

@override final  String field0;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitError_CacheCopyWith<InitError_Cache> get copyWith => _$InitError_CacheCopyWithImpl<InitError_Cache>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitError_Cache&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'InitError.cache(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $InitError_CacheCopyWith<$Res> implements $InitErrorCopyWith<$Res> {
  factory $InitError_CacheCopyWith(InitError_Cache value, $Res Function(InitError_Cache) _then) = _$InitError_CacheCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$InitError_CacheCopyWithImpl<$Res>
    implements $InitError_CacheCopyWith<$Res> {
  _$InitError_CacheCopyWithImpl(this._self, this._then);

  final InitError_Cache _self;
  final $Res Function(InitError_Cache) _then;

/// Create a copy of InitError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(InitError_Cache(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
