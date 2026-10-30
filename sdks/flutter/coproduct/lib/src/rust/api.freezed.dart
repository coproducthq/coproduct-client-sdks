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
mixin _$FrbContextValue {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbContextValue);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FrbContextValue()';
}


}

/// @nodoc
class $FrbContextValueCopyWith<$Res>  {
$FrbContextValueCopyWith(FrbContextValue _, $Res Function(FrbContextValue) __);
}


/// Adds pattern-matching-related methods to [FrbContextValue].
extension FrbContextValuePatterns on FrbContextValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FrbContextValue_String value)?  string,TResult Function( FrbContextValue_Number value)?  number,TResult Function( FrbContextValue_Bool value)?  bool,TResult Function( FrbContextValue_StringList value)?  stringList,TResult Function( FrbContextValue_NumberList value)?  numberList,TResult Function( FrbContextValue_Null value)?  null_,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FrbContextValue_String() when string != null:
return string(_that);case FrbContextValue_Number() when number != null:
return number(_that);case FrbContextValue_Bool() when bool != null:
return bool(_that);case FrbContextValue_StringList() when stringList != null:
return stringList(_that);case FrbContextValue_NumberList() when numberList != null:
return numberList(_that);case FrbContextValue_Null() when null_ != null:
return null_(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FrbContextValue_String value)  string,required TResult Function( FrbContextValue_Number value)  number,required TResult Function( FrbContextValue_Bool value)  bool,required TResult Function( FrbContextValue_StringList value)  stringList,required TResult Function( FrbContextValue_NumberList value)  numberList,required TResult Function( FrbContextValue_Null value)  null_,}){
final _that = this;
switch (_that) {
case FrbContextValue_String():
return string(_that);case FrbContextValue_Number():
return number(_that);case FrbContextValue_Bool():
return bool(_that);case FrbContextValue_StringList():
return stringList(_that);case FrbContextValue_NumberList():
return numberList(_that);case FrbContextValue_Null():
return null_(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FrbContextValue_String value)?  string,TResult? Function( FrbContextValue_Number value)?  number,TResult? Function( FrbContextValue_Bool value)?  bool,TResult? Function( FrbContextValue_StringList value)?  stringList,TResult? Function( FrbContextValue_NumberList value)?  numberList,TResult? Function( FrbContextValue_Null value)?  null_,}){
final _that = this;
switch (_that) {
case FrbContextValue_String() when string != null:
return string(_that);case FrbContextValue_Number() when number != null:
return number(_that);case FrbContextValue_Bool() when bool != null:
return bool(_that);case FrbContextValue_StringList() when stringList != null:
return stringList(_that);case FrbContextValue_NumberList() when numberList != null:
return numberList(_that);case FrbContextValue_Null() when null_ != null:
return null_(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  string,TResult Function( double field0)?  number,TResult Function( bool field0)?  bool,TResult Function( List<String> field0)?  stringList,TResult Function( Float64List field0)?  numberList,TResult Function()?  null_,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FrbContextValue_String() when string != null:
return string(_that.field0);case FrbContextValue_Number() when number != null:
return number(_that.field0);case FrbContextValue_Bool() when bool != null:
return bool(_that.field0);case FrbContextValue_StringList() when stringList != null:
return stringList(_that.field0);case FrbContextValue_NumberList() when numberList != null:
return numberList(_that.field0);case FrbContextValue_Null() when null_ != null:
return null_();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  string,required TResult Function( double field0)  number,required TResult Function( bool field0)  bool,required TResult Function( List<String> field0)  stringList,required TResult Function( Float64List field0)  numberList,required TResult Function()  null_,}) {final _that = this;
switch (_that) {
case FrbContextValue_String():
return string(_that.field0);case FrbContextValue_Number():
return number(_that.field0);case FrbContextValue_Bool():
return bool(_that.field0);case FrbContextValue_StringList():
return stringList(_that.field0);case FrbContextValue_NumberList():
return numberList(_that.field0);case FrbContextValue_Null():
return null_();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  string,TResult? Function( double field0)?  number,TResult? Function( bool field0)?  bool,TResult? Function( List<String> field0)?  stringList,TResult? Function( Float64List field0)?  numberList,TResult? Function()?  null_,}) {final _that = this;
switch (_that) {
case FrbContextValue_String() when string != null:
return string(_that.field0);case FrbContextValue_Number() when number != null:
return number(_that.field0);case FrbContextValue_Bool() when bool != null:
return bool(_that.field0);case FrbContextValue_StringList() when stringList != null:
return stringList(_that.field0);case FrbContextValue_NumberList() when numberList != null:
return numberList(_that.field0);case FrbContextValue_Null() when null_ != null:
return null_();case _:
  return null;

}
}

}

