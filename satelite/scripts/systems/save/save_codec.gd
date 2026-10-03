class_name SaveCodec
extends RefCounted
## Lossless [Variant] to JSON codec.
##
## Godot's [JSON] class only carries nil, bool, int, float, String, Array and
## Dictionary. Every other type - [Vector2], [Color], [StringName], [NodePath],
## [Transform3D] - is written as a plain string by [method JSON.stringify] and
## comes back as a String, so a save written that way cannot be trusted to round
## trip. This project uses [StringName] keys and [Color] tints everywhere, which
## makes that loss the difference between a working save and a broken one.
##
## So anything JSON cannot carry is wrapped in a tagged object instead, and
## everything JSON does understand is left alone. A save file therefore stays
## plain JSON and stays readable - a [Dictionary] stays a JSON object, so stat
## ids and upgrade ids are ordinary keys:
##
## [codeblock]
## {"speed": 12.5, "tint": {"$type": "Color", "r": 1.0, "g": 0.0, "b": 0.0, "a": 1.0}}
## [/codeblock]
##
## [method encode] is the only place that knows about types, so nothing else in
## the save system has to:
##
## [codeblock]
## var text: String = SaveCodec.stringify({"tint": Color.RED, "id": &"engine"})
## var value: Variant = SaveCodec.parse(text)  # a Color and a StringName again
## [/codeblock]
##
## [method parse] returns null both for a document that is literally null and for
## one it could not read, so callers that care should check
## [method JSON.parse] themselves.

## Key that marks a wrapped value. Prefixed with a dollar sign to stay out of the
## way of the plain ids game code uses as dictionary keys.
const TYPE_KEY := "$type"

## Types this codec round trips. Everything here is either understood by JSON
## outright or wrapped by [method encode]. [constant TYPE_INT] is in the list but
## is wrapped rather than passed through, because JSON reads every number back as
## a float.
const SUPPORTED_TYPES: Array[int] = [
	TYPE_NIL,
	TYPE_BOOL,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_STRING,
	TYPE_STRING_NAME,
	TYPE_NODE_PATH,
	TYPE_ARRAY,
	TYPE_DICTIONARY,
	TYPE_COLOR,
	TYPE_VECTOR2,
	TYPE_VECTOR2I,
	TYPE_VECTOR3,
	TYPE_VECTOR3I,
	TYPE_VECTOR4,
	TYPE_VECTOR4I,
	TYPE_RECT2,
	TYPE_RECT2I,
	TYPE_PLANE,
	TYPE_QUATERNION,
	TYPE_AABB,
	TYPE_BASIS,
	TYPE_TRANSFORM2D,
	TYPE_TRANSFORM3D,
	TYPE_PROJECTION,
	TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_INT32_ARRAY,
	TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY,
	TYPE_PACKED_STRING_ARRAY,
	TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY,
	TYPE_PACKED_COLOR_ARRAY,
]


## True when [method encode] can represent [param value] without losing it. Used
## to skip state that is not worth saving, such as a reference to another node.
static func is_supported(value: Variant) -> bool:
	return SUPPORTED_TYPES.has(typeof(value))


## JSON text for [param value], with every type it needs wrapped.
static func stringify(value: Variant, indent: String = "\t") -> String:
	return JSON.stringify(encode(value), indent, false, true)


