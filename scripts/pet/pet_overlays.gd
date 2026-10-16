class_name PetOverlays
extends Node2D
## 半身立繪的「浮動差分與配件」:把小圖以指定座標(錨點)覆蓋在立繪的對應動作上,用來做眨眼、說話嘴型、手勢、身上裝飾。
## 立繪本體是「每個動作一幀」,所以錨點以「動作」為單位、座標用立繪原圖的像素座標(從圖的左上角算)。
## 部件是 Pet 視覺根節點的子節點:跟著本體一起縮放、翻轉、呼吸伸縮;圖層由 z_index 相對值決定
## (-1 本體後面、0 本體之上、+1 最上層、9 光源之上——PetLights 掛在同一個視覺根節點下、z_index=8,
## 「光源之上」的部件才會蓋過身上的光暈,其餘三層(含「最上層」)都在光暈底下,見 PackLayers),
## 而立繪本身在 DrawLayers.STILL 的帶裡,所以部件永遠不會跑到別的桌寵前面。
##
## 設定檔 overlays.json(放在立繪資料夾或素材包資料夾)的格式見 docs/素材包格式.md「浮動差分與配件」。
## 座標空間 space:"image"(預設,半身立繪用:立繪原圖的像素座標,從左上角算)或 "pivot"(素材包的一般桌寵用:
## 相對於腳底軸心的偏移,x 向右、y 向下,單位是縮放前像素,例如帽子放在 [0, -70])。一般桌寵的動作是多幀動畫,
## 所以錨點除了每個動作一個(anchors),還可以每一幀一個(frame_anchors:{動作: [[x,y], 第 0 幀, 第 1 幀…]}),部件跟著本體幀走。
## 部件是視覺根節點的子節點,所以左右翻轉、爬牆/天花板的旋轉、縮放、呼吸都會自動跟著本體。
## 部件的 role:
##   part   一般部件(手勢、裝飾):在列出的動作裡一直顯示,多張圖依 fps 循環;
##   blink  眨眼:隨機間隔短暫出現(說話中不眨),多張圖在 duration 秒內依序播完;
##   speak  說話:講話(打字機滾動)期間顯示,多張圖依 fps 循環(嘴型)。
## 部件的 flip_h / flip_v(true = 水平 / 垂直翻轉,2026-10-16):整個部件的圖在原地翻(佔的範圍不變),跟桌寵面向的鏡像各算各的。
## 部件的 scale(預設 1)是整體縮放倍數,借用別的角色的圖當替身配件時很方便(像素圖用 nearest 放大成整數倍再存檔最清楚)。
## 配件動畫(clips):一個部件可以有多段動畫,再指定「哪個動作播哪一段」,例如拿著茶杯的角色平常播冒煙(steam),
## 換到某個表情動作就播喝茶(sip):
##   "clips": {"steam": {"images": [...], "fps": 5}, "sip": {"images": [...], "fps": 6, "loop": false}},
##   "clip_for": {"pose_03": "sip", "*": "steam"}
## 部件本身的 images / fps / loop 是「預設動畫」(名字 default);沒有 clip_for 對到的動作就播預設動畫(沒有預設就播 clip_for["*"] 或第一段)。
## loop = false 的動畫每次(重新)顯示時從頭播一次,停在最後一幀。
## 逐幀顯示(frame_visible:{動作: [true / false / null, 第 0 幀, 第 1 幀…]},2026-10-13):角色在動畫裡每一幀的角度可能不同,
## 某幾幀要把圖層藏起來(或只在某幾幀露出來)時用。null(或沒寫)= 這一幀照平常的規則;false = 這一幀不顯示;
## true = 這一幀要顯示——一般部件(part)連「在這些動作顯示」沒列到的動作也會顯示,眨眼/說話差分則照樣只在眨眼/說話時出現。
## 執行期的開關與位移(積木「顯示/隱藏圖層」「移動圖層」,見 Pet.set_layer_visible / move_layer):關掉的圖層不管種類都不顯示;
## 位移是加在錨點上的像素(縮放前,跟錨點同一個座標空間)。
## 家具的圖層(2026-10-15,見 FurnitureItem):同一套格式掛在家具上,「動作」是家具的狀態(normal / conditional / interacted)。
## 另外多「誰在用時顯示」(只有家具會看,見 FurnitureItem.overlay_allows):
##   "used_by": "always"(預設,不看有沒有人在用)/ "idle"(沒有桌寵在用)/ "in_use"(有桌寵在用)/
##              "pets"(used_by_tags 列的桌寵在用)/ "not_pets"(used_by_tags 以外的桌寵在用);
##   "used_by_tags": [桌寵的辨識代號…];"used_seat": 只看第幾個坐躺位置(0 起算,-1 或沒寫 = 任何位置)。
## 「在用」= 桌寵已經走到定位坐/躺下(走過去的路上不算)。
## 安全:圖檔路徑只能是資料夾內的相對路徑(不允許 .. 或絕對路徑),圖片有大小上限,部件、動畫與幀數有上限,壞的部件略過並回報。

