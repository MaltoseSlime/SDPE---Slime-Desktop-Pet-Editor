class_name ScopedProperty
extends RefCounted
## 泛用的「預設 / 這一幀」數值覆蓋:任何可以存進 JSON 的值(float、String、bool…)都可以逐幀單獨調整,
## 沒被單獨調整的幀永遠跟著預設值走(包括預設值之後又被改動的情況)。光源的半徑/亮度/顏色/開關
## (PackLights、FurnitureLight)用這個;位置仍然走 AccessoryAnchors(舊資料的欄位名稱是
## anchor/anchors/frame_anchors,不能換,所以位置維持獨立一套,不合併進來)。
##
## 用法:呼叫端的容器字典(例如一盞燈的 Dictionary)自己保留預設值欄位(例如 "radius"),這裡另外用
## "<prefix>_by_frame"(Dictionary[動作, Array]))存逐幀覆蓋,陣列裡 null = 這一幀沒有單獨調整、跟著預設值,
## 非 null = 這一幀自己的值。沒有任何幀被單獨調整時這個鍵不存在。
##
## 每一幀獨立:單獨調整某一幀,不會連帶把同一個動作裡其他還沒調整過的幀也「凍結」成當下的預設值——
## 那些幀繼續動態跟著預設值,之後預設值再被改,它們也會跟著變。

const SCOPE_DEFAULT := 0
const SCOPE_FRAME := 2


## 這個屬性在指定動作與幀的實際值(這一幀自己調整過就用那個值,否則用預設值)。
## default_value = container[default_key] 目前的值。
static func effective(container: Dictionary, prefix: String, default_value: Variant, action: String, frame: int) -> Variant:
	var by_frame: Variant = container.get(prefix + "_by_frame")
	if by_frame is Dictionary and (by_frame as Dictionary).get(action) is Array:
		var list: Array = (by_frame as Dictionary)[action]
		if not list.is_empty():
			var value: Variant = list[frame % list.size()]
			if value != null:
				return value
	return default_value


## 這一幀是不是有單獨調整(SCOPE_FRAME),還是跟著預設值(SCOPE_DEFAULT)。
static func source_of(container: Dictionary, prefix: String, action: String, frame: int) -> int:
	var by_frame: Variant = container.get(prefix + "_by_frame")
	if by_frame is Dictionary and (by_frame as Dictionary).get(action) is Array:
		var list: Array = (by_frame as Dictionary)[action]
		if not list.is_empty() and list[frame % list.size()] != null:
			return SCOPE_FRAME
	return SCOPE_DEFAULT


## 這個動作裡有沒有任何一幀被單獨調整過(給「這個動作有分幀設定」這類提示用)。
static func any_frame_overridden(container: Dictionary, prefix: String, action: String) -> bool:
	var by_frame: Variant = container.get(prefix + "_by_frame")
	if not (by_frame is Dictionary and (by_frame as Dictionary).get(action) is Array):
		return false
	return ((by_frame as Dictionary)[action] as Array).any(func(entry: Variant) -> bool: return entry != null)


## 把值寫進指定的那一層。scope = SCOPE_DEFAULT 寫預設值(container[default_key]);SCOPE_FRAME 寫這一幀的
## 單獨覆蓋(該動作陣列不存在就先建立、長度不夠就用 null 補到 frame_count,其餘幀維持 null = 繼續跟著預設值)。
## 動作是空字串時只能寫預設層。default_key = 預設值在 container 裡的欄位名稱(例如 "radius")。
static func set_value(container: Dictionary, prefix: String, default_key: String, scope: int, action: String, frame: int, frame_count: int, value: Variant) -> void:
	if action == "" or scope == SCOPE_DEFAULT:
		container[default_key] = value
		return
	var by_frame: Dictionary = (container.get(prefix + "_by_frame") as Dictionary) if container.get(prefix + "_by_frame") is Dictionary else {}
	var list: Array = (by_frame.get(action) as Array).duplicate() if by_frame.get(action) is Array else []
	var count := maxi(frame_count, frame + 1)
	while list.size() < count:
		list.append(null)
	list[frame] = value
	by_frame[action] = list
	container[prefix + "_by_frame"] = by_frame


## 清掉這一幀的單獨覆蓋(退回跟著預設值走);整個動作都沒有任何一幀被覆蓋時,把陣列整個刪掉。
static func clear_scope(container: Dictionary, prefix: String, _default_key: String, scope: int, action: String, frame: int) -> void:
	if action == "" or scope == SCOPE_DEFAULT:
		return
	if not (container.get(prefix + "_by_frame") is Dictionary and (container[prefix + "_by_frame"] as Dictionary).get(action) is Array):
		return
	var list: Array = (container[prefix + "_by_frame"] as Dictionary)[action]
	if frame >= 0 and frame < list.size():
		list[frame] = null
	if list.all(func(entry: Variant) -> bool: return entry == null):
		(container[prefix + "_by_frame"] as Dictionary).erase(action)
		if (container[prefix + "_by_frame"] as Dictionary).is_empty():
			container.erase(prefix + "_by_frame")


# --- 存讀淨化(給 pack.json/furniture.json 讀回時用,PackLights 與 FurnitureDef 共用) ---

## 逐幀覆蓋(Dictionary[動作, Array]):null = 沒單獨調整,保留 null;數字型別對且在範圍內就夾住,
## 型別不對的壞值退回 null(不是退回某個固定值——寧可讓那一幀繼續跟著預設值,也不要塞一個猜測值)。
static func clean_float_by_frame(raw: Variant, range: Vector2) -> Dictionary:
	var result := {}
	if raw is Dictionary:
		for action: Variant in (raw as Dictionary).keys().slice(0, 64):
			if not raw[action] is Array or str(action) == "":
				continue
			var values: Array = []
			for entry: Variant in (raw[action] as Array).slice(0, 256):
				values.append(clampf(float(entry), range.x, range.y) if (entry is float or entry is int) else null)
			if values.any(func(v: Variant) -> bool: return v != null):
				result[str(action).left(32)] = values
	return result


static func clean_color_by_frame(raw: Variant) -> Dictionary:
	var result := {}
	if raw is Dictionary:
		for action: Variant in (raw as Dictionary).keys().slice(0, 64):
			if not raw[action] is Array or str(action) == "":
				continue
			var values: Array = []
			for entry: Variant in (raw[action] as Array).slice(0, 256):
				var text := str(entry)
				values.append(text if entry != null and Color.html_is_valid(text) and text.begins_with("#") else null)
			if values.any(func(v: Variant) -> bool: return v != null):
				result[str(action).left(32)] = values
	return result


static func clean_bool_by_frame(raw: Variant) -> Dictionary:
	var result := {}
	if raw is Dictionary:
		for action: Variant in (raw as Dictionary).keys().slice(0, 64):
			if not raw[action] is Array or str(action) == "":
				continue
			var values: Array = []
			for entry: Variant in (raw[action] as Array).slice(0, 256):
				values.append(entry if entry is bool else null)
			if values.any(func(v: Variant) -> bool: return v != null):
				result[str(action).left(32)] = values
	return result


## 把整理好的逐幀覆蓋(非空才)寫進 cleaned 對應的 "<prefix>_by_frame" 鍵。
static func write_cleaned(cleaned: Dictionary, prefix: String, by_frame: Dictionary) -> void:
	if not by_frame.is_empty():
		cleaned[prefix + "_by_frame"] = by_frame
