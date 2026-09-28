class_name PackLights
extends RefCounted
## 桌寵的光源(發光效果,不做陰影):存在素材包 pack.json 的 "lights" 陣列,由精靈圖編輯器的「光源」區編輯(錨點可以在畫布上拖曳,也可以打數字)。
## 每一盞:{name, x, y, radius, energy, color, enabled, action}。座標和判定框同一套:縮放前的像素、原點是腳底線的中心點(x 向右、y 向下,頭頂是負的 y);
## radius = 光暈半徑(像素)、energy = 亮度(0.05~2.0)、color = "#rrggbb"、action = 只在這個動作播放時亮(空白 = 一直亮,例如 walk、sit、dance)。
## 光源全部是程式畫的柔和光暈(見 PetLights),沒有任何圖檔;全局設定可以整個關掉(和效能有關)。
## 動作專屬發光錨點:同一盞光的位置可以依動作、甚至依動畫的每一幀不同(例如舉起發光的手、眼睛在某幾幀發亮):
##   "anchors": {動作: [x, y]}、"frame_anchors": {動作: [[x, y], 第 0 幀, 第 1 幀…]};沒設的動作就用上面的 x / y。優先順序和配件錨點一樣:這一幀 > 這個動作 > 預設(見 AccessoryAnchors)。
## 2026-09-28:半徑/亮度/顏色/是否亮著(熄燈)四項也能逐幀單獨調整(見 ScopedProperty):"radius_by_frame"/
## "energy_by_frame"/"color_by_frame"/"enabled_by_frame"(Dictionary[動作, Array]),陣列裡 null = 這一幀沒有
## 單獨調整、跟著預設值走(包括預設值之後又被改動的情況),非 null = 這一幀自己的值。讀取見 radius_of()/
## energy_of()/color_of()/frame_enabled(),寫入見 set_radius()/set_energy()/set_color()/set_frame_enabled()。
## 位置(x/y)不套用這一套,仍然走 AccessoryAnchors(舊資料的欄位名稱 anchor/anchors/frame_anchors 不能換);
## 精靈圖編輯器的「單獨調整此幀」開關對五個屬性(位置+這四個)都生效,但位置沿用 AccessoryAnchors 既有的
## 「整個動作第一次設逐幀值時,其他幀先凍結成當時的值」規則(不是這裡的 null 動態跟隨),兩者行為有點不同,
## 是刻意的取捨:AccessoryAnchors 同時被配件系統(overlays.json)共用,不能改動它的資料語意。
## FurnitureLight 的分幀光源(道具/家具用)是同一套 ScopedProperty 機制的另一邊,見 FurnitureLight 檔頭。

const MAX_LIGHTS := 8
const MAX_COORD := 2048.0
const RADIUS_RANGE := Vector2(8.0, 600.0)
const ENERGY_RANGE := Vector2(0.05, 2.0)
const DEFAULT_COLOR := "#ffe9a8"


## 一盞預設的光(新增時用):頭部上方、暖白色、中等半徑。
static func new_light(index: int, at := Vector2(0.0, -60.0)) -> Dictionary:
	return {"name": "光源 %d" % (index + 1), "x": at.x, "y": at.y, "radius": 80.0, "energy": 0.8, "color": DEFAULT_COLOR, "enabled": true, "action": ""}   # no-tr:存進 pack.json 的資料,不隨語系變