const MAX_PARTS := 48
const MAX_CLIPS := 16
const MAX_FRAMES := 32
const MAX_SIDE := 2048
const MAX_FILE_BYTES := 8_000_000
const IMAGE_EXTENSIONS: Array[String] = ["png", "webp", "jpg", "jpeg"]
const ROLES := {"part": "part", "decor": "part", "gesture": "part", "blink": "blink", "speak": "speak"}
const LAYER_Z := {"back": -1, "front": 0, "top": 1, "above_light": 9}
const DEFAULT_FPS := 8.0
const DEFAULT_BLINK_SECONDS := 0.18
const BLINK_INTERVAL := Vector2(2.5, 6.0)
const DEFAULT_CLIP := "default"
## 家具圖層的「誰在用時顯示」(見檔頭)。
const USED_BY_MODES: Array[String] = ["always", "idle", "in_use", "pets", "not_pets"]

var _pet: Node
var _pivot_space := false
var _base_size := Vector2.ZERO
var _sprite_position := Vector2.ZERO
var _parts: Array[Dictionary] = []
var _blink_left := 0.0
var _blink_duration := 0.0
var _blink_next := 3.0
var _clock := 0.0
## 使用者在右鍵選單「變更配件」關掉的配件(部件名稱);關掉的不顯示、不佔穿透形狀。眨眼與說話差分(role blink / speak)不算配件,不能關。
var _disabled: Array[String] = []
## 積木移動過的圖層:{部件名稱: Vector2(加在錨點上的位移)}。
var _offsets: Dictionary = {}


## 建立部件。base_size = 立繪一幀的像素大小(座標參考畫布),sprite_position = 本體精靈在視覺根節點裡的位置。回傳讀取報告。
func setup(pet: Node, spec: Dictionary, base_dir: String, base_size: Vector2, sprite_position: Vector2) -> Array[String]:
	_pet = pet
	_base_size = base_size
	_sprite_position = sprite_position
	_pivot_space = str(spec.get("space", "image")).to_lower() == "pivot"
	var report: Array[String] = []
	var raw_parts: Variant = spec.get("overlays", [])
	if not raw_parts is Array:
		report.append("overlays 不是陣列,已忽略。")
		return report
	_prefetch(raw_parts, base_dir)
	for raw: Variant in raw_parts:
		if _parts.size() >= MAX_PARTS:
			report.append(tr("部件超過 %d 個的上限,多的已略過。") % MAX_PARTS)
			break
		var part := _build_part(raw, base_dir, report)
		if not part.is_empty():
			_parts.append(part)
	_prefetched.clear()
	return report


# --- 平行預先解碼(2026-10-17 效能,同 SpritePackLoader._prefetch):圖層的圖常是整張大畫布只畫一小塊,
# 一張張解碼要 0.1~0.2 秒;先用 WorkerThreadPool 平行解碼好,_load_image 先拿這裡的。讀不出來、太大的不放,照原本的流程讀並記錄。

## 完整路徑 → Image。只在 setup 期間有內容。
static var _prefetched: Dictionary = {}
static var _prefetch_mutex := Mutex.new()


static func _prefetch(raw_parts: Array, base_dir: String) -> void:
	if not SpritePackLoader.parallel_decode:
		return
	var paths: Array = []
	for raw: Variant in raw_parts.slice(0, MAX_PARTS):
		if not raw is Dictionary:
			continue
		var holders: Array = [raw]
		if (raw as Dictionary).get("clips") is Dictionary:
			holders.append_array(((raw as Dictionary)["clips"] as Dictionary).values())
		for holder: Variant in holders:
			if not holder is Dictionary:
				continue
			var files: Array = holder["images"] if (holder as Dictionary).get("images") is Array else ([holder["image"]] if (holder as Dictionary).get("image") is String else [])
			for file_name: Variant in files.slice(0, MAX_FRAMES):
				var text := str(file_name)
				if text == "" or text.contains("..") or text.is_absolute_path() or not IMAGE_EXTENSIONS.has(text.get_extension().to_lower()):
					continue
				var path := base_dir.path_join(text)
				if not paths.has(path):
					paths.append(path)
	if paths.size() < 2:
		return
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void: _prefetch_one(paths[i]), paths.size(), -1, true, "overlay decode")
	WorkerThreadPool.wait_for_group_task_completion(task)


