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
## 部件的 scale(預設 1)是整體縮放倍數,借用別的角色的圖當替身配件時很方便(像素圖用 nearest 放大成整數倍再存檔最清楚)。
## 配件動畫(clips):一個部件可以有多段動畫,再指定「哪個動作播哪一段」,例如拿著茶杯的角色平常播冒煙(steam),
## 換到某個表情動作就播喝茶(sip):
##   "clips": {"steam": {"images": [...], "fps": 5}, "sip": {"images": [...], "fps": 6, "loop": false}},
##   "clip_for": {"pose_03": "sip", "*": "steam"}
## 部件本身的 images / fps / loop 是「預設動畫」(名字 default);沒有 clip_for 對到的動作就播預設動畫(沒有預設就播 clip_for["*"] 或第一段)。
## loop = false 的動畫每次(重新)顯示時從頭播一次,停在最後一幀。
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
	for raw: Variant in raw_parts:
		if _parts.size() >= MAX_PARTS:
			report.append(tr("部件超過 %d 個的上限,多的已略過。") % MAX_PARTS)
			break
		var part := _build_part(raw, base_dir, report)
		if not part.is_empty():
			_parts.append(part)
	return report


## 一段動畫 = {textures, fps, loop}。raw 是有 images / image / fps / loop 的物件(部件本身或 clips 裡的一項);圖都讀不出來回空字典。
func _build_clip(raw: Dictionary, base_dir: String, report: Array[String]) -> Dictionary:
	var image_files: Array = []
	if raw.get("images") is Array:
		image_files = raw["images"]
	elif raw.get("image") is String:
		image_files = [raw["image"]]
	var textures: Array[Texture2D] = []
	for file_name: Variant in image_files.slice(0, MAX_FRAMES):
		var texture := _load_texture(base_dir, str(file_name), report)
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
	if raw.get("visible") is bool and not bool(raw["visible"]):
		return {}   # 精靈圖編輯器「圖層」裡取消「遊戲中顯示」的部件:暫時停用,不建立、不回報
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
	if not anchor is Vector2 and anchors_by_action.is_empty() and frame_anchors.is_empty():
		report.append(tr("部件「%s」沒有 anchor(錨點座標),已略過。") % part_name)
		return {}
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
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var part_scale := 1.0
	if raw.get("scale") is float or raw.get("scale") is int:
		part_scale = clampf(float(raw["scale"]), 0.05, 8.0)
	node.scale = Vector2.ONE * part_scale
	var first_texture: Texture2D = clips[base_clip]["textures"][0]
	node.texture = first_texture
	node.offset = -_origin_pixels(raw.get("origin", "center"), Vector2(first_texture.get_size()))
	node.visible = false
	add_child(node)
	var largest := Vector2.ZERO
	for clip: Dictionary in clips.values():
		for texture: Texture2D in clip["textures"]:
			largest = largest.max(Vector2(texture.get_size()))
	return {
		"name": part_name,
		"role": ROLES[role_text],
		"node": node,
		"clips": clips,
		"clip_for": clip_for,
		"base_clip": base_clip,
		"origin": raw.get("origin", "center"),
		"scale": part_scale,
		"largest": largest,
		"actions": actions,
		"anchor": anchor if anchor is Vector2 else Vector2.ZERO,
		"anchors": anchors_by_action,
		"frame_anchors": frame_anchors,
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


static func _load_texture(base_dir: String, file_name: String, report: Array[String]) -> Texture2D:
	if file_name == "" or file_name.contains("..") or file_name.is_absolute_path() or file_name.begins_with("/") or file_name.begins_with("\\"):
		report.append(TranslationServer.translate("圖片路徑「%s」不合法(只能是資料夾內的相對路徑),已略過。") % file_name)
		return null
	if not IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
		report.append(TranslationServer.translate("圖片「%s」不是 png / webp / jpg,已略過。") % file_name)
		return null
	var path := base_dir.path_join(file_name)
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
	return ImageTexture.create_from_image(image)


func part_count() -> int:
	return _parts.size()


## 可以開關的配件名稱(role = part 的部件,依素材包裡的順序,同名只列一次)。
func accessory_names() -> Array[String]:
	var names: Array[String] = []
	for part: Dictionary in _parts:
		if str(part["role"]) == "part" and not names.has(str(part["name"])):
			names.append(str(part["name"]))
	return names


func set_disabled(names: Array) -> void:
	_disabled.clear()
	for entry: Variant in names:
		_disabled.append(str(entry))


func is_accessory_enabled(part_name: String) -> bool:
	return not _disabled.has(part_name)


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
				_blink_duration = _start_blink(action)
				_blink_left = _blink_duration
	for part: Dictionary in _parts:
		var node: Sprite2D = part["node"]
		var visible_now := false
		var texture: Texture2D = null
		if _matches(part, action):
			match str(part["role"]):
				"part":
					visible_now = not _disabled.has(str(part["name"]))
					texture = _clip_texture(part, action)
				"speak":
					visible_now = speaking
					if visible_now:
						texture = _clip_texture(part, action)
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
			node.offset = -_origin_pixels(part["origin"], Vector2(texture.get_size()))
		node.position = _anchor_position(part, action, body_frame)


## 目前動作要播哪一段動畫的目前這一幀。換了動畫(或重新顯示)就從頭計時。
func _clip_texture(part: Dictionary, action: String) -> Texture2D:
	var by_action: Dictionary = part["clip_for"]
	var clip_name: String = by_action.get(action, by_action.get("*", part["base_clip"]))
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
func _start_blink(action: String) -> float:
	var longest := 0.0
	for part: Dictionary in _parts:
		if str(part["role"]) == "blink" and _matches(part, action):
			longest = maxf(longest, float(part["duration"]))
	return longest


static func _matches(part: Dictionary, action: String) -> bool:
	var actions: Array = part["actions"]
	return actions.has("*") or actions.has(action)


## 錨點優先順序:這個動作的逐幀錨點 > 這個動作的錨點 > 預設錨點。
func _anchor_for(part: Dictionary, action: String, frame: int) -> Vector2:
	var by_frame: Dictionary = part["frame_anchors"]
	if by_frame.has(action):
		var points: Array = by_frame[action]
		return points[frame % points.size()]
	var by_action: Dictionary = part["anchors"]
	return by_action[action] if by_action.has(action) else part["anchor"]


## 錨點換算成部件在控制節點座標裡的位置:image 空間要扣掉畫布一半並加上本體精靈的位置;pivot 空間就是相對腳底軸心的偏移。
func _anchor_position(part: Dictionary, action: String, frame: int) -> Vector2:
	var anchor := _anchor_for(part, action, frame)
	return anchor if _pivot_space else _sprite_position + (anchor - _base_size * 0.5)


## 目前動作所有符合的部件(不管此刻有沒有顯示)佔的範圍,桌寵本地座標。穿透形狀要把它算進去,否則突出本體的帽子、翅膀會被視窗區域裁掉;
## 眨眼/說話這類會突然出現的部件、換動畫時圖大小不同的部件,都用它所有圖裡最大的尺寸算,免得出現的那一瞬間慢一影格被裁。
func union_rect() -> Rect2:
	if _parts.is_empty() or _pet == null or not is_instance_valid(_pet):
		return Rect2()
	var action := String(_pet.current_animation_action())
	var frame: int = _pet.body_frame()
	var to_pet: Transform2D = _pet.get_global_transform().affine_inverse() * get_global_transform()
	var result := Rect2()
	var first := true
	for part: Dictionary in _parts:
		if not _matches(part, action) or (str(part["role"]) == "part" and _disabled.has(str(part["name"]))):
			continue
		var size: Vector2 = part["largest"] * float(part["scale"])
		var rect: Rect2 = to_pet * Rect2(_anchor_position(part, action, frame) - _origin_pixels(part["origin"], size), size)
		result = rect if first else result.merge(rect)
		first = false
	return result