## 把任意輸入(pack.json 讀來的)整理成合法的光源清單:壞的項目略過、數字夾在範圍內、最多 MAX_LIGHTS 盞。
static func clean(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array:
		return result
	for entry: Variant in raw:
		if result.size() >= MAX_LIGHTS or not entry is Dictionary:
			continue
		var x: Variant = entry.get("x", 0.0)
		var y: Variant = entry.get("y", 0.0)
		if not (x is float or x is int) or not (y is float or y is int):
			continue
		var radius: Variant = entry.get("radius", 80.0)
		var energy: Variant = entry.get("energy", 0.8)
		var color_text := str(entry.get("color", DEFAULT_COLOR))
		var name_text := str(entry.get("name", "")).strip_edges().left(24)
		var action := str(entry.get("action", "")).strip_edges().left(32)
		var cleaned := {
			"name": name_text if name_text != "" else "光源 %d" % (result.size() + 1),   # no-tr:存進 pack.json 的資料,不隨語系變
			"x": clampf(float(x), -MAX_COORD, MAX_COORD), "y": clampf(float(y), -MAX_COORD, MAX_COORD),
			"radius": clampf(float(radius), RADIUS_RANGE.x, RADIUS_RANGE.y) if (radius is float or radius is int) else 80.0,
			"energy": clampf(float(energy), ENERGY_RANGE.x, ENERGY_RANGE.y) if (energy is float or energy is int) else 0.8,
			"color": color_text if Color.html_is_valid(color_text) and color_text.begins_with("#") else DEFAULT_COLOR,
			"enabled": bool(entry.get("enabled", true)) if entry.get("enabled", true) is bool else true,
			"action": action,
			"layer": "back" if str(entry.get("layer", "front")) == "back" else "front",
		}
		var by_action := _clean_anchors(entry.get("anchors"))
		if not by_action.is_empty():
			cleaned["anchors"] = by_action
		var by_frame := _clean_frame_anchors(entry.get("frame_anchors"))
		if not by_frame.is_empty():
			cleaned["frame_anchors"] = by_frame
		ScopedProperty.write_cleaned(cleaned, "radius", ScopedProperty.clean_float_by_frame(entry.get("radius_by_frame"), RADIUS_RANGE))
		ScopedProperty.write_cleaned(cleaned, "energy", ScopedProperty.clean_float_by_frame(entry.get("energy_by_frame"), ENERGY_RANGE))
		ScopedProperty.write_cleaned(cleaned, "color", ScopedProperty.clean_color_by_frame(entry.get("color_by_frame")))
		ScopedProperty.write_cleaned(cleaned, "enabled", ScopedProperty.clean_bool_by_frame(entry.get("enabled_by_frame")))
		result.append(cleaned)
	return result


static func _point(value: Variant) -> Variant:
	if value is Array and (value as Array).size() >= 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return [clampf(float(value[0]), -MAX_COORD, MAX_COORD), clampf(float(value[1]), -MAX_COORD, MAX_COORD)]
	return null


static func _clean_anchors(raw: Variant) -> Dictionary:
	var result := {}
	if raw is Dictionary:
		for action: Variant in (raw as Dictionary).keys().slice(0, 64):
			var point: Variant = _point(raw[action])
			if point != null and str(action) != "":
				result[str(action).left(32)] = point
	return result


static func _clean_frame_anchors(raw: Variant) -> Dictionary:
	var result := {}
	if raw is Dictionary:
		for action: Variant in (raw as Dictionary).keys().slice(0, 64):
			if not raw[action] is Array or str(action) == "":
				continue
			var points: Array = []
			for entry: Variant in (raw[action] as Array).slice(0, 256):
				var point: Variant = _point(entry)
				points.append(point if point != null else [0.0, 0.0])
			if not points.is_empty():
				result[str(action).left(32)] = points
	return result


## 這盞光在指定動作與幀的位置(幀 > 動作 > 預設 x/y)。
static func position_of(light: Dictionary, action: String, frame: int) -> Vector2:
	return AccessoryAnchors.effective(_as_anchor_part(light), action, frame)


## 這盞光在指定動作與幀的半徑/亮度/顏色/是否亮著(這一幀單獨調整過就用那個值,否則用預設值)。
## 「是否亮著」的總開關(enabled)先決定這盞光整體有沒有可能亮,逐幀覆蓋只能在已經亮著的範圍內額外
## 「熄燈」指定幀,不能讓總開關關掉的燈因為某個逐幀覆蓋又亮起來(見 active() 的呼叫順序)。
static func radius_of(light: Dictionary, action: String, frame: int) -> float:
	return float(ScopedProperty.effective(light, "radius", light["radius"], action, frame))


static func energy_of(light: Dictionary, action: String, frame: int) -> float:
	return float(ScopedProperty.effective(light, "energy", light["energy"], action, frame))


static func color_of(light: Dictionary, action: String, frame: int) -> String:
	return str(ScopedProperty.effective(light, "color", light["color"], action, frame))


static func frame_enabled(light: Dictionary, action: String, frame: int) -> bool:
	return bool(ScopedProperty.effective(light, "enabled", light["enabled"], action, frame))


## 把半徑/亮度/顏色/熄燈寫進指定的那一層(scope 見 ScopedProperty.SCOPE_*,只有 DEFAULT/FRAME 兩層)。
static func set_radius(light: Dictionary, scope: int, action: String, frame: int, frame_count: int, value: float) -> void:
	ScopedProperty.set_value(light, "radius", "radius", scope, action, frame, frame_count, clampf(value, RADIUS_RANGE.x, RADIUS_RANGE.y))


static func set_energy(light: Dictionary, scope: int, action: String, frame: int, frame_count: int, value: float) -> void:
	ScopedProperty.set_value(light, "energy", "energy", scope, action, frame, frame_count, clampf(value, ENERGY_RANGE.x, ENERGY_RANGE.y))


static func set_color(light: Dictionary, scope: int, action: String, frame: int, frame_count: int, value: String) -> void:
	ScopedProperty.set_value(light, "color", "color", scope, action, frame, frame_count, value if Color.html_is_valid(value) and value.begins_with("#") else DEFAULT_COLOR)


static func set_frame_enabled(light: Dictionary, scope: int, action: String, frame: int, frame_count: int, value: bool) -> void:
	ScopedProperty.set_value(light, "enabled", "enabled", scope, action, frame, frame_count, value)


## 這一幀是不是有單獨調整(ScopedProperty.SCOPE_FRAME),還是跟著預設值走(SCOPE_DEFAULT)。四個屬性各自獨立。
static func radius_source_of(light: Dictionary, action: String, frame: int) -> int:
	return ScopedProperty.source_of(light, "radius", action, frame)


static func energy_source_of(light: Dictionary, action: String, frame: int) -> int:
	return ScopedProperty.source_of(light, "energy", action, frame)


static func color_source_of(light: Dictionary, action: String, frame: int) -> int:
	return ScopedProperty.source_of(light, "color", action, frame)


static func enabled_source_of(light: Dictionary, action: String, frame: int) -> int:
	return ScopedProperty.source_of(light, "enabled", action, frame)


## 這個動作裡,位置/半徑/亮度/顏色/是否亮著,有沒有任何一項在任何一幀被單獨調整過(給「這盞光在這個動作有
## 分幀設定」這類提示用;位置的判定用 AccessoryAnchors.source_of() 的既有語意,跟另外四項的 any_frame_overridden 不完全對等,見檔頭說明)。
static func has_any_frame_override(light: Dictionary, action: String) -> bool:
	return AccessoryAnchors.source_of(_as_anchor_part(light), action) == AccessoryAnchors.SCOPE_FRAME \
			or ScopedProperty.any_frame_overridden(light, "radius", action) \
			or ScopedProperty.any_frame_overridden(light, "energy", action) \
			or ScopedProperty.any_frame_overridden(light, "color", action) \
			or ScopedProperty.any_frame_overridden(light, "enabled", action)


## 清掉指定那一層的覆蓋(回到跟著預設值走)。
static func clear_radius_scope(light: Dictionary, scope: int, action: String, frame: int) -> void:
	ScopedProperty.clear_scope(light, "radius", "radius", scope, action, frame)


static func clear_energy_scope(light: Dictionary, scope: int, action: String, frame: int) -> void:
	ScopedProperty.clear_scope(light, "energy", "energy", scope, action, frame)


static func clear_color_scope(light: Dictionary, scope: int, action: String, frame: int) -> void:
	ScopedProperty.clear_scope(light, "color", "color", scope, action, frame)


static func clear_enabled_scope(light: Dictionary, scope: int, action: String, frame: int) -> void:
	ScopedProperty.clear_scope(light, "enabled", "enabled", scope, action, frame)


## 現在生效的是哪一層(AccessoryAnchors.SCOPE_*),位置專用。
static func source_of(light: Dictionary, action: String) -> int:
	return AccessoryAnchors.source_of(_as_anchor_part(light), action)


## 把位置寫進指定的那一層(預設 = x / y;逐幀,見 AccessoryAnchors.set_anchor)。
static func set_position(light: Dictionary, scope: int, action: String, frame: int, frame_count: int, at: Vector2) -> void:
	if action == "" or scope == AccessoryAnchors.SCOPE_DEFAULT:
		light["x"] = at.x
		light["y"] = at.y
		return
	var part := _as_anchor_part(light)
	AccessoryAnchors.set_anchor(part, scope, action, frame, frame_count, at)
	_copy_back(light, part)


static func clear_scope(light: Dictionary, scope: int, action: String, frame: int) -> void:
	var part := _as_anchor_part(light)
	AccessoryAnchors.clear_scope(part, scope, action, frame)
	_copy_back(light, part)


static func _as_anchor_part(light: Dictionary) -> Dictionary:
	var part := {"anchor": [float(light.get("x", 0.0)), float(light.get("y", 0.0))]}
	if light.get("anchors") is Dictionary:
		part["anchors"] = (light["anchors"] as Dictionary).duplicate(true)
	if light.get("frame_anchors") is Dictionary:
		part["frame_anchors"] = (light["frame_anchors"] as Dictionary).duplicate(true)
	return part


static func _copy_back(light: Dictionary, part: Dictionary) -> void:
	for key: String in ["anchors", "frame_anchors"]:
		if part.has(key) and not (part[key] as Dictionary).is_empty():
			light[key] = part[key]
		else:
			light.erase(key)


## 這一刻(動作 action、幀 frame)有哪幾盞是亮的:總開關啟用、沒有指定動作或指定的動作剛好是現在的、
## 而且這一幀沒有被逐幀覆蓋熄燈。
static func active(lights: Array[Dictionary], action: String, frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for light in lights:
		if not bool(light["enabled"]):
			continue
		var wanted := str(light["action"])
		if wanted != "" and wanted != action:
			continue
		if not frame_enabled(light, action, frame):
			continue
		result.append(light)
	return result

## 持有錨點(pack.json 的 "hold_anchor": [x, y],桌寵手拿道具的位置):格式對就回 Vector2(夾在合法範圍),沒設或壞掉回 null。放在這裡是因為標定方式和光源錨點一樣。
static func anchor_of(raw: Variant) -> Variant:
	if raw is Array and (raw as Array).size() >= 2 and (raw[0] is float or raw[0] is int) and (raw[1] is float or raw[1] is int):
		return Vector2(clampf(float(raw[0]), -MAX_COORD, MAX_COORD), clampf(float(raw[1]), -MAX_COORD, MAX_COORD))
	return null