static func _prefetch_one(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return
	var decoded: Variant = SpritePackLoader._decode_raw(path)
	if not decoded is Image or (decoded as Image).get_width() > MAX_SIDE or (decoded as Image).get_height() > MAX_SIDE:
		return
	_prefetch_mutex.lock()
	_prefetched[path] = decoded
	_prefetch_mutex.unlock()


## 一段動畫 = {textures, fps, loop}。raw 是有 images / image / fps / loop 的物件(部件本身或 clips 裡的一項);圖都讀不出來回空字典。
func _build_clip(raw: Dictionary, base_dir: String, report: Array[String]) -> Dictionary:
	var image_files: Array = []
	if raw.get("images") is Array:
		image_files = raw["images"]
	elif raw.get("image") is String:
		image_files = [raw["image"]]
	var crops: Array = raw["crops"] if raw.get("crops") is Array else []
	var textures: Array[Texture2D] = []
	var slot := 0
	for file_name: Variant in image_files.slice(0, MAX_FRAMES):
		var texture := load_cropped(base_dir, str(file_name), crops[slot] if slot < crops.size() else null, report)
		slot += 1
		if texture != null:
			textures.append(texture)
	if textures.is_empty():
		return {}
	var fps := DEFAULT_FPS
	if raw.get("fps") is float or raw.get("fps") is int:
		fps = clampf(float(raw["fps"]), 0.5, 60.0)
	return {"textures": textures, "fps": fps, "loop": bool(raw.get("loop", true))}


func _build_part(raw: Variant, base_dir: String, report: Array[String]) -> Dictionary:
	if not raw is Dictionary:
		report.append("有一個部件不是物件,已略過。")
		return {}
	var part_name := str(raw.get("name", tr("部件%d") % (_parts.size() + 1))).left(40)
	# 精靈圖編輯器「圖層」裡種類設成「待呼叫」的部件(visible: false):照樣建立,但平常不出現,
	# 只有積木「暫時顯示圖層」或狀態鏡的「啟用時暫時顯示圖層」要它出現時才出現(2026-10-15 起;之前是整個不建立)。
	var dormant := raw.get("visible") is bool and not bool(raw["visible"])
	var role_text := str(raw.get("role", "part")).to_lower()
	if not ROLES.has(role_text):
		report.append(tr("部件「%s」的 role「%s」不認得(part / blink / speak),已略過。") % [part_name, role_text])
		return {}
	var clips := {}
	var default_clip := _build_clip(raw, base_dir, report)
	if not default_clip.is_empty():
		clips[DEFAULT_CLIP] = default_clip
	if raw.get("clips") is Dictionary:
		for clip_name: Variant in (raw["clips"] as Dictionary).keys().slice(0, MAX_CLIPS):
			var clip_spec: Variant = raw["clips"][clip_name]
			if not clip_spec is Dictionary:
				report.append(tr("部件「%s」的動畫「%s」不是物件,已略過。") % [part_name, clip_name])
				continue
			var clip := _build_clip(clip_spec, base_dir, report)
			if clip.is_empty():
				report.append(tr("部件「%s」的動畫「%s」沒有可用的圖片,已略過。") % [part_name, clip_name])
			else:
				clips[str(clip_name)] = clip
	if clips.is_empty():
		report.append(tr("部件「%s」沒有可用的 image / images / clips,已略過。") % part_name)
		return {}
	var clip_for := {}
	if raw.get("clip_for") is Dictionary:
		for action: String in raw["clip_for"]:
			var wanted := str(raw["clip_for"][action])
			if clips.has(wanted):
				clip_for[action] = wanted
			else:
				report.append(tr("部件「%s」的 clip_for「%s」指到不存在的動畫「%s」,已略過。") % [part_name, action, wanted])
	var base_clip := DEFAULT_CLIP if clips.has(DEFAULT_CLIP) else str(clip_for.get("*", clips.keys()[0]))
	var anchor: Variant = _vector(raw.get("anchor"))
	var anchors_by_action: Dictionary = {}
	if raw.get("anchors") is Dictionary:
		for action: String in raw["anchors"]:
			var by_action: Variant = _vector(raw["anchors"][action])
			if by_action is Vector2:
				anchors_by_action[action] = by_action
	var frame_anchors: Dictionary = {}
	if raw.get("frame_anchors") is Dictionary:
		for action: String in raw["frame_anchors"]:
			var list: Variant = raw["frame_anchors"][action]
			if list is Array:
				var points: Array[Vector2] = []
				for entry: Variant in list.slice(0, 256):
					var point: Variant = _vector(entry)
					points.append(point if point is Vector2 else Vector2.ZERO)
				if not points.is_empty():
					frame_anchors[action] = points
	var frame_visible: Dictionary = {}
	if raw.get("frame_visible") is Dictionary:
		for action: String in raw["frame_visible"]:
			var flags: Variant = raw["frame_visible"][action]
			if flags is Array and not (flags as Array).is_empty():
				frame_visible[action] = (flags as Array).slice(0, 256).map(func(entry: Variant) -> Variant: return entry if entry is bool else null)
	if not anchor is Vector2 and anchors_by_action.is_empty() and frame_anchors.is_empty():
		report.append(tr("部件「%s」沒有 anchor(錨點座標),已略過。") % part_name)
		return {}
	var used_by := str(raw.get("used_by", "always")).to_lower()
	if not USED_BY_MODES.has(used_by):
		used_by = "always"
	var used_by_tags: Array[String] = []
	if raw.get("used_by_tags") is Array:
		for tag: Variant in (raw["used_by_tags"] as Array).slice(0, 64):
			if str(tag).strip_edges() != "" and not used_by_tags.has(str(tag).strip_edges()):
				used_by_tags.append(str(tag).strip_edges())
	var mirror_for: Array[String] = []
	if raw.get("mirror_for") is Array:
		for action: Variant in (raw["mirror_for"] as Array).slice(0, 256):
			mirror_for.append(str(action))
	var used_seat := int(raw["used_seat"]) if (raw.get("used_seat") is float or raw.get("used_seat") is int) else -1
	var actions: Array[String] = []
	var raw_actions: Variant = raw.get("actions", ["*"])
	if raw_actions is Array:
		for action: Variant in raw_actions:
			actions.append(str(action))
	if actions.is_empty():
		actions = ["*"]
	var node := Sprite2D.new()
	node.centered = false
	node.z_index = int(LAYER_Z.get(str(raw.get("layer", "front")).to_lower(), 0))
	# 取樣方式不另外設:跟著 PetOverlays 自己(Pet 會設成跟本體一樣,見 Pet.set_smooth_scaling)。
	# 2026-10-15 之前寫死平滑取樣,像素風角色的眨眼差分在本體是最近點取樣、放大顯示時特別糊(使用者回報)。
	node.use_parent_material = true   # 清晰像素取樣(SharpPixel)也跟本體一樣,由 Pet 設在 PetOverlays 上
	var part_scale := 1.0
	if raw.get("scale") is float or raw.get("scale") is int:
		part_scale = clampf(float(raw["scale"]), 0.05, 8.0)
	node.scale = Vector2.ONE * part_scale
	node.flip_h = raw.get("flip_h") is bool and bool(raw["flip_h"])
	node.flip_v = raw.get("flip_v") is bool and bool(raw["flip_v"])
	var first_texture: Texture2D = clips[base_clip]["textures"][0]
	node.texture = first_texture
	node.offset = texture_offset(raw.get("origin", "center"), first_texture)
	node.visible = false
	add_child(node)
	# 所有圖(裁切後)相對錨點佔的範圍,縮放前:穿透形狀用(見 union_rect)。
	var bounds := Rect2()
	var first_bounds := true
	for clip: Dictionary in clips.values():
		for texture: Texture2D in clip["textures"]:
			var rect := Rect2(texture_offset(raw.get("origin", "center"), texture), Vector2(texture.get_size()))
			bounds = rect if first_bounds else bounds.merge(rect)
			first_bounds = false
	return {
		"name": part_name,
		"role": ROLES[role_text],
		"node": node,
		"clips": clips,
		"clip_for": clip_for,
		"base_clip": base_clip,
		"origin": raw.get("origin", "center"),
		"scale": part_scale,
		"bounds": bounds,
		"dormant": dormant,
		"actions": actions,
		"anchor": anchor if anchor is Vector2 else Vector2.ZERO,
		"anchors": anchors_by_action,
		"frame_anchors": frame_anchors,
		"frame_visible": frame_visible,
		"mirror_for": mirror_for,
		"used_by": used_by,
		"used_by_tags": used_by_tags,
		"used_seat": used_seat,
		"duration": clampf(float(raw.get("duration", DEFAULT_BLINK_SECONDS)) if (raw.get("duration") is float or raw.get("duration") is int) else DEFAULT_BLINK_SECONDS, 0.05, 3.0),
		"clip_name": "",
		"clip_start": 0.0,
	}


static func _vector(value: Variant) -> Variant:
	if value is Array and value.size() >= 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2(float(value[0]), float(value[1]))
	return null


## 部件圖片裡「放在錨點上的那一點」(像素座標):center(預設)、top_left、bottom_center,或 [x, y]。
static func _origin_pixels(origin: Variant, size: Vector2) -> Vector2:
	if origin is Array:
		var explicit: Variant = _vector(origin)
		return explicit if explicit is Vector2 else size * 0.5
	match str(origin).to_lower():
		"top_left":
			return Vector2.ZERO
		"bottom_center":
			return Vector2(size.x * 0.5, size.y)
		"top_center":
			return Vector2(size.x * 0.5, 0.0)
	return size * 0.5


## 圖層圖片的裁切(2026-10-15,overlays.json 部件或 clips 項目的 "crops":和 images 一一對應的 [x, y, 寬, 高] 或 null):
## 只顯示圖上的這一塊,位置不變——「圖上放在錨點的那一點」(origin)仍然照原圖算,所以裁切不會讓圖層跑掉,只是少畫空白。
## 格式不對回 null(= 不裁切)。
static func crop_rect(value: Variant) -> Variant:
	if not value is Array or (value as Array).size() < 4:
		return null
	for entry: Variant in (value as Array).slice(0, 4):
		if not (entry is float or entry is int):
			return null
	var rect := Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))
	if rect.position.x < 0 or rect.position.y < 0 or rect.size.x < 1 or rect.size.y < 1:
		return null
	return rect


