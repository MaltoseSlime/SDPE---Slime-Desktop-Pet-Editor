class_name AccessoryAnchors
extends RefCounted
## 配件(overlays.json 的部件)錨點的三層設定,和執行時 PetOverlays._anchor_for 的優先順序一致:
##   這個動作的逐幀錨點(frame_anchors[動作][幀])> 這個動作的錨點(anchors[動作])> 整個配件的預設錨點(anchor)。
## 精靈圖編輯器用它讀寫:在編輯器裡選「整個配件 / 只有目前這個動作 / 只有目前這一幀」再拖曳或改座標,就寫進對應的那一層。
## 全部是純函式,直接改傳進來的部件字典(呼叫端負責存檔與撤回點)。

const SCOPE_DEFAULT := 0
const SCOPE_ACTION := 1
const SCOPE_FRAME := 2


static func _point(value: Variant) -> Variant:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2 and ((value as Array)[0] is float or (value as Array)[0] is int) and ((value as Array)[1] is float or (value as Array)[1] is int):
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return null


static func _to_array(point: Vector2) -> Array:
	return [point.x, point.y]


## 這個部件在指定動作與幀的實際錨點(沒有任何設定回 Vector2.ZERO)。
static func effective(part: Dictionary, action: String, frame: int) -> Vector2:
	var by_frame: Variant = part.get("frame_anchors")
	if by_frame is Dictionary and (by_frame as Dictionary).get(action) is Array and not ((by_frame as Dictionary)[action] as Array).is_empty():
		var list: Array = (by_frame as Dictionary)[action]
		var from_list: Variant = _point(list[frame % list.size()])
		if from_list is Vector2:
			return from_list
	return _fallback(part, action)


## 不看逐幀那一層:這個動作的錨點 > 預設錨點。
static func _fallback(part: Dictionary, action: String) -> Vector2:
	var by_action: Variant = part.get("anchors")
	if by_action is Dictionary and (by_action as Dictionary).has(action):
		var from_action: Variant = _point((by_action as Dictionary)[action])
		if from_action is Vector2:
			return from_action
	var base: Variant = _point(part.get("anchor"))
	return base if base is Vector2 else Vector2.ZERO


## 現在生效的是哪一層(SCOPE_*)。
static func source_of(part: Dictionary, action: String) -> int:
	var by_frame: Variant = part.get("frame_anchors")
	if by_frame is Dictionary and (by_frame as Dictionary).get(action) is Array and not ((by_frame as Dictionary)[action] as Array).is_empty():
		return SCOPE_FRAME
	var by_action: Variant = part.get("anchors")
	if by_action is Dictionary and (by_action as Dictionary).has(action):
		return SCOPE_ACTION
	return SCOPE_DEFAULT


## 把錨點寫進指定的那一層。逐幀:這個動作第一次設逐幀錨點時,所有幀先填成「目前的實際位置」(其他幀看起來不變),再改這一幀。
## frame_count = 這個動作有幾幀。動作是空字串時只能寫預設層。
static func set_anchor(part: Dictionary, scope: int, action: String, frame: int, frame_count: int, at: Vector2) -> void:
	if action == "" or scope == SCOPE_DEFAULT:
		part["anchor"] = _to_array(at)
		return
	if scope == SCOPE_ACTION:
		var by_action: Dictionary = (part.get("anchors") as Dictionary) if part.get("anchors") is Dictionary else {}
		by_action[action] = _to_array(at)
		part["anchors"] = by_action
		return
	var by_frame: Dictionary = (part.get("frame_anchors") as Dictionary) if part.get("frame_anchors") is Dictionary else {}
	var list: Array = (by_frame.get(action) as Array).duplicate() if by_frame.get(action) is Array else []
	var count := maxi(frame_count, frame + 1)
	var current := _fallback(part, action)
	while list.size() < count:
		list.append(_to_array(current))
	list[frame] = _to_array(at)
	by_frame[action] = list
	part["frame_anchors"] = by_frame


## 清掉指定那一層的設定(回到比較上層的位置):動作層 = 刪掉 anchors[動作];幀層 = 這一幀改回上一層的位置,全部幀都和上一層一樣就整個刪掉。預設層不能清。
static func clear_scope(part: Dictionary, scope: int, action: String, frame: int) -> void:
	if action == "" or scope == SCOPE_DEFAULT:
		return
	if scope == SCOPE_ACTION:
		if part.get("anchors") is Dictionary:
			(part["anchors"] as Dictionary).erase(action)
			if (part["anchors"] as Dictionary).is_empty():
				part.erase("anchors")
		return
	if not (part.get("frame_anchors") is Dictionary and (part["frame_anchors"] as Dictionary).get(action) is Array):
		return
	var list: Array = (part["frame_anchors"] as Dictionary)[action]
	var fallback := _fallback(part, action)
	if frame >= 0 and frame < list.size():
		list[frame] = _to_array(fallback)
	var all_same := list.all(func(entry: Variant) -> bool: return _point(entry) == fallback)
	if all_same:
		(part["frame_anchors"] as Dictionary).erase(action)
		if (part["frame_anchors"] as Dictionary).is_empty():
			part.erase("frame_anchors")
