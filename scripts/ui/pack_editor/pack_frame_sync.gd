class_name PackFrameSync
extends RefCounted
## 精靈圖編輯器的「同步到其他動作」(2026-10-15 使用者要求):先把圖匯入一個沒在用的動作(整理用的來源動作)統一裁切、對軸,
## 再複製貼到真正的動作;來源動作打開同步後,之後在來源動作裡的調整會跟著帶到其他動作裡「用同一張原圖」的幀。
##
## 帶過去的東西(每一幀):圖片處理(fx,裁切翻轉旋轉)、軸心、圖片偏移、每盞光源在這一幀的位置/半徑/亮度/顏色/是否亮著、
## 每個圖層在這一幀的錨點與逐幀顯示設定。寫到目標幀上時一律寫成「這一幀自己的設定」(光源/圖層位置走 AccessoryAnchors 的逐幀層)。
##
## 規則(單向、只跟著沒自己改過的):
##   ・比對「同一張原圖」用原圖檔案 + 精靈圖切片範圍(不管圖片處理),見 base_key。
##   ・只在來源的某個值「真的變了」才帶過去,而且目標那一幀的這個值要還等於來源改之前的值——目標動作自己改過的值(或自己的光源、圖層設定)
##     就不會被蓋掉;目標動作的改動也永遠不會帶回來源動作。例外:來源的圖片處理變了,軸心的意義跟著變,所以圖片處理跟上時軸心一起跟上。
##   ・「立刻全部同步一次」(force)不看來源改之前的值,把目標幀直接改成跟來源一樣(只寫真的不一樣的值)。
##   ・圖層顯示比對的是逐幀設定(PackLayers.frame_rule),不是「在這些動作顯示」——整理用的動作通常不在那份清單裡。
## 純函式,直接改模型(呼叫端負責撤回點與畫面更新)。


## 幀的「原圖」身分:檔案 + 切片範圍(整張圖是空範圍),不含圖片處理。
static func base_key(model: PackEditorModel, path: String) -> String:
	if SpritePackLoader.is_virtual(path):
		var parsed := SpritePackLoader.parse_virtual(path)
		var file := str(parsed.get("file", ""))
		var relative := model._relative(file)
		return "%s|%s" % [relative if relative != "" else file, str(parsed.get("rect", Rect2i()))]
	var plain := model._relative(path)
	return "%s|%s" % [plain if plain != "" else path, str(Rect2i())]


## 光源 / 圖層在同步資料裡的鍵:名稱(同名的第二個以後加 #序號)。
static func _object_keys(list: Array, prefix: String) -> Array[String]:
	var keys: Array[String] = []
	var seen := {}
	for item: Dictionary in list:
		var name := str(item.get("name", ""))
		var count := int(seen.get(name, 0))
		seen[name] = count + 1
		keys.append("%s:%s%s" % [prefix, name, "" if count == 0 else "#%d" % count])
	return keys


static func _light_values(light: Dictionary, action: String, frame: int) -> Dictionary:
	return {"pos": PackLights.position_of(light, action, frame), "radius": PackLights.radius_of(light, action, frame), "energy": PackLights.energy_of(light, action, frame),
			"color": PackLights.color_of(light, action, frame), "on": PackLights.frame_enabled(light, action, frame)}


static func _part_values(part: Dictionary, action: String, frame: int) -> Dictionary:
	return {"pos": AccessoryAnchors.effective(part, action, frame), "vis": PackLayers.frame_rule(part, action, frame)}


## 來源動作目前的狀態:{原圖身分: {index, fx, pivot, offset, objs: {物件鍵: {欄位: 值}}}}(同一張原圖出現好幾次以第一次為準)。
static func state(model: PackEditorModel, action: String) -> Dictionary:
	var result := {}
	if not model.action_names().has(action):
		return result
	var lights := model.lights()
	var parts := model.accessories()
	var light_keys := _object_keys(lights, "L")
	var part_keys := _object_keys(parts, "P")
	for i in model.frame_count(action):
		var key := base_key(model, model.frame_path(action, i))
		if result.has(key):
			continue
		var objs := {}
		for n in lights.size():
			objs[light_keys[n]] = _light_values(lights[n], action, i)
		for n in parts.size():
			objs[part_keys[n]] = _part_values(parts[n], action, i)
		result[key] = {"index": i, "fx": model.fx_text(action, i), "pivot": model.pivot(action, i), "offset": model.offset(action, i), "objs": objs}
	return result


static func _same(a: Variant, b: Variant) -> bool:
	if a is Vector2 and b is Vector2:
		return (a as Vector2).is_equal_approx(b)
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b