## 讀一張圖層圖片並套用裁切(crop 是 crop_rect 認得的值,null = 不裁)。回傳的貼圖帶兩個 meta:
## "full" = 原圖大小、"trim" = 裁切範圍的左上角(都是 Vector2),畫的時候用 texture_offset 換算位置。
static func load_cropped(base_dir: String, file_name: String, crop: Variant, report: Array[String]) -> Texture2D:
	var image := _load_image(base_dir, file_name, report)
	if image == null:
		return null
	var full := Vector2(image.get_size())
	var trim := Vector2.ZERO
	var rect: Variant = crop_rect(crop)
	if rect is Rect2i:
		var clipped := (rect as Rect2i).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if clipped.size.x > 0 and clipped.size.y > 0:
			image = image.get_region(clipped)
			trim = Vector2(clipped.position)
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta("full", full)
	texture.set_meta("trim", trim)
	return texture


## 圖層貼圖的 Sprite2D.offset(錨點到圖左上角的位移):依原圖大小找 origin 那一點,再加回裁切掉的左上角。
static func texture_offset(origin: Variant, texture: Texture2D) -> Vector2:
	var full: Vector2 = texture.get_meta("full", Vector2(texture.get_size()))
	return -_origin_pixels(origin, full) + (texture.get_meta("trim", Vector2.ZERO) as Vector2)