## [param value] rebuilt from [method stringify] output, or null when the text is
## not readable JSON. Nested tagged objects are unwrapped all the way down.
static func parse(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("SaveCodec: %s (line %d)." % [json.get_error_message(), json.get_error_line()])
		return null
	return decode(json.data)


## [param value] in a form [method JSON.stringify] accepts.
static func encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_INT:
			# JSON has one number type and [method JSON.parse] hands back floats for
			# everything it reads, so an int that stays plain would come back as
			# 2.0. Tagging it is what keeps levels, counts and array elements ints.
			return _tagged(&"Int", {&"value": value})
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in (value as Array):
				items.append(encode(item))
			return items
		TYPE_DICTIONARY:
			return _encode_dictionary(value as Dictionary)
		TYPE_STRING_NAME:
			return _tagged(&"StringName", {&"value": str(value)})
		TYPE_NODE_PATH:
			return _tagged(&"NodePath", {&"value": str(value)})
		TYPE_COLOR:
			var color: Color = value
			return _tagged(&"Color", {&"r": color.r, &"g": color.g, &"b": color.b, &"a": color.a})
		TYPE_VECTOR2:
			var vector2: Vector2 = value
			return _tagged(&"Vector2", {&"x": vector2.x, &"y": vector2.y})
		TYPE_VECTOR2I:
			var vector2i: Vector2i = value
			return _tagged(&"Vector2i", {&"x": vector2i.x, &"y": vector2i.y})
		TYPE_VECTOR3:
			var vector3: Vector3 = value
			return _tagged(&"Vector3", {&"x": vector3.x, &"y": vector3.y, &"z": vector3.z})
		TYPE_VECTOR3I:
			var vector3i: Vector3i = value
			return _tagged(&"Vector3i", {&"x": vector3i.x, &"y": vector3i.y, &"z": vector3i.z})
		TYPE_VECTOR4:
			var vector4: Vector4 = value
			return _tagged(&"Vector4", {&"x": vector4.x, &"y": vector4.y, &"z": vector4.z, &"w": vector4.w})
		TYPE_VECTOR4I:
			var vector4i: Vector4i = value
			return _tagged(&"Vector4i", {&"x": vector4i.x, &"y": vector4i.y, &"z": vector4i.z, &"w": vector4i.w})
		TYPE_RECT2:
			var rect: Rect2 = value
			return _tagged(&"Rect2", {
				&"position": [rect.position.x, rect.position.y],
				&"size": [rect.size.x, rect.size.y],
			})
		TYPE_RECT2I:
			var recti: Rect2i = value
			return _tagged(&"Rect2i", {
				&"position": [recti.position.x, recti.position.y],
				&"size": [recti.size.x, recti.size.y],
			})
		TYPE_PLANE:
			var plane: Plane = value
			return _tagged(&"Plane", {&"normal": [plane.normal.x, plane.normal.y, plane.normal.z], &"d": plane.d})
		TYPE_QUATERNION:
			var quaternion: Quaternion = value
			return _tagged(&"Quaternion", {
				&"x": quaternion.x, &"y": quaternion.y, &"z": quaternion.z, &"w": quaternion.w,
			})
		TYPE_AABB:
			var aabb: AABB = value
			return _tagged(&"AABB", {
				&"position": [aabb.position.x, aabb.position.y, aabb.position.z],
				&"size": [aabb.size.x, aabb.size.y, aabb.size.z],
			})
		TYPE_BASIS:
			return _encode_basis(value)
		TYPE_TRANSFORM2D:
			var transform2d: Transform2D = value
			return _tagged(&"Transform2D", {
				&"x": [transform2d.x.x, transform2d.x.y],
				&"y": [transform2d.y.x, transform2d.y.y],
				&"origin": [transform2d.origin.x, transform2d.origin.y],
			})
		TYPE_TRANSFORM3D:
			var transform3d: Transform3D = value
			var body := _basis_body(transform3d.basis)
			body[&"origin"] = [transform3d.origin.x, transform3d.origin.y, transform3d.origin.z]
			return _tagged(&"Transform3D", body)
		TYPE_PROJECTION:
			var projection: Projection = value
			return _tagged(&"Projection", {
				&"x": _vec4_list(projection.x),
				&"y": _vec4_list(projection.y),
				&"z": _vec4_list(projection.z),
				&"w": _vec4_list(projection.w),
			})
		TYPE_PACKED_BYTE_ARRAY:
			# Base64 because this one really is binary, and a list of 0..255
			# integers would triple the size of every texture blob.
			return _tagged(&"PackedByteArray", {&"value": Marshalls.raw_to_base64(value)})
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			# One of these is a typed list of the type above it, which as a plain
			# Array loses its type. The constructor form keeps it in one readable
			# line and is exactly what [method str_to_var] reads back.
			return _tagged(StringName(type_string(typeof(value))), {&"value": var_to_str(value)})
		TYPE_OBJECT:
			return _encode_object(value as Object)
	push_warning("SaveCodec: a %s cannot be stored, saving null instead." % type_string(typeof(value)))
	return null


## The counterpart of [method encode]. Returns [param value] untouched when it is
## not a tagged object, which is what makes untagged JSON pass straight through.
static func decode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source := value as Dictionary
			if source.has(TYPE_KEY):
				return _decode_tagged(source)
			return _decode_dictionary(source)
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in (value as Array):
				items.append(decode(item))
			return items
	return value


static func _tagged(type: StringName, body: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {TYPE_KEY: str(type)}
	for key: Variant in body:
		result[key] = body[key]
	return result


## JSON object keys are always strings. That covers String and [StringName]
## alike, which Godot also treats as the same key, so an ordinary dictionary
## becomes an ordinary JSON object. A dictionary keyed by anything else has to be
## carried as a list of pairs instead.
static func _encode_dictionary(source: Dictionary) -> Variant:
	var exotic := false
	for key: Variant in source:
		if not (key is String or key is StringName):
			exotic = true
			break

	if exotic:
		var pairs: Array = []
		for key: Variant in source:
			pairs.append([encode(key), encode(source[key])])
		return _tagged(&"Dictionary", {&"value": pairs})

	var body: Dictionary = {}
	for key: Variant in source:
		body[str(key)] = encode(source[key])
	return body


static func _decode_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		result[key] = decode(source[key])
	return result


static func _decode_tagged(source: Dictionary) -> Variant:
	var type := StringName(str(source.get(TYPE_KEY, "")))
	var payload: Dictionary = {}
	for key: Variant in source:
		if key == TYPE_KEY:
			continue
		payload[StringName(key)] = decode(source[key])

	match type:
		&"Int":
			return int(payload[&"value"])
		&"StringName":
			return StringName(payload.get(&"value", ""))
		&"NodePath":
			return NodePath(payload.get(&"value", ""))
		&"Color":
			return Color(payload[&"r"], payload[&"g"], payload[&"b"], payload[&"a"])
		&"Vector2":
			return Vector2(payload[&"x"], payload[&"y"])
		&"Vector2i":
			return Vector2i(payload[&"x"], payload[&"y"])
		&"Vector3":
			return Vector3(payload[&"x"], payload[&"y"], payload[&"z"])
		&"Vector3i":
			return Vector3i(payload[&"x"], payload[&"y"], payload[&"z"])
		&"Vector4":
			return Vector4(payload[&"x"], payload[&"y"], payload[&"z"], payload[&"w"])
		&"Vector4i":
			return Vector4i(payload[&"x"], payload[&"y"], payload[&"z"], payload[&"w"])
		&"Rect2":
			return Rect2(_vector2(payload[&"position"]), _vector2(payload[&"size"]))
		&"Rect2i":
			return Rect2i(_vector2i(payload[&"position"]), _vector2i(payload[&"size"]))
		&"Plane":
			return Plane(_vector3(payload[&"normal"]), payload[&"d"])
		&"Quaternion":
			return Quaternion(payload[&"x"], payload[&"y"], payload[&"z"], payload[&"w"])
		&"AABB":
			return AABB(_vector3(payload[&"position"]), _vector3(payload[&"size"]))
		&"Basis":
			return _decode_basis(payload)
		&"Transform2D":
			return Transform2D(_vector2(payload[&"x"]), _vector2(payload[&"y"]), _vector2(payload[&"origin"]))
		&"Transform3D":
			return Transform3D(_decode_basis(payload), _vector3(payload[&"origin"]))
		&"Projection":
			return Projection(
				_vector4(payload[&"x"]), _vector4(payload[&"y"]), _vector4(payload[&"z"]), _vector4(payload[&"w"])
			)
		&"PackedByteArray":
			return Marshalls.base64_to_raw(str(payload.get(&"value", "")))
		&"Dictionary":
			return _decode_tagged_dictionary(payload)
		&"Resource":
			return _decode_resource(str(payload.get(&"value", "")))

	# Packed arrays, and anything a future save file brings along.
	var restored: Variant = str_to_var(str(payload.get(&"value", "")))
	if restored == null:
		push_warning("SaveCodec: could not read back a '%s'." % type)
	return restored


static func _encode_basis(value: Variant) -> Dictionary:
	var basis: Basis = value
	return _tagged(&"Basis", _basis_body(basis))


static func _basis_body(basis: Basis) -> Dictionary:
	return {
		&"x": [basis.x.x, basis.x.y, basis.x.z],
		&"y": [basis.y.x, basis.y.y, basis.y.z],
		&"z": [basis.z.x, basis.z.y, basis.z.z],
	}


static func _decode_basis(payload: Dictionary) -> Basis:
	return Basis(_vector3(payload[&"x"]), _vector3(payload[&"y"]), _vector3(payload[&"z"]))


static func _decode_tagged_dictionary(payload: Dictionary) -> Variant:
	var body: Variant = payload.get(&"value")
	if not (body is Array):
		return body
	# Pair list: the only form that survives keys JSON cannot express. The payload
	# was already decoded on the way in, so the keys are back to being keys.
	var pairs: Dictionary = {}
	for pair: Variant in (body as Array):
		if pair is Array and (pair as Array).size() == 2:
			pairs[decode((pair as Array)[0])] = decode((pair as Array)[1])
	return pairs


## Only a [Resource] is worth persisting, and only by path: a node, a plain object
## or a resource built at runtime has nothing a save file could point at.
static func _encode_object(value: Object) -> Variant:
	if value == null:
		return null
	var path := ""
	if value is Resource:
		path = (value as Resource).resource_path
	if path.is_empty():
		return null
	return _tagged(&"Resource", {&"value": path})


static func _decode_resource(path: String) -> Variant:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path)


static func _vec4_list(value: Vector4) -> Array:
	return [value.x, value.y, value.z, value.w]


static func _vector2(value: Variant) -> Vector2:
	var list := value as Array
	return Vector2(float(list[0]), float(list[1])) if list.size() == 2 else Vector2.ZERO


static func _vector2i(value: Variant) -> Vector2i:
	var list := value as Array
	return Vector2i(int(list[0]), int(list[1])) if list.size() == 2 else Vector2i.ZERO


static func _vector3(value: Variant) -> Vector3:
	var list := value as Array
	return Vector3(float(list[0]), float(list[1]), float(list[2])) if list.size() == 3 else Vector3.ZERO


static func _vector4(value: Variant) -> Vector4:
	var list := value as Array
	if list.size() != 4:
		return Vector4.ZERO
	return Vector4(float(list[0]), float(list[1]), float(list[2]), float(list[3]))