/// @nodoc


class FrbContextValue_String extends FrbContextValue {
  const FrbContextValue_String(this.field0): super._();
  

 final  String field0;

/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbContextValue_StringCopyWith<FrbContextValue_String> get copyWith => _$FrbContextValue_StringCopyWithImpl<FrbContextValue_String>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbContextValue_String&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'FrbContextValue.string(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FrbContextValue_StringCopyWith<$Res> implements $FrbContextValueCopyWith<$Res> {
  factory $FrbContextValue_StringCopyWith(FrbContextValue_String value, $Res Function(FrbContextValue_String) _then) = _$FrbContextValue_StringCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$FrbContextValue_StringCopyWithImpl<$Res>
    implements $FrbContextValue_StringCopyWith<$Res> {
  _$FrbContextValue_StringCopyWithImpl(this._self, this._then);

  final FrbContextValue_String _self;
  final $Res Function(FrbContextValue_String) _then;

/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FrbContextValue_String(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FrbContextValue_Number extends FrbContextValue {
  const FrbContextValue_Number(this.field0): super._();
  

 final  double field0;

/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbContextValue_NumberCopyWith<FrbContextValue_Number> get copyWith => _$FrbContextValue_NumberCopyWithImpl<FrbContextValue_Number>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbContextValue_Number&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'FrbContextValue.number(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FrbContextValue_NumberCopyWith<$Res> implements $FrbContextValueCopyWith<$Res> {
  factory $FrbContextValue_NumberCopyWith(FrbContextValue_Number value, $Res Function(FrbContextValue_Number) _then) = _$FrbContextValue_NumberCopyWithImpl;
@useResult
$Res call({
 double field0
});




}
/// @nodoc
class _$FrbContextValue_NumberCopyWithImpl<$Res>
    implements $FrbContextValue_NumberCopyWith<$Res> {
  _$FrbContextValue_NumberCopyWithImpl(this._self, this._then);

  final FrbContextValue_Number _self;
  final $Res Function(FrbContextValue_Number) _then;

/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FrbContextValue_Number(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class FrbContextValue_Bool extends FrbContextValue {
  const FrbContextValue_Bool(this.field0): super._();
  

 final  bool field0;

/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbContextValue_BoolCopyWith<FrbContextValue_Bool> get copyWith => _$FrbContextValue_BoolCopyWithImpl<FrbContextValue_Bool>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbContextValue_Bool&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'FrbContextValue.bool(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FrbContextValue_BoolCopyWith<$Res> implements $FrbContextValueCopyWith<$Res> {
  factory $FrbContextValue_BoolCopyWith(FrbContextValue_Bool value, $Res Function(FrbContextValue_Bool) _then) = _$FrbContextValue_BoolCopyWithImpl;
@useResult
$Res call({
 bool field0
});




}
/// @nodoc
class _$FrbContextValue_BoolCopyWithImpl<$Res>
    implements $FrbContextValue_BoolCopyWith<$Res> {
  _$FrbContextValue_BoolCopyWithImpl(this._self, this._then);

  final FrbContextValue_Bool _self;
  final $Res Function(FrbContextValue_Bool) _then;

/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FrbContextValue_Bool(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FrbContextValue_StringList extends FrbContextValue {
  const FrbContextValue_StringList(final  List<String> field0): _field0 = field0,super._();
  

 final  List<String> _field0;
 List<String> get field0 {
  if (_field0 is EqualUnmodifiableListView) return _field0;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_field0);
}


/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbContextValue_StringListCopyWith<FrbContextValue_StringList> get copyWith => _$FrbContextValue_StringListCopyWithImpl<FrbContextValue_StringList>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbContextValue_StringList&&const DeepCollectionEquality().equals(other._field0, _field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_field0));

@override
String toString() {
  return 'FrbContextValue.stringList(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FrbContextValue_StringListCopyWith<$Res> implements $FrbContextValueCopyWith<$Res> {
  factory $FrbContextValue_StringListCopyWith(FrbContextValue_StringList value, $Res Function(FrbContextValue_StringList) _then) = _$FrbContextValue_StringListCopyWithImpl;
@useResult
$Res call({
 List<String> field0
});




}
/// @nodoc
class _$FrbContextValue_StringListCopyWithImpl<$Res>
    implements $FrbContextValue_StringListCopyWith<$Res> {
  _$FrbContextValue_StringListCopyWithImpl(this._self, this._then);

  final FrbContextValue_StringList _self;
  final $Res Function(FrbContextValue_StringList) _then;

/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FrbContextValue_StringList(
null == field0 ? _self._field0 : field0 // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class FrbContextValue_NumberList extends FrbContextValue {
  const FrbContextValue_NumberList(this.field0): super._();
  

 final  Float64List field0;

/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbContextValue_NumberListCopyWith<FrbContextValue_NumberList> get copyWith => _$FrbContextValue_NumberListCopyWithImpl<FrbContextValue_NumberList>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbContextValue_NumberList&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'FrbContextValue.numberList(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FrbContextValue_NumberListCopyWith<$Res> implements $FrbContextValueCopyWith<$Res> {
  factory $FrbContextValue_NumberListCopyWith(FrbContextValue_NumberList value, $Res Function(FrbContextValue_NumberList) _then) = _$FrbContextValue_NumberListCopyWithImpl;
@useResult
$Res call({
 Float64List field0
});




}
/// @nodoc
class _$FrbContextValue_NumberListCopyWithImpl<$Res>
    implements $FrbContextValue_NumberListCopyWith<$Res> {
  _$FrbContextValue_NumberListCopyWithImpl(this._self, this._then);

  final FrbContextValue_NumberList _self;
  final $Res Function(FrbContextValue_NumberList) _then;

/// Create a copy of FrbContextValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FrbContextValue_NumberList(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as Float64List,
  ));
}


}

/// @nodoc


class FrbContextValue_Null extends FrbContextValue {
  const FrbContextValue_Null(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbContextValue_Null);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FrbContextValue.null_()';
}


}




/// @nodoc
mixin _$FrbFlagValue {

 Object get value;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbFlagValue&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(value));

@override
String toString() {
  return 'FrbFlagValue(value: $value)';
}


}

/// @nodoc
class $FrbFlagValueCopyWith<$Res>  {
$FrbFlagValueCopyWith(FrbFlagValue _, $Res Function(FrbFlagValue) __);
}


/// Adds pattern-matching-related methods to [FrbFlagValue].
extension FrbFlagValuePatterns on FrbFlagValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FrbFlagValue_Bool value)?  bool,TResult Function( FrbFlagValue_String value)?  string,TResult Function( FrbFlagValue_Int value)?  int,TResult Function( FrbFlagValue_Number value)?  number,TResult Function( FrbFlagValue_Json value)?  json,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FrbFlagValue_Bool() when bool != null:
return bool(_that);case FrbFlagValue_String() when string != null:
return string(_that);case FrbFlagValue_Int() when int != null:
return int(_that);case FrbFlagValue_Number() when number != null:
return number(_that);case FrbFlagValue_Json() when json != null:
return json(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FrbFlagValue_Bool value)  bool,required TResult Function( FrbFlagValue_String value)  string,required TResult Function( FrbFlagValue_Int value)  int,required TResult Function( FrbFlagValue_Number value)  number,required TResult Function( FrbFlagValue_Json value)  json,}){
final _that = this;
switch (_that) {
case FrbFlagValue_Bool():
return bool(_that);case FrbFlagValue_String():
return string(_that);case FrbFlagValue_Int():
return int(_that);case FrbFlagValue_Number():
return number(_that);case FrbFlagValue_Json():
return json(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FrbFlagValue_Bool value)?  bool,TResult? Function( FrbFlagValue_String value)?  string,TResult? Function( FrbFlagValue_Int value)?  int,TResult? Function( FrbFlagValue_Number value)?  number,TResult? Function( FrbFlagValue_Json value)?  json,}){
final _that = this;
switch (_that) {
case FrbFlagValue_Bool() when bool != null:
return bool(_that);case FrbFlagValue_String() when string != null:
return string(_that);case FrbFlagValue_Int() when int != null:
return int(_that);case FrbFlagValue_Number() when number != null:
return number(_that);case FrbFlagValue_Json() when json != null:
return json(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool value)?  bool,TResult Function( String value)?  string,TResult Function( PlatformInt64 value)?  int,TResult Function( double value)?  number,TResult Function( String value)?  json,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FrbFlagValue_Bool() when bool != null:
return bool(_that.value);case FrbFlagValue_String() when string != null:
return string(_that.value);case FrbFlagValue_Int() when int != null:
return int(_that.value);case FrbFlagValue_Number() when number != null:
return number(_that.value);case FrbFlagValue_Json() when json != null:
return json(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool value)  bool,required TResult Function( String value)  string,required TResult Function( PlatformInt64 value)  int,required TResult Function( double value)  number,required TResult Function( String value)  json,}) {final _that = this;
switch (_that) {
case FrbFlagValue_Bool():
return bool(_that.value);case FrbFlagValue_String():
return string(_that.value);case FrbFlagValue_Int():
return int(_that.value);case FrbFlagValue_Number():
return number(_that.value);case FrbFlagValue_Json():
return json(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool value)?  bool,TResult? Function( String value)?  string,TResult? Function( PlatformInt64 value)?  int,TResult? Function( double value)?  number,TResult? Function( String value)?  json,}) {final _that = this;
switch (_that) {
case FrbFlagValue_Bool() when bool != null:
return bool(_that.value);case FrbFlagValue_String() when string != null:
return string(_that.value);case FrbFlagValue_Int() when int != null:
return int(_that.value);case FrbFlagValue_Number() when number != null:
return number(_that.value);case FrbFlagValue_Json() when json != null:
return json(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class FrbFlagValue_Bool extends FrbFlagValue {
  const FrbFlagValue_Bool({required this.value}): super._();
  

@override final  bool value;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbFlagValue_BoolCopyWith<FrbFlagValue_Bool> get copyWith => _$FrbFlagValue_BoolCopyWithImpl<FrbFlagValue_Bool>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbFlagValue_Bool&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'FrbFlagValue.bool(value: $value)';
}


}

/// @nodoc
abstract mixin class $FrbFlagValue_BoolCopyWith<$Res> implements $FrbFlagValueCopyWith<$Res> {
  factory $FrbFlagValue_BoolCopyWith(FrbFlagValue_Bool value, $Res Function(FrbFlagValue_Bool) _then) = _$FrbFlagValue_BoolCopyWithImpl;
@useResult
$Res call({
 bool value
});




}
/// @nodoc
class _$FrbFlagValue_BoolCopyWithImpl<$Res>
    implements $FrbFlagValue_BoolCopyWith<$Res> {
  _$FrbFlagValue_BoolCopyWithImpl(this._self, this._then);

  final FrbFlagValue_Bool _self;
  final $Res Function(FrbFlagValue_Bool) _then;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(FrbFlagValue_Bool(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FrbFlagValue_String extends FrbFlagValue {
  const FrbFlagValue_String({required this.value}): super._();
  

@override final  String value;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbFlagValue_StringCopyWith<FrbFlagValue_String> get copyWith => _$FrbFlagValue_StringCopyWithImpl<FrbFlagValue_String>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbFlagValue_String&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'FrbFlagValue.string(value: $value)';
}


}

/// @nodoc
abstract mixin class $FrbFlagValue_StringCopyWith<$Res> implements $FrbFlagValueCopyWith<$Res> {
  factory $FrbFlagValue_StringCopyWith(FrbFlagValue_String value, $Res Function(FrbFlagValue_String) _then) = _$FrbFlagValue_StringCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$FrbFlagValue_StringCopyWithImpl<$Res>
    implements $FrbFlagValue_StringCopyWith<$Res> {
  _$FrbFlagValue_StringCopyWithImpl(this._self, this._then);

  final FrbFlagValue_String _self;
  final $Res Function(FrbFlagValue_String) _then;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(FrbFlagValue_String(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FrbFlagValue_Int extends FrbFlagValue {
  const FrbFlagValue_Int({required this.value}): super._();
  

@override final  PlatformInt64 value;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbFlagValue_IntCopyWith<FrbFlagValue_Int> get copyWith => _$FrbFlagValue_IntCopyWithImpl<FrbFlagValue_Int>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbFlagValue_Int&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'FrbFlagValue.int(value: $value)';
}


}

/// @nodoc
abstract mixin class $FrbFlagValue_IntCopyWith<$Res> implements $FrbFlagValueCopyWith<$Res> {
  factory $FrbFlagValue_IntCopyWith(FrbFlagValue_Int value, $Res Function(FrbFlagValue_Int) _then) = _$FrbFlagValue_IntCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 value
});




}
/// @nodoc
class _$FrbFlagValue_IntCopyWithImpl<$Res>
    implements $FrbFlagValue_IntCopyWith<$Res> {
  _$FrbFlagValue_IntCopyWithImpl(this._self, this._then);

  final FrbFlagValue_Int _self;
  final $Res Function(FrbFlagValue_Int) _then;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(FrbFlagValue_Int(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class FrbFlagValue_Number extends FrbFlagValue {
  const FrbFlagValue_Number({required this.value}): super._();
  

@override final  double value;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbFlagValue_NumberCopyWith<FrbFlagValue_Number> get copyWith => _$FrbFlagValue_NumberCopyWithImpl<FrbFlagValue_Number>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbFlagValue_Number&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'FrbFlagValue.number(value: $value)';
}


}

/// @nodoc
abstract mixin class $FrbFlagValue_NumberCopyWith<$Res> implements $FrbFlagValueCopyWith<$Res> {
  factory $FrbFlagValue_NumberCopyWith(FrbFlagValue_Number value, $Res Function(FrbFlagValue_Number) _then) = _$FrbFlagValue_NumberCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$FrbFlagValue_NumberCopyWithImpl<$Res>
    implements $FrbFlagValue_NumberCopyWith<$Res> {
  _$FrbFlagValue_NumberCopyWithImpl(this._self, this._then);

  final FrbFlagValue_Number _self;
  final $Res Function(FrbFlagValue_Number) _then;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(FrbFlagValue_Number(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class FrbFlagValue_Json extends FrbFlagValue {
  const FrbFlagValue_Json({required this.value}): super._();
  

@override final  String value;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbFlagValue_JsonCopyWith<FrbFlagValue_Json> get copyWith => _$FrbFlagValue_JsonCopyWithImpl<FrbFlagValue_Json>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbFlagValue_Json&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'FrbFlagValue.json(value: $value)';
}


}

/// @nodoc
abstract mixin class $FrbFlagValue_JsonCopyWith<$Res> implements $FrbFlagValueCopyWith<$Res> {
  factory $FrbFlagValue_JsonCopyWith(FrbFlagValue_Json value, $Res Function(FrbFlagValue_Json) _then) = _$FrbFlagValue_JsonCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$FrbFlagValue_JsonCopyWithImpl<$Res>
    implements $FrbFlagValue_JsonCopyWith<$Res> {
  _$FrbFlagValue_JsonCopyWithImpl(this._self, this._then);

  final FrbFlagValue_Json _self;
  final $Res Function(FrbFlagValue_Json) _then;

/// Create a copy of FrbFlagValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(FrbFlagValue_Json(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

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

/// @nodoc
mixin _$PollOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PollOutcome()';
}


}

/// @nodoc
class $PollOutcomeCopyWith<$Res>  {
$PollOutcomeCopyWith(PollOutcome _, $Res Function(PollOutcome) __);
}


/// Adds pattern-matching-related methods to [PollOutcome].
extension PollOutcomePatterns on PollOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PollOutcome_Updated value)?  updated,TResult Function( PollOutcome_NotModified value)?  notModified,TResult Function( PollOutcome_Fatal value)?  fatal,TResult Function( PollOutcome_Retrying value)?  retrying,TResult Function( PollOutcome_RateLimited value)?  rateLimited,TResult Function( PollOutcome_Stale value)?  stale,TResult Function( PollOutcome_DedupedSkipped value)?  dedupedSkipped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PollOutcome_Updated() when updated != null:
return updated(_that);case PollOutcome_NotModified() when notModified != null:
return notModified(_that);case PollOutcome_Fatal() when fatal != null:
return fatal(_that);case PollOutcome_Retrying() when retrying != null:
return retrying(_that);case PollOutcome_RateLimited() when rateLimited != null:
return rateLimited(_that);case PollOutcome_Stale() when stale != null:
return stale(_that);case PollOutcome_DedupedSkipped() when dedupedSkipped != null:
return dedupedSkipped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PollOutcome_Updated value)  updated,required TResult Function( PollOutcome_NotModified value)  notModified,required TResult Function( PollOutcome_Fatal value)  fatal,required TResult Function( PollOutcome_Retrying value)  retrying,required TResult Function( PollOutcome_RateLimited value)  rateLimited,required TResult Function( PollOutcome_Stale value)  stale,required TResult Function( PollOutcome_DedupedSkipped value)  dedupedSkipped,}){
final _that = this;
switch (_that) {
case PollOutcome_Updated():
return updated(_that);case PollOutcome_NotModified():
return notModified(_that);case PollOutcome_Fatal():
return fatal(_that);case PollOutcome_Retrying():
return retrying(_that);case PollOutcome_RateLimited():
return rateLimited(_that);case PollOutcome_Stale():
return stale(_that);case PollOutcome_DedupedSkipped():
return dedupedSkipped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PollOutcome_Updated value)?  updated,TResult? Function( PollOutcome_NotModified value)?  notModified,TResult? Function( PollOutcome_Fatal value)?  fatal,TResult? Function( PollOutcome_Retrying value)?  retrying,TResult? Function( PollOutcome_RateLimited value)?  rateLimited,TResult? Function( PollOutcome_Stale value)?  stale,TResult? Function( PollOutcome_DedupedSkipped value)?  dedupedSkipped,}){
final _that = this;
switch (_that) {
case PollOutcome_Updated() when updated != null:
return updated(_that);case PollOutcome_NotModified() when notModified != null:
return notModified(_that);case PollOutcome_Fatal() when fatal != null:
return fatal(_that);case PollOutcome_Retrying() when retrying != null:
return retrying(_that);case PollOutcome_RateLimited() when rateLimited != null:
return rateLimited(_that);case PollOutcome_Stale() when stale != null:
return stale(_that);case PollOutcome_DedupedSkipped() when dedupedSkipped != null:
return dedupedSkipped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  updated,TResult Function()?  notModified,TResult Function()?  fatal,TResult Function()?  retrying,TResult Function( PlatformInt64 retryAfterSecs)?  rateLimited,TResult Function()?  stale,TResult Function()?  dedupedSkipped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PollOutcome_Updated() when updated != null:
return updated();case PollOutcome_NotModified() when notModified != null:
return notModified();case PollOutcome_Fatal() when fatal != null:
return fatal();case PollOutcome_Retrying() when retrying != null:
return retrying();case PollOutcome_RateLimited() when rateLimited != null:
return rateLimited(_that.retryAfterSecs);case PollOutcome_Stale() when stale != null:
return stale();case PollOutcome_DedupedSkipped() when dedupedSkipped != null:
return dedupedSkipped();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  updated,required TResult Function()  notModified,required TResult Function()  fatal,required TResult Function()  retrying,required TResult Function( PlatformInt64 retryAfterSecs)  rateLimited,required TResult Function()  stale,required TResult Function()  dedupedSkipped,}) {final _that = this;
switch (_that) {
case PollOutcome_Updated():
return updated();case PollOutcome_NotModified():
return notModified();case PollOutcome_Fatal():
return fatal();case PollOutcome_Retrying():
return retrying();case PollOutcome_RateLimited():
return rateLimited(_that.retryAfterSecs);case PollOutcome_Stale():
return stale();case PollOutcome_DedupedSkipped():
return dedupedSkipped();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  updated,TResult? Function()?  notModified,TResult? Function()?  fatal,TResult? Function()?  retrying,TResult? Function( PlatformInt64 retryAfterSecs)?  rateLimited,TResult? Function()?  stale,TResult? Function()?  dedupedSkipped,}) {final _that = this;
switch (_that) {
case PollOutcome_Updated() when updated != null:
return updated();case PollOutcome_NotModified() when notModified != null:
return notModified();case PollOutcome_Fatal() when fatal != null:
return fatal();case PollOutcome_Retrying() when retrying != null:
return retrying();case PollOutcome_RateLimited() when rateLimited != null:
return rateLimited(_that.retryAfterSecs);case PollOutcome_Stale() when stale != null:
return stale();case PollOutcome_DedupedSkipped() when dedupedSkipped != null:
return dedupedSkipped();case _:
  return null;

}
}

}

/// @nodoc


class PollOutcome_Updated extends PollOutcome {
  const PollOutcome_Updated(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollOutcome_Updated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PollOutcome.updated()';
}


}




/// @nodoc


class PollOutcome_NotModified extends PollOutcome {
  const PollOutcome_NotModified(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollOutcome_NotModified);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PollOutcome.notModified()';
}


}




/// @nodoc


class PollOutcome_Fatal extends PollOutcome {
  const PollOutcome_Fatal(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollOutcome_Fatal);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PollOutcome.fatal()';
}


}




/// @nodoc


class PollOutcome_Retrying extends PollOutcome {
  const PollOutcome_Retrying(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollOutcome_Retrying);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PollOutcome.retrying()';
}


}




/// @nodoc


class PollOutcome_RateLimited extends PollOutcome {
  const PollOutcome_RateLimited({required this.retryAfterSecs}): super._();
  

 final  PlatformInt64 retryAfterSecs;

/// Create a copy of PollOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PollOutcome_RateLimitedCopyWith<PollOutcome_RateLimited> get copyWith => _$PollOutcome_RateLimitedCopyWithImpl<PollOutcome_RateLimited>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollOutcome_RateLimited&&(identical(other.retryAfterSecs, retryAfterSecs) || other.retryAfterSecs == retryAfterSecs));
}


@override
int get hashCode => Object.hash(runtimeType,retryAfterSecs);

@override
String toString() {
  return 'PollOutcome.rateLimited(retryAfterSecs: $retryAfterSecs)';
}


}