static func _load_texture(base_dir: String, file_name: String, report: Array[String]) -> Texture2D:
	return load_cropped(base_dir, file_name, null, report)


static func _load_image(base_dir: String, file_name: String, report: Array[String]) -> Image:
	if file_name == "" or file_name.contains("..") or file_name.is_absolute_path() or file_name.begins_with("/") or file_name.begins_with("\\"):
		report.append(TranslationServer.translate("圖片路徑「%s」不合法(只能是資料夾內的相對路徑),已略過。") % file_name)
		return null
	if not IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
		report.append(TranslationServer.translate("圖片「%s」不是 png / webp / jpg,已略過。") % file_name)
		return null
	var path := base_dir.path_join(file_name)
	var ready: Variant = _prefetched.get(path)
	if ready is Image:
		return ready
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		report.append(TranslationServer.translate("圖片「%s」讀不了或太大,已略過。") % file_name)
		return null
	var bytes := file.get_buffer(file.get_length())
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match file_name.get_extension().to_lower():
		"png":
			error = image.load_png_from_buffer(bytes)
		"webp":
			error = image.load_webp_from_buffer(bytes)
		_:
			error = image.load_jpg_from_buffer(bytes)
	if error != OK or image.is_empty() or image.get_width() > MAX_SIDE or image.get_height() > MAX_SIDE:
		report.append(TranslationServer.translate("圖片「%s」毀損或尺寸超過 %d,已略過。") % [file_name, MAX_SIDE])
		return null
	return image


