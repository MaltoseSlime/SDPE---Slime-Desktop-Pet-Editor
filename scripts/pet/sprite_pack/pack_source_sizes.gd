class_name PackSourceSizes
extends RefCounted
## 原圖尺寸記錄與自動重新對位(2026-10-16):直接在檔案總管把素材包裡的圖換成新的(例如用同一套匯出工具匯出另一個角色),
## 新圖的畫布大小跟舊的不一樣時,幀的裁切範圍、軸心、圖層的裁切與對齊點都是照舊圖的像素座標記的,套到新圖上會裁錯地方。
##
## 做法:精靈圖編輯器存檔時把每張原圖當時的大小記下來(pack.json 與 overlays.json 的 "source_sizes":{相對路徑: [寬, 高]})。
## 之後讀素材包時發現某張圖的大小跟記錄不同,就假設新圖是「同一套匯出方式、畫布放大/縮小、角色原點在畫布裡的相對位置不變、
## 像素比例不變」(匯出工具的常見行為):角色原點的相對位置 f 從素材包所有幀的軸心估出來(取中位數),
## 這張圖的所有座標一起平移 d = f × (新大小 − 舊大小)。
##   本體幀:軸心平移;裁切範圍平移後再放大到包住附近新畫的東西(本體幀的裁切幾乎都是裁透明邊,新角色的圖可能比較大)。
##   圖層:裁切範圍只平移不放大(圖層的裁切通常是刻意只框一小塊,例如只框眼睛);對齊點(origin)改成平移後的明確座標。
## 讀檔時只在記憶體裡換算(桌面直接能用);精靈圖編輯器打開時也會換算並標成未存檔,存檔後就寫進檔案、記錄更新成新大小。
## 沒有記錄的素材包(舊版存的、手寫的)不做任何事。

const KEY := "source_sizes"


## 圖檔的像素大小(PNG 只讀檔頭,其他格式整張讀)。讀不出來回 (0, 0)。
static func image_size(path: String) -> Vector2i:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Vector2i.ZERO
	if file.get_length() >= 24:
		var head := file.get_buffer(24)
		if head[0] == 0x89 and head[1] == 0x50 and head[2] == 0x4E and head[3] == 0x47:
			return Vector2i(_be32(head, 16), _be32(head, 20))
	file.close()
	var image := Image.load_from_file(path)
	return image.get_size() if image != null else Vector2i.ZERO