/// @nodoc
abstract mixin class $PollOutcome_RateLimitedCopyWith<$Res> implements $PollOutcomeCopyWith<$Res> {
  factory $PollOutcome_RateLimitedCopyWith(PollOutcome_RateLimited value, $Res Function(PollOutcome_RateLimited) _then) = _$PollOutcome_RateLimitedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 retryAfterSecs
});




}
/// @nodoc
class _$PollOutcome_RateLimitedCopyWithImpl<$Res>
    implements $PollOutcome_RateLimitedCopyWith<$Res> {
  _$PollOutcome_RateLimitedCopyWithImpl(this._self, this._then);

  final PollOutcome_RateLimited _self;
  final $Res Function(PollOutcome_RateLimited) _then;

/// Create a copy of PollOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? retryAfterSecs = null,}) {
  return _then(PollOutcome_RateLimited(
retryAfterSecs: null == retryAfterSecs ? _self.retryAfterSecs : retryAfterSecs // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class PollOutcome_Stale extends PollOutcome {
  const PollOutcome_Stale(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollOutcome_Stale);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PollOutcome.stale()';
}


}




/// @nodoc


class PollOutcome_DedupedSkipped extends PollOutcome {
  const PollOutcome_DedupedSkipped(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PollOutcome_DedupedSkipped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PollOutcome.dedupedSkipped()';
}


}




// dart format on