func part_count() -> int:
	return _parts.size()


## 可以開關的配件名稱(role = part 的部件,依素材包裡的順序,同名只列一次)。
## 平常不顯示的只有「在某些幀設了要顯示」的才算(那幾幀會自己出現,所以也要能關),其餘只靠積木/狀態鏡叫出來,不列。
func accessory_names() -> Array[String]:
	var names: Array[String] = []
	for part: Dictionary in _parts:
		if str(part["role"]) == "part" and (not bool(part["dormant"]) or _has_frame_show(part)) and not names.has(str(part["name"])):
			names.append(str(part["name"]))
	return names


func set_disabled(names: Array) -> void:
	_disabled.clear()
	for entry: Variant in names:
		_disabled.append(str(entry))


func is_accessory_enabled(part_name: String) -> bool:
	return not _disabled.has(part_name)


## 所有圖層(部件)的名稱,不分種類,依素材包裡的順序,同名只列一次。給積木的圖層選單(Schema 的 layers)用。
func layer_names() -> Array[String]:
	var names: Array[String] = []
	for part: Dictionary in _parts:
		if not names.has(str(part["name"])):
			names.append(str(part["name"]))
	return names


## 這個圖層是「平常不顯示」的嗎(精靈圖編輯器種類設成「待呼叫」,overlays.json 的 visible: false)。找不到也回 false。
func is_dormant(part_name: String) -> bool:
	for part: Dictionary in _parts:
		if str(part["name"]) == part_name:
			return bool(part["dormant"])
	return false


## 積木移動過的圖層位移:{部件名稱: Vector2}。
func set_offsets(offsets: Dictionary) -> void:
	_offsets = offsets.duplicate()


## 逐幀顯示裡有沒有任何一幀明確設成「顯示」。
static func _has_frame_show(part: Dictionary) -> bool:
	for flags: Array in (part["frame_visible"] as Dictionary).values():
		if flags.has(true):
			return true
	return false


## 這個部件在這個動作、這一幀的逐幀顯示設定:true / false,沒有設定回 null。
## plain = 去掉朝向後綴的動作名稱(播朝左專用的 walk_left 時是 walk):這個朝向版本沒有自己的設定就用原動作的。
static func _frame_rule(part: Dictionary, action: String, frame: int, plain := "") -> Variant:
	var by_action: Dictionary = part["frame_visible"]
	if not by_action.has(action):
		if plain == "" or plain == action or not by_action.has(plain):
			return null
		action = plain
	var flags: Array = by_action[action]
	return flags[frame] if frame >= 0 and frame < flags.size() else null


## 這個部件在這個動作、這一幀算不算「在場」(還要再看種類:眨眼/說話只在眨眼/說話時才真的顯示)。
static func _shown_on(part: Dictionary, action: String, frame: int, plain := "") -> bool:
	var rule: Variant = _frame_rule(part, action, frame, plain)
	if rule is bool:
		return rule and (str(part["role"]) == "part" or _matches(part, action, plain))
	return _matches(part, action, plain)


## 這個部件現在要不要畫(種類的時機另外看):被積木/狀態鏡暫時顯示的一定畫(這一幀設成不顯示的除外);
## 平常不顯示的(dormant)只在逐幀設成「顯示」的幀畫(2026-10-16 使用者回報:種類設成「待呼叫」、只在 sleep 那一幀勾顯示,
## 睡覺時卻沒出現——明確勾了「在此幀顯示」就該出現);其餘照動作、逐幀規則與右鍵選單的開關。
func _part_active(part: Dictionary, action: String, frame: int, plain: String) -> bool:
	if _is_forced(part):
		return _frame_rule(part, action, frame, plain) != false
	if bool(part["dormant"]) and _frame_rule(part, action, frame, plain) != true:
		return false
	if str(part["used_by"]) != "always" and _pet.has_method("overlay_allows") and not bool(_pet.overlay_allows(part)):
		return false
	return _shown_on(part, action, frame, plain) and not _disabled.has(str(part["name"]))