## 把來源動作的變化帶到其他動作。old_state = 來源上一次的狀態(state 的結果);force = true 時不看舊狀態,目標直接改成跟來源一樣。
## 回傳 {frames: 改了幾幀, objects: 光源/圖層有沒有被改(呼叫端要重讀)}。
static func propagate(model: PackEditorModel, source: String, old_state: Dictionary, force := false) -> Dictionary:
	var result := {"frames": 0, "objects": false}
	var new_state := state(model, source)
	if new_state.is_empty() or (not force and new_state == old_state):
		return result
	var lights := model.lights()
	var parts := model.accessories()
	var light_index := {}
	var part_index := {}
	var light_keys := _object_keys(lights, "L")
	var part_keys := _object_keys(parts, "P")
	for n in light_keys.size():
		light_index[light_keys[n]] = n
	for n in part_keys.size():
		part_index[part_keys[n]] = n
	var touched := {}
	for target: String in model.action_names():
		if target == source:
			continue
		var count := model.frame_count(target)
		var frame_plans := {}
		for j in count:
			var key := base_key(model, model.frame_path(target, j))
			if not new_state.has(key):
				continue
			var now: Dictionary = new_state[key]
			var before: Variant = old_state.get(key)
			if not force and not before is Dictionary:
				continue   # 來源剛加進來的圖,沒有「改之前」可以比
			# --- 幀本身:圖片處理、軸心、圖片偏移 ---
			var plan := {}
			var fx_now := model.fx_text(target, j)
			var pivot_now := model.pivot(target, j)
			var offset_now := model.offset(target, j)
			if force:
				if fx_now != str(now["fx"]) or not _same(pivot_now, now["pivot"]):
					plan["fx"] = now["fx"]
					plan["pivot"] = now["pivot"]
				if not _same(offset_now, now["offset"]):
					plan["offset"] = now["offset"]
			else:
				if str(before["fx"]) != str(now["fx"]) and fx_now == str(before["fx"]):
					plan["fx"] = now["fx"]
					plan["pivot"] = now["pivot"]   # 圖片處理換了,軸心的座標意義跟著換,一起跟上
				elif not _same(before["pivot"], now["pivot"]) and _same(pivot_now, before["pivot"]) and fx_now == str(now["fx"]):
					plan["pivot"] = now["pivot"]
				if not _same(before["offset"], now["offset"]) and _same(offset_now, before["offset"]):
					plan["offset"] = now["offset"]
			if not plan.is_empty():
				frame_plans[j] = plan
				touched["%s/%d" % [target, j]] = true
			# --- 光源、圖層在這一幀的設定 ---
			var objs_now: Dictionary = now["objs"]
			var objs_before: Dictionary = (before as Dictionary)["objs"] if before is Dictionary else {}
			for object_key: String in objs_now:
				var is_light := object_key.begins_with("L:")
				var holder: Dictionary = {}
				if is_light and light_index.has(object_key):
					holder = lights[light_index[object_key]]
				elif not is_light and part_index.has(object_key) and not PackLayers.is_locked(parts[part_index[object_key]]):
					holder = parts[part_index[object_key]]   # 鎖住的圖層不同步
				else:
					continue
				var values_now: Dictionary = objs_now[object_key]
				var values_before: Variant = objs_before.get(object_key)
				if not force and not values_before is Dictionary:
					continue   # 來源剛新增的光源/圖層:目標看到的也是同一份預設值,不用帶
				var current := _light_values(holder, target, j) if is_light else _part_values(holder, target, j)
				for field: String in values_now:
					var wanted: Variant = values_now[field]
					if _same(current[field], wanted):
						continue
					if not force and (_same((values_before as Dictionary)[field], wanted) or not _same(current[field], (values_before as Dictionary)[field])):
						continue
					_write_object_field(holder, is_light, field, target, j, count, wanted)
					result["objects"] = true
					touched["%s/%d" % [target, j]] = true
		if not frame_plans.is_empty():
			_apply_frame_plans(model, target, frame_plans)
	if bool(result["objects"]):
		model.set_lights(lights)
		model.set_accessories(parts)
	result["frames"] = touched.size()
	return result


static func _write_object_field(holder: Dictionary, is_light: bool, field: String, action: String, frame: int, count: int, value: Variant) -> void:
	match field:
		"pos":
			if is_light:
				PackLights.set_position(holder, AccessoryAnchors.SCOPE_FRAME, action, frame, count, value)
			else:
				AccessoryAnchors.set_anchor(holder, AccessoryAnchors.SCOPE_FRAME, action, frame, count, value)
		"vis":
			PackLayers.set_frame_rule(holder, action, frame, count, value)
		"radius":
			PackLights.set_radius(holder, ScopedProperty.SCOPE_FRAME, action, frame, count, float(value))
		"energy":
			PackLights.set_energy(holder, ScopedProperty.SCOPE_FRAME, action, frame, count, float(value))
		"color":
			PackLights.set_color(holder, ScopedProperty.SCOPE_FRAME, action, frame, count, str(value))
		"on":
			PackLights.set_frame_enabled(holder, ScopedProperty.SCOPE_FRAME, action, frame, count, bool(value))


## 把幀本身的變化寫進目標動作的 frames 清單(一次寫完一個動作)。軸心、偏移寫成這一幀自己的設定。
static func _apply_frame_plans(model: PackEditorModel, action: String, plans: Dictionary) -> void:
	model.materialize(action)
	var refs := model.frame_refs(action)
	for j: int in plans:
		if j >= refs.size():
			continue
		var plan: Dictionary = plans[j]
		var ref: Variant = refs[j]
		var entry: Dictionary = {"file": ref} if ref is String else (ref as Dictionary).duplicate(true)
		if plan.has("fx"):
			if str(plan["fx"]) == "":
				entry.erase("fx")
			else:
				entry["fx"] = str(plan["fx"])
		for setting: String in ["pivot", "offset"]:
			if plan.has(setting):
				var point: Vector2 = plan[setting]
				entry[setting] = [int(point.x), int(point.y)]
		refs[j] = model._normalize_ref(entry)
	model._set_refs(action, refs)
