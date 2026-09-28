class_name ValueGateway
extends RefCounted
## 數值存取閘道器(企劃書「Unified Value Gateway」):讀寫局部/全域數值的唯一入口,
## 依宣告(PetValueDef)自動判斷 key 屬於哪個作用域,套用預設值與上下限夾限,並發出 value_updated。
## 沒有宣告的 key:用呼叫端給的作用域提示(SCOPE 欄位),沒有提示就看哪邊已經有這個 key,再不然視為局部。
## 呼叫端(直譯器、對話選項、對話文字插值、Status 面板)都不需要自己判斷作用域。


static func _state() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("/root/DesktopShellState")


## 這個 key 的定義(局部優先於全域);沒宣告回傳 null。
static func find_def(pet: Node, key: String) -> PetValueDef:
	for def: PetValueDef in pet.value_defs:
		if def.key == key:
			return def
	for def: PetValueDef in _state().global_value_defs:
		if def.key == key:
			return def
	return null


static func is_global(pet: Node, key: String, scope_hint := "") -> bool:
	var def := find_def(pet, key)
	if def != null:
		return def.is_global
	var hint := scope_hint.to_lower()
	if hint.contains("global") or scope_hint.contains("全域"):
		return true
	if hint.contains("local") or scope_hint.contains("局部"):
		return false
	return not pet.local_values.has(key) and _state().global_values.has(key)


static func get_value(pet: Node, key: String, scope_hint := "") -> float:
	var store: Dictionary = _state().global_values if is_global(pet, key, scope_hint) else pet.local_values
	if store.has(key):
		return float(store[key])
	var def := find_def(pet, key)
	return def.default_value if def != null else 0.0


static func set_value(pet: Node, key: String, value: float, scope_hint := "") -> void:
	var global := is_global(pet, key, scope_hint)
	var store: Dictionary = _state().global_values if global else pet.local_values
	var def := find_def(pet, key)
	if def != null:
		value = def.clamp_value(value)
	var old := get_value(pet, key, scope_hint)
	store[key] = value
	if not is_equal_approx(old, value):
		_state().value_updated.emit(pet, "global" if global else "local", key, value, old)


static func modify_value(pet: Node, key: String, delta: float, scope_hint := "") -> void:
	set_value(pet, key, get_value(pet, key, scope_hint) + delta, scope_hint)


## 桌寵加入時呼叫:把還沒有值的局部/全域宣告寫入預設值。
static func init_defaults(pet: Node) -> void:
	for def: PetValueDef in pet.value_defs:
		if not pet.local_values.has(def.key):
			pet.local_values[def.key] = def.clamp_value(def.default_value)
	var globals: Dictionary = _state().global_values
	for def: PetValueDef in _state().global_value_defs:
		if not globals.has(def.key):
			globals[def.key] = def.clamp_value(def.default_value)


## Status 面板要顯示的數值定義:只含創作者勾選 show_in_status 的,依排序權重(相同就依宣告順序)排序。
static func status_defs(pet: Node) -> Array[PetValueDef]:
	var result: Array[PetValueDef] = []
	for def: PetValueDef in pet.value_defs:
		if def.show_in_status:
			result.append(def)
	for def: PetValueDef in _state().global_value_defs:
		if def.show_in_status:
			result.append(def)
	# sort_custom 不保證穩定,權重相同時用宣告順序當次要條件。
	var order := {}
	for i in result.size():
		order[result[i]] = i
	result.sort_custom(func(a: PetValueDef, b: PetValueDef) -> bool:
		return a.sort_weight < b.sort_weight or (a.sort_weight == b.sort_weight and order[a] < order[b]))
	return result