func _is_forced(part: Dictionary) -> bool:
	return _pet.has_method("is_layer_forced") and bool(_pet.is_layer_forced(str(part["name"])))


## 目前這個動作、說話狀態下每個部件是否顯示(測試與除錯用):{部件名: 是否顯示}。
func visibility_map() -> Dictionary:
	var result := {}
	for part: Dictionary in _parts:
		result[part["name"]] = (part["node"] as Node2D).visible
	return result


## 目前每個部件正在播哪一段動畫(測試與除錯用):{部件名: 動畫名};沒顯示的部件是空字串。
func clip_map() -> Dictionary:
	var result := {}
	for part: Dictionary in _parts:
		result[part["name"]] = str(part["clip_name"])
	return result


func _process(delta: float) -> void:
	if _parts.is_empty() or _pet == null or not is_instance_valid(_pet):
		return
	_clock += delta
	var action := String(_pet.current_animation_action())
	var plain := _plain_of(action)
	var mirrored := _pet.has_method("directional_mirrored") and bool(_pet.directional_mirrored())
	var speaking: bool = _pet.is_speaking_now()
	var body_frame: int = _pet.body_frame()
	# 眨眼計時:說話中不眨;只有目前動作真的有眨眼部件時才開始眨。
	if _blink_left > 0.0:
		_blink_left -= delta
	else:
		_blink_next -= delta
		if _blink_next <= 0.0:
			_blink_next = randf_range(BLINK_INTERVAL.x, BLINK_INTERVAL.y)
			if not speaking:
				_blink_duration = _start_blink(action, plain)
				_blink_left = _blink_duration
	for part: Dictionary in _parts:
		var node: Sprite2D = part["node"]
		var visible_now := false
		var texture: Texture2D = null
		if _part_active(part, action, body_frame, plain):
			# 被暫時顯示的圖層不管種類都當一般配件畫(眨眼、說話差分也一直顯示到時間到)。
			match "part" if _is_forced(part) else str(part["role"]):
				"part":
					visible_now = true
					texture = _clip_texture(part, action, plain)
				"speak":
					visible_now = speaking
					if visible_now:
						texture = _clip_texture(part, action, plain)
				"blink":
					visible_now = _blink_left > 0.0 and not speaking
					if visible_now:
						var frames: Array = part["clips"][part["base_clip"]]["textures"]
						var progress := clampf(1.0 - _blink_left / maxf(_blink_duration, 0.001), 0.0, 0.999)
						texture = frames[int(progress * frames.size())]
		if node.visible != visible_now:
			node.visible = visible_now
		if not visible_now or texture == null:
			# 沒顯示:下次再出現時,不循環的動畫要從頭播。
			part["clip_name"] = ""
			continue
		if node.texture != texture:
			node.texture = texture
			node.offset = texture_offset(part["origin"], texture)
		var flip := mirrored and _uses_plain_anchor(part, action, plain)
		node.scale.x = float(part["scale"]) * (-1.0 if _image_mirrored(part, action, flip) else 1.0)
		node.position = _anchor_position(part, action, body_frame, plain, flip)


## 這個部件的圖現在要不要左右鏡像(以錨點為中心):沿用原動作位置時跟著整隻鏡像;
## mirror_for 列到的動作(精靈圖編輯器「複製預設版本並左右翻轉」建立的朝向版本)再翻一次。
static func _image_mirrored(part: Dictionary, action: String, flip: bool) -> bool:
	return flip != (part["mirror_for"] as Array).has(action)


## 動作名稱去掉朝向後綴(walk_left → walk)。
static func _plain_of(action: String) -> String:
	return SpritePackLoader.plain_action(action)