static func _be32(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


static func _size_of(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() >= 2 and ((value as Array)[0] is float or (value as Array)[0] is int) and ((value as Array)[1] is float or (value as Array)[1] is int):
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i.ZERO


## 幀清單裡的原圖檔(相對路徑;精靈圖切片不算)。
static func frame_files(manifest: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var frames: Variant = manifest.get("frames")
	if not frames is Dictionary:
		return result
	for action: Variant in frames:
		if not (frames as Dictionary)[action] is Array:
			continue
		for ref: Variant in (frames as Dictionary)[action]:
			var file := _ref_file(ref)
			if file != "" and not result.has(file):
				result.append(file)
	return result


static func _ref_file(ref: Variant) -> String:
	if ref is String:
		return str(ref)
	if ref is Dictionary and (ref as Dictionary).get("file") is String:
		return str((ref as Dictionary)["file"])
	return ""


## 圖層用到的原圖檔(部件與部件的 clips)。
static func overlay_files(spec: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for holder: Dictionary in _image_holders(spec):
		for file: String in _holder_images(holder):
			if not result.has(file):
				result.append(file)
	return result


## 有 images / image 的物件:每個部件本身與它 clips 裡的每一項。
static func _image_holders(spec: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not spec.get("overlays") is Array:
		return result
	for part: Variant in spec["overlays"]:
		if not part is Dictionary:
			continue
		result.append(part)
		if (part as Dictionary).get("clips") is Dictionary:
			for clip: Variant in (part["clips"] as Dictionary).values():
				if clip is Dictionary:
					result.append(clip)
	return result


static func _holder_images(holder: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if holder.get("images") is Array:
		for file: Variant in holder["images"]:
			result.append(str(file))
	elif holder.get("image") is String:
		result.append(str(holder["image"]))
	return result


## 存檔時:記下現在每張原圖的大小(只記讀得到的)。overlay_spec 是空的就只記 pack.json 的部分。
static func record(root: String, manifest: Dictionary, overlay_spec: Dictionary) -> void:
	var sizes := _measure(root, frame_files(manifest))
	if sizes.is_empty():
		manifest.erase(KEY)
	else:
		manifest[KEY] = sizes
	if overlay_spec.is_empty():
		return
	var overlay_sizes := _measure(root, overlay_files(overlay_spec))
	if overlay_sizes.is_empty():
		overlay_spec.erase(KEY)
	else:
		overlay_spec[KEY] = overlay_sizes


static func _measure(root: String, files: Array[String]) -> Dictionary:
	var sizes := {}
	for file in files:
		if file.contains("..") or file.is_absolute_path():
			continue
		var size := image_size(root.path_join(file))
		if size.x > 0 and size.y > 0:
			sizes[file] = [size.x, size.y]
	return sizes


## 記錄裡大小跟現在不一樣的圖:{相對路徑: [舊大小, 新大小]}。
static func _changed(root: String, recorded: Variant) -> Dictionary:
	var result := {}
	if not recorded is Dictionary:
		return result
	for file: Variant in recorded:
		var old := _size_of((recorded as Dictionary)[file])
		if old.x <= 0 or old.y <= 0 or str(file).contains(".."):
			continue
		var now := image_size(root.path_join(str(file)))
		if now.x > 0 and now.y > 0 and now != old:
			result[str(file)] = [old, now]
	return result


## 一個點從「處理後的圖」換回「原圖」的座標(PackImageFx.map_point 的反向)。sizes[k] = 第 k 步之前的圖大小。
static func _back_point(point: Vector2, ops: Array, sizes: Array) -> Vector2:
	var current := point
	for k in range(ops.size() - 1, -1, -1):
		var step: Dictionary = ops[k]
		var size: Vector2i = sizes[k]
		match str(step["op"]):
			"h":
				current = Vector2(float(size.x) - current.x, current.y)
			"v":
				current = Vector2(current.x, float(size.y) - current.y)
			"c":
				current += Vector2((step["rect"] as Rect2i).intersection(Rect2i(Vector2i.ZERO, size)).position)
			"r":
				var after: Vector2i = sizes[k + 1]
				var radians := -deg_to_rad(fposmod(float(step["degrees"]), 360.0))
				var relative := current - Vector2(after) * 0.5
				current = Vector2(relative.x * cos(radians) - relative.y * sin(radians), relative.x * sin(radians) + relative.y * cos(radians)) + Vector2(size) * 0.5
	return current


## 每一步之前的圖大小(最後多一項 = 處理完的大小)。
static func _stage_sizes(size: Vector2i, ops: Array) -> Array:
	var sizes: Array = [size]
	var current := size
	for step: Dictionary in ops:
		current = PackImageFx.size_after(current, step)
		sizes.append(current)
	return sizes


static func _ops_of(ref: Variant) -> Array:
	var parsed: Variant = PackImageFx.parse(str((ref as Dictionary).get("fx", ""))) if ref is Dictionary else []
	return parsed if parsed is Array else []


## 這一幀(舊圖)軸心在原圖上的位置:幀自己的 pivot > pivots 表 > 自動(底邊中央,見 SpritePackLoader._pivot_for)。
static func _source_pivot(ref: Variant, action: String, old_size: Vector2i, manifest: Dictionary) -> Vector2:
	var ops := _ops_of(ref)
	var sizes := _stage_sizes(old_size, ops)
	var processed: Vector2i = sizes[sizes.size() - 1]
	var raw: Variant = (ref as Dictionary).get("pivot") if ref is Dictionary else null
	var post := SpritePackLoader._pivot_for(_ref_file(ref), action, {"size": processed, "tag": Rect2i()}, manifest, false)
	if raw is Array and (raw as Array).size() >= 2 and ((raw as Array)[0] is float or (raw as Array)[0] is int) and ((raw as Array)[1] is float or (raw as Array)[1] is int):
		post = Vector2(float(raw[0]), float(raw[1]))
	return _back_point(post, ops, sizes)


## 角色原點在畫布裡的相對位置:素材包裡用 sizes(檔案 → 大小)量得到的每一幀,軸心在原圖上的位置 ÷ 原圖大小,取中位數。量不到回 (0.5, 1)。
static func estimate_fraction(manifest: Dictionary, sizes: Dictionary) -> Vector2:
	var xs: Array[float] = []
	var ys: Array[float] = []
	var frames: Variant = manifest.get("frames")
	if frames is Dictionary:
		for action: Variant in frames:
			if not (frames as Dictionary)[action] is Array:
				continue
			for ref: Variant in (frames as Dictionary)[action]:
				var size: Variant = sizes.get(_ref_file(ref))
				if not size is Vector2i or (size as Vector2i).x <= 0:
					continue
				var point := _source_pivot(ref, str(action), size, manifest)
				xs.append(point.x / float((size as Vector2i).x))
				ys.append(point.y / float((size as Vector2i).y))
	if xs.is_empty():
		return Vector2(0.5, 1.0)
	xs.sort()
	ys.sort()
	return Vector2(xs[xs.size() / 2], ys[ys.size() / 2])


static func _shift(fraction: Vector2, old: Vector2i, now: Vector2i) -> Vector2i:
	return Vector2i(roundi(fraction.x * float(now.x - old.x)), roundi(fraction.y * float(now.y - old.y)))


## pack.json:大小變了的圖重新對位(直接改 manifest)。回傳換算過的檔案清單;沒有記錄或都沒變回空陣列。
static func realign_manifest(root: String, manifest: Dictionary) -> Array[String]:
	var done: Array[String] = []
	var changed := _changed(root, manifest.get(KEY))
	if changed.is_empty():
		return done
	var old_sizes := {}
	for file: Variant in manifest[KEY]:
		old_sizes[str(file)] = _size_of(manifest[KEY][file])
	var fraction := estimate_fraction(manifest, old_sizes)
	var images := {}
	var frames: Dictionary = manifest["frames"] if manifest.get("frames") is Dictionary else {}
	for action: Variant in frames:
		if not frames[action] is Array:
			continue
		var list: Array = frames[action]
		for n in list.size():
			var file := _ref_file(list[n])
			if not changed.has(file):
				continue
			if not images.has(file):
				images[file] = Image.load_from_file(root.path_join(file))
			var image: Image = images[file]
			if image == null:
				continue
			list[n] = _realign_ref(list[n], str(action), changed[file][0], changed[file][1], fraction, image, manifest)
			if not done.has(file):
				done.append(file)
	for file: String in done:
		manifest[KEY][file] = [(changed[file][1] as Vector2i).x, (changed[file][1] as Vector2i).y]
	return done


static func _realign_ref(ref: Variant, action: String, old: Vector2i, now: Vector2i, fraction: Vector2, image: Image, manifest: Dictionary) -> Dictionary:
	var entry: Dictionary = (ref as Dictionary).duplicate(true) if ref is Dictionary else {"file": str(ref)}
	var shift := _shift(fraction, old, now)
	var ops := _ops_of(entry)
	var sizes := _stage_sizes(old, ops)
	var pivot := _source_pivot(entry, action, old, manifest) + Vector2(shift)
	var new_ops: Array = []
	if ops.any(func(step: Dictionary) -> bool: return str(step["op"]) == "c"):
		# 舊的裁切範圍(原圖座標):處理後的圖四個角換回原圖取外框
		var processed: Vector2i = sizes[sizes.size() - 1]
		var corners := [Vector2.ZERO, Vector2(processed.x, 0), Vector2(0, processed.y), Vector2(processed)]
		var box := Rect2(_back_point(corners[0], ops, sizes), Vector2.ZERO)
		for corner: Vector2 in corners:
			box = box.expand(_back_point(corner, ops, sizes))
		var moved := Rect2i(Vector2i(box.position.round()) + shift, Vector2i(box.size.round()))
		var crop := _grow_to_content(image, moved).expand(Vector2i(pivot.round())).intersection(Rect2i(Vector2i.ZERO, now))
		new_ops.append({"op": "c", "rect": crop})
		for step: Dictionary in ops:
			if str(step["op"]) != "c":
				new_ops.append(step)
	else:
		new_ops = ops
	var text := PackImageFx.serialize(new_ops)
	if text == "":
		entry.erase("fx")
	else:
		entry["fx"] = text
	var post := PackImageFx.map_point_through(pivot, now, new_ops)
	entry["pivot"] = [roundi(post.x), roundi(post.y)]
	return entry


## 本體幀的裁切:平移後的範圍再放大到包住附近(往外一個範圍邊長內)新畫的東西,新角色的圖比較大也不會被切到。
static func _grow_to_content(image: Image, moved: Rect2i) -> Rect2i:
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	var near := moved.grow(maxi(moved.size.x, moved.size.y)).intersection(bounds)
	var result := moved.intersection(bounds)
	if near.size.x <= 0 or near.size.y <= 0:
		return result if result.size.x > 0 else moved
	var used := image.get_region(near).get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		var content := Rect2i(near.position + used.position, used.size)
		result = content if result.size.x <= 0 or result.size.y <= 0 else result.merge(content)
	return result


## overlays.json:大小變了的圖層圖重新對位(直接改 spec)。manifest 用來估角色原點的相對位置(本體幀現在的大小)。
## 回傳 {done: 換算過的檔案, skipped: 沒辦法換算的部件名稱(同一個部件裡有的圖換了、有的沒換,共用的對齊點沒辦法同時對上)}。
static func realign_overlays(root: String, spec: Dictionary, manifest: Dictionary) -> Dictionary:
	var done: Array[String] = []
	var skipped: Array[String] = []
	var changed := _changed(root, spec.get(KEY))
	if changed.is_empty():
		return {"done": done, "skipped": skipped}
	var now_sizes := {}
	for file: String in frame_files(manifest):
		now_sizes[file] = image_size(root.path_join(file))
	var fraction := estimate_fraction(manifest, now_sizes)
	for part: Variant in spec.get("overlays", []):
		if not part is Dictionary:
			continue
		var holders: Array[Dictionary] = [part]
		if (part as Dictionary).get("clips") is Dictionary:
			for clip: Variant in (part["clips"] as Dictionary).values():
				if clip is Dictionary:
					holders.append(clip)
		var pairs := {}
		var untouched := false
		for holder: Dictionary in holders:
			var files := _holder_images(holder)
			for k in files.size():
				if not changed.has(files[k]):
					untouched = true
					continue
				var old: Vector2i = changed[files[k]][0]
				var now: Vector2i = changed[files[k]][1]
				pairs["%s>%s" % [old, now]] = [old, now]
				var shift := _shift(fraction, old, now)
				if holder.get("crops") is Array and k < (holder["crops"] as Array).size():
					var rect: Variant = PetOverlays.crop_rect(holder["crops"][k])
					if rect is Rect2i:
						holder["crops"][k] = [(rect as Rect2i).position.x + shift.x, (rect as Rect2i).position.y + shift.y, (rect as Rect2i).size.x, (rect as Rect2i).size.y]
				if not done.has(files[k]):
					done.append(files[k])
		if pairs.is_empty():
			continue
		if pairs.size() > 1 or untouched:
			skipped.append(str((part as Dictionary).get("name", "?")))
			continue
		# 對齊點:照舊圖大小算出來的那一點平移過去,寫成明確座標(center 這類寫法會跟著新圖大小變,不能沿用)
		var pair: Array = pairs.values()[0]
		var origin := PetOverlays._origin_pixels((part as Dictionary).get("origin", "center"), Vector2(pair[0])) + Vector2(_shift(fraction, pair[0], pair[1]))
		part["origin"] = [origin.x, origin.y]
	for file: String in done:
		spec[KEY][file] = [(changed[file][1] as Vector2i).x, (changed[file][1] as Vector2i).y]
	return {"done": done, "skipped": skipped}