## 目前動作要播哪一段動畫的目前這一幀。換了動畫(或重新顯示)就從頭計時。
func _clip_texture(part: Dictionary, action: String, plain := "") -> Texture2D:
	var by_action: Dictionary = part["clip_for"]
	var clip_name: String = by_action.get(action, by_action.get(plain, by_action.get("*", part["base_clip"])))
	if not (part["clips"] as Dictionary).has(clip_name):
		clip_name = part["base_clip"]
	if str(part["clip_name"]) != clip_name:
		part["clip_name"] = clip_name
		part["clip_start"] = _clock
	var clip: Dictionary = part["clips"][clip_name]
	var frames: Array = clip["textures"]
	if frames.size() <= 1:
		return frames[0]
	var index := int((_clock - float(part["clip_start"])) * float(clip["fps"]))
	index = index % frames.size() if bool(clip["loop"]) else mini(index, frames.size() - 1)
	return frames[index]


## 目前動作有眨眼部件就回傳這次眨眼的長度(取符合部件中最長的 duration),沒有就 0。
func _start_blink(action: String, plain := "") -> float:
	var longest := 0.0
	for part: Dictionary in _parts:
		if str(part["role"]) == "blink" and not bool(part["dormant"]) and _matches(part, action, plain):
			longest = maxf(longest, float(part["duration"]))
	return longest


static func _matches(part: Dictionary, action: String, plain := "") -> bool:
	var actions: Array = part["actions"]
	return actions.has("*") or actions.has(action) or (plain != "" and actions.has(plain))


## 播朝向專用動畫時,這個部件沒有為它另外設定位置(要沿用原動作的位置)。
static func _uses_plain_anchor(part: Dictionary, action: String, plain: String) -> bool:
	return plain != action and not (part["frame_anchors"] as Dictionary).has(action) and not (part["anchors"] as Dictionary).has(action)


## 錨點優先順序:這個動作的逐幀錨點 > 這個動作的錨點 > 預設錨點。朝向專用動畫(walk_left)沒有自己的設定時用原動作(walk)的。
func _anchor_for(part: Dictionary, action: String, frame: int, plain := "") -> Vector2:
	var by_frame: Dictionary = part["frame_anchors"]
	var by_action: Dictionary = part["anchors"]
	for key: String in ([action, plain] if plain != "" and plain != action else [action]):
		if by_frame.has(key):
			var points: Array = by_frame[key]
			return points[frame % points.size()]
		if by_action.has(key):
			return by_action[key]
	return part["anchor"]


## 錨點換算成部件在控制節點座標裡的位置:image 空間要扣掉畫布一半並加上本體精靈的位置;pivot 空間就是相對腳底軸心的偏移。
## flip = 播朝向專用動畫、沿用原動作的位置:原動作平常是整隻鏡像畫的,這裡不鏡像,所以把位置左右翻過來。
func _anchor_position(part: Dictionary, action: String, frame: int, plain := "", flip := false) -> Vector2:
	var anchor: Vector2 = _anchor_for(part, action, frame, plain) + (_offsets.get(str(part["name"]), Vector2.ZERO) as Vector2)
	var position := anchor if _pivot_space else _sprite_position + (anchor - _base_size * 0.5)
	if flip:
		position.x = -position.x
	return position


## 目前動作所有符合的部件(不管此刻有沒有顯示)佔的範圍,桌寵本地座標。穿透形狀要把它算進去,否則突出本體的帽子、翅膀會被視窗區域裁掉;
## 眨眼/說話這類會突然出現的部件、換動畫時圖大小不同的部件,都用它所有圖(裁切後)合起來的範圍算,免得出現的那一瞬間慢一影格被裁。
func union_rect() -> Rect2:
	if _parts.is_empty() or _pet == null or not is_instance_valid(_pet):
		return Rect2()
	var action := String(_pet.current_animation_action())
	var plain := _plain_of(action)
	var mirrored := _pet.has_method("directional_mirrored") and bool(_pet.directional_mirrored())
	var frame: int = _pet.body_frame()
	var to_pet: Transform2D = _pet.get_global_transform().affine_inverse() * get_global_transform()
	var result := Rect2()
	var first := true
	for part: Dictionary in _parts:
		if not _part_active(part, action, frame, plain):
			continue
		var flip := mirrored and _uses_plain_anchor(part, action, plain)
		var bounds: Rect2 = part["bounds"]
		var scaled := Rect2(bounds.position * float(part["scale"]), bounds.size * float(part["scale"]))
		if _image_mirrored(part, action, flip):
			scaled.position.x = -scaled.end.x
		var rect: Rect2 = to_pet * Rect2(_anchor_position(part, action, frame, plain, flip) + scaled.position, scaled.size)
		result = rect if first else result.merge(rect)
		first = false
	return result
