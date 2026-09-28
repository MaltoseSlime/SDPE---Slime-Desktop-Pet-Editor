class_name SpritePackLoader
extends RefCounted
## 素材包載入器:把一個「已經裁切好的 sprite 資料夾」讀成 SpriteFrames,不需要每種素材各寫一個轉接層。
## 格式說明(給創作者)見 docs/素材包格式.md;這裡是實作。
##
## 認得的資料夾長相(自動偵測,不用設定):
##   A. 表情/差分資料夾  <臉>/<階段>/<動作>_<幀>.png     例:default/0/stand1_0.png、blink/1/stand1_0.png
##      default(沒有就取第一個資料夾)的階段 0 = 本體;blink 的各階段 = 眨眼(閉眼過程),依階段編號依序播放,
##      而且是「對應本體那一幀」的眨眼(本體動作播到第 k 幀時眨眼,就用 blink 各階段的第 k 幀圖),身體不會在眨眼時跳格。
##   B. 平放         <動作>_<幀>.png、<動作><兩位以上數字>.png(idle00)、<動作>_l/r_<幀>.png(只取朝右 r)
##   C. 動作資料夾   <動作>/<幀>.png(0.png、1.png…)
## 選用的 pack.json(放在素材包資料夾根目錄)可以覆蓋:名稱/辨識代號/縮放/面向/FPS/動作對應/眨眼資料夾名。沒有它就全用自動偵測。
##
## 對應規則:系統動作(idle、walk、run、rise、fall、sit、lay、sleep、drag、interact、dance、climb_wall、climb_ceiling…)
## 由 pack.json 的 "actions" 指定,沒指定的用 ALIASES 別名表自動找;素材包裡沒被系統動作用到的動作,
## 原名保留當自訂動作(積木的動作下拉選單會列出)。所有幀以「腳底置中」對齊成同一個畫布大小。
## 安全:只讀 PNG/JPG/WEBP、檔案數與尺寸有上限、pack.json 逐欄驗證型別,壞掉的欄位/檔案略過並記在 report,不往外拋錯。

const MAX_FILES := 1500
const MAX_FILE_BYTES := 8_000_000
const MAX_SIDE := 4096
const MAX_TOTAL_PIXELS := 60_000_000
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
## 圖片偏移(pack.json 的 offsets)每軸的上限(像素),避免畫布被撐到離譜大小。
const MAX_OFFSET := 512.0
const DEFAULT_FPS := 8.0
const DEFAULT_BLINK_FPS := 14.0
## 沒指定縮放時,讓待機動作大約這麼高(像素)。
const DEFAULT_TARGET_HEIGHT := 110.0
## 系統動作 → 素材包裡可能的動作名稱(依序找,大小寫不分)。
const ALIASES := {
	"idle": ["idle", "stand", "stand1", "wait", "breath"],
	"walk": ["walk", "walk1", "move"],
	"run": ["run", "dash", "walk", "walk1"],
	"rise": ["rise", "jump", "jumpstart"],
	"fall": ["fall", "jump", "land"],
	"fly": ["fly", "flying", "hover"],
	"sit": ["sit", "sit1", "squat"],
	"lay": ["lay", "prone", "lie"],
	"sleep": ["sleep"],
	"drag": ["drag", "held", "hang"],
	"interact": ["interact", "pet", "poke"],
	"dance": ["dance", "jumpstart"],
	"enter": ["enter"],
	"leave": ["leave"],
	"gather": ["gather"],
	"climb_wall": ["climb_wall", "climb", "ladder"],
	"climb_ceiling": ["climb_ceiling", "ceiling"],
}
## 這些動作預設只播一次(不循環)。
const ONE_SHOT: Array[String] = ["enter", "leave"]

static var _RE_UNDERSCORE := RegEx.create_from_string("^(.+)_(\\d+)$")
static var _RE_TRAILING := RegEx.create_from_string("^(.*[^\\d])(\\d{2,})$")
static var _RE_ONLY_NUMBER := RegEx.create_from_string("^\\d+$")


## 載入素材包。回傳 {ok, frames(SpriteFrames), meta{tag,name,scale,art_flipped,smooth,path}, report[String]};失敗時 ok=false、report 說明原因。
static func load_pack(folder: String) -> Dictionary:
	var report: Array[String] = []
	var root := folder.strip_edges().trim_suffix("/").trim_suffix("\\")
	if root == "" or DirAccess.open(root) == null:
		return _fail(TranslationServer.translate("找不到資料夾:%s") % folder)
	_sheet_cache.clear()
	var manifest := _read_manifest(root, report)
	var layout := _scan(root, manifest, report)
	if layout.is_empty() or (layout["actions"] as Dictionary).is_empty():
		return _fail("資料夾裡找不到可用的圖片(需要 <動作>_<幀>.png 之類的檔名,見 docs/素材包格式.md)")
	var actions: Dictionary = layout["actions"]
	var overlays: Dictionary = layout["overlays"]
	# 1. 決定要建哪些動畫:animation 名稱 → {source(素材包動作名), frames(來源幀索引陣列)}
	var plan := _plan_animations(actions, manifest, report)
	# 2. 讀圖(每張只讀一次):取得貼圖與尺寸;要用名字標籤對齊時再多分析標籤位置
	var nametag_align := str(manifest.get("nametag", "off")).to_lower() == "align"
	var infos: Dictionary = {}
	var total_pixels := [0]
	var base_paths: Dictionary = {}
	for animation_name: String in plan:
		var entry: Dictionary = plan[animation_name]
		for index: int in entry["frames"]:
			base_paths[(actions[entry["source"]] as Array)[index]] = true
	for path: String in base_paths:
		var info := _load_info(path, total_pixels, report, nametag_align)
		if not info.is_empty():
			infos[path] = info
	if infos.is_empty():
		return _fail("圖片都讀不出來(檔案損毀或超過大小上限)")
	var blink_stages: Array = overlays.get("blink", [])
	var speak_stages: Array = overlays.get("speak", [])
	var blink_infos: Dictionary = {}
	for stage: Dictionary in blink_stages + speak_stages:
		for source_name: String in stage:
			if not _plan_uses_source(plan, source_name):
				continue
			for path: String in stage[source_name]:
				if not blink_infos.has(path) and not infos.has(path):
					var info := _load_info(path, total_pixels, report, false)
					if not info.is_empty():
						blink_infos[path] = info
	# 3. 每一幀的軸心(腳底中心點)與畫布:
	#    軸心 = 這一幀圖上「站在地面的那一點」(像素座標,從圖的左上角算),優先順序:
	#    pack.json 的 pivots(單幀檔名 > 整個動作名)> 名字標籤對齊(nametag: align)> foot_from_bottom / pivot_x_offset > 圖的底邊中心。
	#    所有幀以軸心對齊、補成同一個畫布(AtlasTexture 的 margin,不複製像素);軸心以下的內容可以裁掉(crop_below_foot)。
	var crop := bool(manifest.get("crop_below_foot", nametag_align))
	# 專屬天花板動作(climb_ceiling)的來源:畫的是倒掛的樣子,軸心預設在圖的上緣中心(抓著天花板的點),不套用名字標籤對齊、不裁切。
	var ceiling_sources: Dictionary = {}
	for animation_name: String in plan:
		if animation_name.begins_with("climb_ceiling_"):
			ceiling_sources[plan[animation_name]["source"]] = true
	var pivots: Dictionary = {}
	# 圖片偏移(pack.json 的 offsets):圖片相對軸心平移,軸心本身(腳底線、裁切線、坐下判定、配件錨點)不動;
	# 圖片實際貼的位置 = 軸心 − 偏移(圖往右移 dx,就等於軸心在圖裡往左移 dx)。
	var offsets: Dictionary = {}
	var half_width := 0.0
	var up_max := 0.0
	var down_max := 0.0
	for animation_name: String in plan:
		var entry: Dictionary = plan[animation_name]
		for index: int in entry["frames"]:
			var path: String = (actions[entry["source"]] as Array)[index]
			if not infos.has(path) or pivots.has(path):
				continue
			var info: Dictionary = infos[path]
			var is_ceiling := ceiling_sources.has(entry["source"])
			var pivot := _pivot_for(path, str(entry["source"]), info, manifest, nametag_align and not is_ceiling, is_ceiling)
			var offset := _offset_for(path, str(entry["source"]), manifest)
			pivots[path] = pivot
			offsets[path] = offset
			var place := pivot - offset
			var size: Vector2i = info["size"]
			var used_height := clampi(int(pivot.y), 1, size.y) if crop and not is_ceiling else size.y
			half_width = maxf(half_width, maxf(place.x, float(size.x) - place.x))
			up_max = maxf(up_max, place.y)
			down_max = maxf(down_max, float(used_height) - place.y)
	var cell := Vector2i(int(ceil(half_width)) * 2, int(ceil(up_max + down_max)))
	if cell.x <= 0 or cell.y <= 0:
		return _fail("算不出畫布大小(軸心設定有問題?)")
	# 4. 組 SpriteFrames
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var fps := _number(manifest.get("fps"), DEFAULT_FPS)
	var fps_by_action: Dictionary = manifest.get("fps_by_action", {}) if manifest.get("fps_by_action") is Dictionary else {}
	var one_shot: Array = manifest.get("one_shot", ONE_SHOT) if manifest.get("one_shot") is Array else ONE_SHOT
	var blink_fps := _number(manifest.get("blink_fps"), DEFAULT_BLINK_FPS)
	var loop_table := PackLoop.clean(manifest.get("loop_by_action"))
	var loop_starts := {}
	var all_infos := infos.duplicate()
	all_infos.merge(blink_infos)
	for animation_name: String in plan:
		var entry: Dictionary = plan[animation_name]
		var source_paths: Array = actions[entry["source"]]
		var animation := StringName(animation_name)
		var base_name := animation_name.substr(0, animation_name.rfind("_"))
		var loop_entry: Dictionary = loop_table.get(base_name, {})
		# repeat 模式(整段重複播 N 次再停):引擎的 SpriteFrames 只有「一直循環」或「播一次」兩種,沒有「播 N 次」,
		# 所以直接把幀序重複串接成一段不循環的長動畫,播完 N 輪自然停在最後一幀(見 PackLoop 檔頭說明)。
		var is_repeat := str(loop_entry.get("mode", "")) == "repeat"
		var frame_list: Array
		var loop_flag: Variant
		if is_repeat:
			frame_list = PackLoop.repeat_frames(entry["frames"] as Array, int(loop_entry.get("times", 0)))
			loop_flag = false
		else:
			var span := PackLoop.frame_range((entry["frames"] as Array).size(), loop_entry)
			frame_list = (entry["frames"] as Array).slice(0, int(span["kept"]))
			loop_flag = span["loop"]
			if int(span["start"]) > 0:
				loop_starts[animation_name] = int(span["start"])
				loop_starts[animation_name + "_sp"] = int(span["start"])
		frames.add_animation(animation)
		frames.set_animation_speed(animation, _number(fps_by_action.get(base_name), fps))
		frames.set_animation_loop(animation, bool(loop_flag) if loop_flag != null else not one_shot.has(base_name))
		var added := 0
		for index: int in frame_list:
			var path: String = source_paths[index]
			if infos.has(path):
				frames.add_frame(animation, _frame_texture(infos[path], pivots[path], offsets[path], cell, up_max, crop and not ceiling_sources.has(entry["source"])))
				added += 1
		if added == 0:
			frames.remove_animation(animation)
			continue
		# 眨眼:對應「本體第 k 幀」的眨眼動畫 <動畫>_bl_f<k>,各階段圖用同一個動作同一幀、同一個軸心
		var frame_position := 0
		for index: int in frame_list:
			var body_path: String = source_paths[index]
			if not infos.has(body_path):
				continue
			var blink_animation := StringName("%s_bl_f%d" % [animation_name, frame_position])
			var stage_count := 0
			for stage: Dictionary in blink_stages:
				var stage_paths: Array = stage.get(entry["source"], [])
				if index >= stage_paths.size() or not all_infos.has(stage_paths[index]):
					continue
				if stage_count == 0:
					frames.add_animation(blink_animation)
					frames.set_animation_speed(blink_animation, blink_fps)
					frames.set_animation_loop(blink_animation, false)
				frames.add_frame(blink_animation, _frame_texture(all_infos[stage_paths[index]], pivots[body_path], offsets[body_path], cell, up_max, crop and not ceiling_sources.has(entry["source"])))
				stage_count += 1
			frame_position += 1
		# 說話差分 <動畫>_sp:身體照原本的幀序播,嘴型依「來回」順序(0,1,2,1,0…)逐幀換成說話資料夾的圖(沒有對應圖的幀用本體圖);
		# 說話期間(打字機滾動)Pet 會切到這個動畫,結束再切回本體。
		if not speak_stages.is_empty():
			var speak_animation := StringName("%s_sp" % animation_name)
			var speak_added := 0
			for position_index in frame_list.size():
				var body_index: int = frame_list[position_index]
				var body_path: String = source_paths[body_index]
				if not infos.has(body_path):
					continue
				var mouth_stage: int = _ping_pong(position_index, speak_stages.size())
				var stage_paths: Array = (speak_stages[mouth_stage] as Dictionary).get(entry["source"], [])
				var mouth_info: Dictionary = all_infos.get(stage_paths[body_index], {}) if body_index < stage_paths.size() else {}
				if mouth_info.is_empty():
					mouth_info = infos[body_path]
				if speak_added == 0:
					frames.add_animation(speak_animation)
					frames.set_animation_speed(speak_animation, frames.get_animation_speed(animation))
					frames.set_animation_loop(speak_animation, true)
				frames.add_frame(speak_animation, _frame_texture(mouth_info, pivots[body_path], offsets[body_path], cell, up_max, crop and not ceiling_sources.has(entry["source"])))
				speak_added += 1
	if not frames.has_animation(&"idle_0"):
		# 沒有待機動作:拿第一個動作的第一幀湊一個(至少不會整隻消失),並提醒創作者
		var first: String = plan.keys()[0]
		frames.add_animation(&"idle_0")
		frames.set_animation_loop(&"idle_0", true)
		frames.add_frame(&"idle_0", frames.get_frame_texture(StringName(first), 0))
		report.append(TranslationServer.translate("素材包沒有待機(idle/stand)動作,先拿「%s」的第一幀當待機;可在 pack.json 的 actions 指定 idle。") % first)
	frames.set_meta("loop_starts", loop_starts)   # 動畫名稱 → 循環時接回來的幀(見 PackLoop;桌寵在動畫循環一圈時把幀設回這裡)
	# 軸心以下多出來的畫布高度(沒裁掉的名字標籤、影子…):Pet 放置圖片時要把它算進去,軸心才會剛好踩在腳底的位置。
	frames.set_meta("ground_below", down_max)
	var idle_path: String = ""
	var idle_entry: Dictionary = plan.get("idle_0", plan[plan.keys()[0]])
	idle_path = (actions[idle_entry["source"]] as Array)[idle_entry["frames"][0]]
	var idle_info: Dictionary = infos.get(idle_path, infos[infos.keys()[0]])
	var idle_pivot: Vector2 = pivots.get(idle_path, Vector2(float(idle_info["size"].x) * 0.5, float(idle_info["size"].y)))
	var body_size := Vector2(float(idle_info["size"].x), minf(idle_pivot.y, float(idle_info["size"].y)))
	frames.set_meta("body_size", body_size)
	# pack.json 的互動判定框(縮放前像素、錨點在腳底線中心):"hitbox": [寬, 高]、"hitbox_offset": [x, y]
	var hitbox_value: Variant = manifest.get("hitbox")
	if hitbox_value is Array and hitbox_value.size() >= 2 and _number(hitbox_value[0], 0.0) > 0.0 and _number(hitbox_value[1], 0.0) > 0.0:
		frames.set_meta("hitbox_size", Vector2(_number(hitbox_value[0], 0.0), _number(hitbox_value[1], 0.0)))
	# 光源(發光效果):pack.json 的 "lights",見 PackLights。
	frames.set_meta("lights", PackLights.clean(manifest.get("lights")))
	frames.set_meta("hold_anchor", PackLights.anchor_of(manifest.get("hold_anchor")))
	var hitbox_offset_value: Variant = manifest.get("hitbox_offset")
	if hitbox_offset_value is Array and hitbox_offset_value.size() >= 2 and (hitbox_offset_value[0] is float or hitbox_offset_value[0] is int) and (hitbox_offset_value[1] is float or hitbox_offset_value[1] is int):
		frames.set_meta("hitbox_offset", Vector2(float(hitbox_offset_value[0]), float(hitbox_offset_value[1])))
	var hint := _nametag_hint(idle_path, nametag_align)
	if hint != "":
		report.append(hint)
	# 一般桌寵的浮動差分與配件:素材包資料夾裡的 overlays.json(座標空間預設 pivot = 相對腳底軸心,見 PetOverlays)。
	var overlay_spec := _read_json_file(root.path_join("overlays.json"))
	if not overlay_spec.is_empty():
		overlay_spec["space"] = str(overlay_spec.get("space", "pivot"))
	var height := body_size.y
	var tag := _clean_tag(str(manifest.get("tag", "")), root.get_file())
	var meta := {
		"tag": tag,
		"name": str(manifest.get("name", root.get_file())).strip_edges().left(40),
		"scale": clampf(_number(manifest.get("scale"), DEFAULT_TARGET_HEIGHT / maxf(height, 1.0)), 0.1, 6.0),
		"art_flipped": str(manifest.get("facing", "right")).to_lower() == "left",
		"smooth": str(manifest.get("filter", "nearest" if height <= 200.0 else "linear")).to_lower() == "linear",
		"path": root,
		"cell": cell,
		"overlays": overlay_spec,
		"kind": "still" if str(manifest.get("kind", "active")).to_lower() == "still" else "active",
	}
	_sheet_cache.clear()
	report.insert(0, TranslationServer.translate("讀到 %d 個動作(系統動作 + 自訂動作)、畫布 %d×%d、眨眼 %s。") % [_count_actions(frames), cell.x, cell.y, "有(逐幀對應)" if not blink_stages.is_empty() else "沒有"])
	return {"ok": true, "frames": frames, "meta": meta, "report": report}


## 0,1,2,…,n-1,n-2,…,1,0,1… 的來回序列(n=1 恆為 0)。
static func _ping_pong(index: int, count: int) -> int:
	if count <= 1:
		return 0
	var cycle := (count - 1) * 2
	var i := index % cycle
	return i if i < count else cycle - i


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "frames": null, "meta": {}, "report": [message]}


static func _count_actions(frames: SpriteFrames) -> int:
	var names := {}
	for animation in frames.get_animation_names():
		var text := String(animation)
		if "_bl" in text or text.ends_with("_sp"):
			continue
		names[text.substr(0, text.rfind("_"))] = true
	return names.size()


static func _number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var number := float(value)
		if not is_nan(number) and not is_inf(number) and number > 0.0:
			return number
	return fallback


static func _clean_tag(tag: String, fallback: String) -> String:
	var cleaned := (tag if tag.strip_edges() != "" else fallback).strip_edges().validate_filename().left(40)
	return cleaned if cleaned != "" else "pack"


static func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 200_000:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _read_manifest(root: String, report: Array[String]) -> Dictionary:
	var path := root.path_join("pack.json")
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 200_000:
		report.append("pack.json 讀不了或太大,已忽略,改用自動偵測。")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		report.append("pack.json 不是有效的 JSON 物件,已忽略,改用自動偵測。")
		return {}
	return parsed


## 一個「臉」資料夾(眨眼、說話)的各階段:回傳 [階段0的{動作名 → [路徑…]}, 階段1…]。
static func _scan_overlay(root: String, face: String, stage_names: Array, counter: Array, report: Array[String]) -> Array:
	var stages: Array = []
	for stage_name: String in stage_names:
		var stage_actions: Dictionary = {}
		var stage_path := root.path_join(face).path_join(stage_name)
		_group_flat(stage_path, _list_images(stage_path), stage_actions, counter, report)
		stages.append(stage_actions)
	return stages


## 掃資料夾,回傳 {actions: {動作名 → [圖片路徑…(依幀序)]}, overlays: {"blink": [階段0的{動作名 → [路徑]}, 階段1…]}}。
static func _scan(root: String, manifest: Dictionary, report: Array[String]) -> Dictionary:
	var counter := [0]
	var root_images := _list_images(root)
	var subdirs := _list_dirs(root)
	var actions: Dictionary = {}
	var overlays: Dictionary = {}
	if not root_images.is_empty():
		_group_flat(root, root_images, actions, counter, report)
	# 子資料夾:先判斷是「臉/階段」(裡面還有數字資料夾)還是「動作資料夾」(裡面直接是圖片)
	var face_dirs: Dictionary = {}
	for sub: String in subdirs:
		var sub_path := root.path_join(sub)
		var stage_dirs: Array[String] = []
		for inner in _list_dirs(sub_path):
			if _RE_ONLY_NUMBER.search(inner) != null:
				stage_dirs.append(inner)
		if not stage_dirs.is_empty():
			stage_dirs.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
			face_dirs[sub] = stage_dirs
		else:
			var images := _list_images(sub_path)
			if not images.is_empty():
				_group_action_folder(sub, sub_path, images, actions, counter, report)
	if not face_dirs.is_empty():
		var base_face := "default" if face_dirs.has("default") else str(face_dirs.keys()[0])
		if base_face != "default":
			report.append(TranslationServer.translate("沒有 default 資料夾,拿「%s」當本體。") % base_face)
		for stage_name: String in [face_dirs[base_face][0]]:
			_group_flat(root.path_join(base_face).path_join(stage_name), _list_images(root.path_join(base_face).path_join(stage_name)), actions, counter, report)
		var blink_face := str(manifest.get("blink", "blink"))
		if face_dirs.has(blink_face) and blink_face != base_face:
			overlays["blink"] = _scan_overlay(root, blink_face, face_dirs[blink_face], counter, report)
		# 說話差分:嘴型資料夾(pack.json 的 "speak" 指定名稱,沒指定就找 speak / talk / sp / mouth),階段 = 不同嘴型
		var speak_face := str(manifest.get("speak", ""))
		if speak_face == "":
			for candidate: String in ["speak", "talk", "sp", "mouth"]:
				if face_dirs.has(candidate) and candidate != base_face and candidate != blink_face:
					speak_face = candidate
					break
		if speak_face != "" and face_dirs.has(speak_face) and speak_face != base_face and speak_face != blink_face:
			overlays["speak"] = _scan_overlay(root, speak_face, face_dirs[speak_face], counter, report)
		else:
			speak_face = ""
		for face: String in face_dirs:
			if face != base_face and face != blink_face and face != speak_face:
				report.append(TranslationServer.translate("資料夾「%s」不是 default 也不是眨眼資料夾(%s),目前沒有用到;在 pack.json 用 \"blink\" 指定眨眼資料夾名稱。") % [face, blink_face])
	# Mal 式的 _l/_r 左右兩組:兩邊都有就只取朝右的 _r
	for action_name: String in actions.keys():
		if action_name.ends_with("_r"):
			var base := action_name.left(action_name.length() - 2)
			if actions.has(base + "_l") or not actions.has(base):
				actions[base] = actions[action_name]
				actions.erase(action_name)
				actions.erase(base + "_l")
	_apply_frame_overrides(root, manifest, actions, counter, report)
	if counter[0] > MAX_FILES:
		report.append(TranslationServer.translate("圖片超過 %d 張的上限,多的已略過。") % MAX_FILES)
	return {"actions": actions, "overlays": overlays}


## pack.json 的 "frames":{ "<動作>": [ 項目… ] } 覆蓋(或新增)該動作的幀清單。項目的寫法:
##   "相對路徑.png"                                        一張圖
##   {"file": "相對路徑.png", "pivot": [x, y], "offset": [dx, dy]}        一張圖,帶這一幀自己的軸心/圖片偏移(都可省略)
##   {"sheet": "相對路徑.png", "rect": [x, y, w, h], "pivot": …, "offset": …}   精靈圖切片(引用精靈圖的一塊區域,不複製像素)
## 給精靈圖編輯器用:匯入、新增、覆蓋、複製貼上、調換順序、刪幀都只是改這份清單,不動原本的檔案;每一幀的軸心/偏移跟著項目走,調整順序不會對不上。
## 只接受素材包資料夾內的相對路徑(不可 .. 或絕對路徑)、圖片副檔名;壞的項目略過並記在 report,整個動作都沒有好項目就維持原本掃到的。
## 清單裡每個幀都用「虛擬路徑」表示(見 make_virtual),序號 = 它在 frames 清單裡的位置(壞項目略過後序號會有空缺,不影響設定對應)。
## 項目自己的 pivot / offset 會寫進 manifest 的 pivots / offsets 表(鍵 "<動作>/<序號>",蓋過同鍵的舊值)——所以呼叫端傳進來的 manifest 會被改,編輯器要傳複本。
static func _apply_frame_overrides(root: String, manifest: Dictionary, actions: Dictionary, counter: Array, report: Array[String]) -> void:
	var overrides: Variant = manifest.get("frames")
	if not overrides is Dictionary:
		return
	for action_key: Variant in overrides:
		var action_name := _clean_action_name(str(action_key))
		var refs: Variant = overrides[action_key]
		if action_name == "" or not refs is Array:
			continue
		var list: Array[String] = []
		for position in (refs as Array).size():
			var resolved := _resolve_frame_ref(root, refs[position], position, report)
			if resolved.is_empty():
				continue
			list.append(resolved["path"])
			counter[0] += 1
			for setting: String in ["pivot", "offset"]:
				if resolved.has(setting):
					var table_name := setting + "s"
					var table: Dictionary = manifest.get(table_name, {}) if manifest.get(table_name) is Dictionary else {}
					var value: Vector2 = resolved[setting]
					table["%s/%d" % [action_name, position]] = [value.x, value.y]
					manifest[table_name] = table
		if list.is_empty():
			report.append(TranslationServer.translate("pack.json 的 frames「%s」沒有可用的項目,維持原本掃到的幀。") % action_name)
			continue
		actions[action_name] = list


## 一個 frames 項目 → {path(虛擬路徑), pivot?, offset?};失敗回空字典。
static func _resolve_frame_ref(root: String, ref: Variant, index: int, report: Array[String]) -> Dictionary:
	var result := {}
	if ref is String:
		var whole := _safe_pack_path(root, ref, report)
		if whole == "":
			return {}
		result["path"] = make_virtual(whole, Rect2i(), index)
		return result
	if not ref is Dictionary:
		report.append(TranslationServer.translate("frames 裡有看不懂的項目,已略過:%s") % str(ref).left(60))
		return {}
	# 圖片處理(裁切/翻轉/旋轉):寫法不對就忽略這個欄位(圖照原樣用),不讓整幀消失。
	var fx := ""
	if ref.get("fx") is String and str(ref["fx"]).strip_edges() != "":
		var parsed_fx: Variant = PackImageFx.parse(str(ref["fx"]))
		if parsed_fx == null or "|" in str(ref["fx"]):
			report.append(TranslationServer.translate("frames 的 fx(圖片處理)寫法不對,已忽略:%s") % str(ref["fx"]).left(60))
		else:
			fx = PackImageFx.serialize(parsed_fx as Array)
	if ref.get("sheet") is String and ref.get("rect") is Array and (ref["rect"] as Array).size() >= 4:
		var sheet := _safe_pack_path(root, ref["sheet"], report)
		if sheet == "":
			return {}
		var rect_values: Array = ref["rect"]
		for value: Variant in rect_values.slice(0, 4):
			if not (value is float or value is int):
				report.append(TranslationServer.translate("frames 的切片範圍不是數字:%s") % str(rect_values))
				return {}
		var rect := Rect2i(int(rect_values[0]), int(rect_values[1]), int(rect_values[2]), int(rect_values[3]))
		if rect.position.x < 0 or rect.position.y < 0 or rect.size.x < 1 or rect.size.y < 1 or rect.size.x > MAX_SIDE or rect.size.y > MAX_SIDE:
			report.append(TranslationServer.translate("frames 的切片範圍不合理,已略過:%s") % str(rect_values))
			return {}
		result["path"] = make_virtual(sheet, rect, index, fx)
	elif ref.get("file") is String:
		var file_path := _safe_pack_path(root, ref["file"], report)
		if file_path == "":
			return {}
		result["path"] = make_virtual(file_path, Rect2i(), index, fx)
	else:
		report.append(TranslationServer.translate("frames 裡有看不懂的項目,已略過:%s") % str(ref).left(60))
		return {}
	for setting: String in ["pivot", "offset"]:
		var pair: Variant = ref.get(setting)
		if pair is Array and pair.size() >= 2 and (pair[0] is float or pair[0] is int) and (pair[1] is float or pair[1] is int):
			result[setting] = Vector2(roundf(float(pair[0])), roundf(float(pair[1])))
	return result

## 素材包資料夾內的相對路徑 → 完整路徑;不是相對路徑、含 ..、副檔名不是圖片、檔案不存在都回空字串。
static func _safe_pack_path(root: String, relative: String, report: Array[String]) -> String:
	var clean := relative.replace("\\", "/").strip_edges()
	if clean == "" or clean.is_absolute_path() or clean.begins_with("/") or ":" in clean or ".." in clean.split("/"):
		report.append(TranslationServer.translate("frames 的路徑必須是素材包資料夾內的相對路徑,已略過:%s") % relative.left(60))
		return ""
	if not IMAGE_EXTENSIONS.has(clean.get_extension().to_lower()):
		report.append(TranslationServer.translate("frames 的檔案不是圖片,已略過:%s") % clean.left(60))
		return ""
	var full := root.path_join(clean)
	if not FileAccess.file_exists(full):
		report.append(TranslationServer.translate("frames 指到的檔案不存在,已略過:%s") % clean.left(60))
		return ""
	return full


# --- 「虛擬幀路徑」(frames 清單裡的每一幀):<圖片完整路徑>|x,y,w,h|<序號>;整張圖(不是切片)的 x,y,w,h 寫成 - ---

static func is_virtual(path: String) -> bool:
	return path.contains("|")


## fx = 圖片處理步驟(裁切/翻轉/旋轉,見 PackImageFx);沒有處理就不寫,路徑還是三段。
static func make_virtual(file: String, rect: Rect2i, index: int, fx := "") -> String:
	var base := "%s|-|%d" % [file, index] if rect.size == Vector2i.ZERO else "%s|%d,%d,%d,%d|%d" % [file, rect.position.x, rect.position.y, rect.size.x, rect.size.y, index]
	return base if fx == "" else "%s|%s" % [base, fx]


## 是精靈圖切片(不是整張圖的虛擬幀)。
static func is_slice(path: String) -> bool:
	var parsed := parse_virtual(path)
	return not parsed.is_empty() and (parsed["rect"] as Rect2i).size != Vector2i.ZERO


## 這一幀有圖片處理(裁切/翻轉/旋轉)。
static func has_fx(path: String) -> bool:
	return str(parse_virtual(path).get("fx", "")) != ""


## 拆解虛擬路徑 → {file, rect, index, fx};不是虛擬路徑或格式錯誤回空字典。
static func parse_virtual(path: String) -> Dictionary:
	var parts := path.split("|")
	if parts.size() != 3 and parts.size() != 4:
		return {}
	var fx := parts[3] if parts.size() == 4 else ""
	if parts[1] == "-":
		return {"file": parts[0], "rect": Rect2i(), "index": int(parts[2]), "fx": fx}
	var numbers := parts[1].split(",")
	if numbers.size() != 4:
		return {}
	return {"file": parts[0], "rect": Rect2i(int(numbers[0]), int(numbers[1]), int(numbers[2]), int(numbers[3])), "index": int(parts[2]), "fx": fx}


## 精靈圖的讀圖快取(完整圖只解碼一次;每個切片只是貼圖的一個區域)。load_pack 結束、編輯器關閉時清掉。
static var _sheet_cache: Dictionary = {}


static func clear_sheet_cache() -> void:
	_sheet_cache.clear()


## 讀一張精靈圖(有快取)。回傳 {image, tex, size};讀不出來回空字典。
static func _sheet(path: String, total_pixels: Array, report: Array[String]) -> Dictionary:
	if _sheet_cache.has(path):
		return _sheet_cache[path]
	var image := _load_image(path, report)
	if image == null:
		return {}
	if image.get_width() > MAX_SIDE or image.get_height() > MAX_SIDE:
		report.append(TranslationServer.translate("精靈圖尺寸超過 %d,已略過:%s") % [MAX_SIDE, path.get_file()])
		return {}
	total_pixels[0] += image.get_width() * image.get_height()
	if total_pixels[0] > MAX_TOTAL_PIXELS:
		report.append("素材包總像素超過上限,後面的圖已略過。")
		return {}
	var entry := {"image": image, "tex": ImageTexture.create_from_image(image), "size": Vector2i(image.get_width(), image.get_height())}
	_sheet_cache[path] = entry
	return entry


static func _list_images(folder: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return result
	for file_name in dir.get_files():
		if IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
			result.append(file_name)
	return result


static func _list_dirs(folder: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return result
	for dir_name in dir.get_directories():
		if not dir_name.begins_with("."):
			result.append(dir_name)
	result.sort()
	return result


## 「<動作>_<幀>.png」與「<動作><兩位以上數字>.png」歸類到 actions[動作] = [依幀序排好的路徑]。
static func _group_flat(folder: String, file_names: Array[String], actions: Dictionary, counter: Array, report: Array[String]) -> void:
	var grouped: Dictionary = {}
	for file_name in file_names:
		counter[0] += 1
		if counter[0] > MAX_FILES:
			return
		var base := file_name.get_basename()
		var match_result := _RE_UNDERSCORE.search(base)
		if match_result == null:
			match_result = _RE_TRAILING.search(base)
		if match_result == null:
			report.append(TranslationServer.translate("檔名「%s」看不出幀編號(要像 walk_0.png 或 walk00.png),已略過。") % file_name)
			continue
		var action_name := match_result.get_string(1).trim_suffix("_")
		if not grouped.has(action_name):
			grouped[action_name] = []
		grouped[action_name].append([int(match_result.get_string(2)), folder.path_join(file_name)])
	for action_name: String in grouped:
		var entries: Array = grouped[action_name]
		entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var paths: Array = []
		for entry: Array in entries:
			paths.append(entry[1])
		actions[action_name] = paths


## 「<動作>/0.png、1.png…」:資料夾名稱是動作名稱。
static func _group_action_folder(action_name: String, folder: String, file_names: Array[String], actions: Dictionary, counter: Array, report: Array[String]) -> void:
	var entries: Array = []
	for file_name in file_names:
		counter[0] += 1
		if counter[0] > MAX_FILES:
			return
		var base := file_name.get_basename()
		var number := _RE_UNDERSCORE.search(base)
		var digits := number.get_string(2) if number != null else (base if _RE_ONLY_NUMBER.search(base) != null else "")
		if digits == "":
			report.append(TranslationServer.translate("「%s/%s」看不出幀編號,已略過。") % [action_name, file_name])
			continue
		entries.append([int(digits), folder.path_join(file_name)])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var paths: Array = []
	for entry: Array in entries:
		paths.append(entry[1])
	if not paths.is_empty():
		actions[action_name] = paths


## 規劃要建的動畫。回傳 {"動畫名(如 idle_0)" → {source = 素材包動作名, frames = 來源幀索引陣列}}。
static func _plan_animations(actions: Dictionary, manifest: Dictionary, report: Array[String]) -> Dictionary:
	var plan: Dictionary = {}
	var consumed: Dictionary = {}
	var lower_lookup: Dictionary = {}
	for action_name: String in actions:
		lower_lookup[action_name.to_lower()] = action_name
	var configured: Dictionary = manifest.get("actions", {}) if manifest.get("actions") is Dictionary else {}
	var system_names: Array = ALIASES.keys()
	for extra: String in configured:
		if not system_names.has(extra):
			system_names.append(extra)
	for system_action: String in system_names:
		var spec: Variant = configured.get(system_action)
		var variants: Array = []
		if spec is String or spec is Dictionary:
			variants = [spec]
		elif spec is Array:
			variants = spec
		elif spec == null and ALIASES.has(system_action):
			for candidate: String in ALIASES[system_action]:
				if lower_lookup.has(candidate):
					variants = [lower_lookup[candidate]]
					break
		var index := 0
		for variant: Variant in variants:
			var source := ""
			var picked: Array = []
			if variant is String:
				source = lower_lookup.get(str(variant).to_lower(), "")
			elif variant is Dictionary:
				source = lower_lookup.get(str(variant.get("from", "")).to_lower(), "")
				if variant.get("frames") is Array:
					for frame_index: Variant in variant["frames"]:
						if frame_index is float or frame_index is int:
							picked.append(int(frame_index))
			if source == "":
				report.append(TranslationServer.translate("動作對應「%s」指定的「%s」在素材包裡找不到,已略過。") % [system_action, str(variant)])
				continue
			var source_count: int = (actions[source] as Array).size()
			if picked.is_empty():
				for i in source_count:
					picked.append(i)
			picked = picked.filter(func(i: int) -> bool: return i >= 0 and i < source_count)
			if picked.is_empty():
				continue
			plan["%s_%d" % [system_action, index]] = {"source": source, "frames": picked}
			consumed[source] = true
			index += 1
	# 沒被系統動作用到的,原名保留當自訂動作(名稱只留英數與底線)
	for action_name: String in actions:
		if consumed.has(action_name):
			continue
		var custom := _clean_action_name(action_name)
		if custom == "" or plan.has(custom + "_0"):
			continue
		var all_frames: Array = []
		for i in (actions[action_name] as Array).size():
			all_frames.append(i)
		plan[custom + "_0"] = {"source": action_name, "frames": all_frames}
	return plan


static var _RE_BAD_NAME_CHARS := RegEx.create_from_string("[^A-Za-z0-9_]")


static func _clean_action_name(action_name: String) -> String:
	return _RE_BAD_NAME_CHARS.sub(action_name.strip_edges(), "_", true).left(40)


static func _plan_uses_source(plan: Dictionary, source_name: String) -> bool:
	for animation_name: String in plan:
		if plan[animation_name]["source"] == source_name:
			return true
	return false


## 讀一張圖。回傳 {tex(ImageTexture), size(Vector2i), tag(Rect2i,名字標籤位置,detect_tag 為 false 或沒偵測到時是空 Rect2i)};
## 失敗回空字典並記在 report。受檔案大小、尺寸、總像素上限保護。
static func _load_info(path: String, total_pixels: Array, report: Array[String], detect_tag: bool) -> Dictionary:
	if is_virtual(path):
		# 精靈圖切片:不複製像素,貼圖是整張精靈圖、origin 是切片在裡面的左上角(名字標籤偵測不適用)。
		var slice := parse_virtual(path)
		if slice.is_empty():
			return {}
		if str(slice.get("fx", "")) != "":
			return _fx_info(path, slice, total_pixels, report)
		if not is_slice(path):
			# frames 清單裡的整張圖:照一般圖片讀(名字標籤偵測照舊)。同一個檔案被好幾幀引用(複製貼上、重複的姿勢)只讀一次。
			var cache_key := "info:" + str(slice["file"])
			if _sheet_cache.has(cache_key):
				return _sheet_cache[cache_key]
			var whole := _load_info(str(slice["file"]), total_pixels, report, detect_tag)
			if not whole.is_empty():
				_sheet_cache[cache_key] = whole
			return whole
		var sheet := _sheet(str(slice["file"]), total_pixels, report)
		if sheet.is_empty():
			return {}
		var rect: Rect2i = slice["rect"]
		if not Rect2i(Vector2i.ZERO, sheet["size"]).encloses(rect):
			report.append(TranslationServer.translate("切片超出精靈圖範圍,已略過:%s %s") % [str(slice["file"]).get_file(), str(rect)])
			return {}
		return {"tex": sheet["tex"], "size": rect.size, "tag": Rect2i(), "origin": rect.position}
	var image := _load_image(path, report)
	if image == null:
		return {}
	if image.get_width() > MAX_SIDE or image.get_height() > MAX_SIDE:
		report.append(TranslationServer.translate("圖片尺寸超過 %d,已略過:%s") % [MAX_SIDE, path.get_file()])
		return {}
	total_pixels[0] += image.get_width() * image.get_height()
	if total_pixels[0] > MAX_TOTAL_PIXELS:
		report.append("素材包總像素超過上限,後面的圖已略過。")
		return {}
	return {
		"tex": ImageTexture.create_from_image(image),
		"size": Vector2i(image.get_width(), image.get_height()),
		"tag": detect_nametag(image) if detect_tag else Rect2i(),
	}


## 有圖片處理的一幀:先取出原圖(整張或切片),照 fx 的步驟處理,結果(新的貼圖)只算一次、之後重用。沒有名字標籤偵測。
static func _fx_info(path: String, slice: Dictionary, total_pixels: Array, report: Array[String]) -> Dictionary:
	var cache_key := "fx:" + path
	if _sheet_cache.has(cache_key):
		return _sheet_cache[cache_key]
	var image := _base_image_of(slice, report)
	if image == null:
		return {}
	var processed := _process_fx(image, str(slice["fx"]), path, report)
	if processed == null:
		return {}
	total_pixels[0] += processed.get_width() * processed.get_height()
	if total_pixels[0] > MAX_TOTAL_PIXELS:
		report.append("素材包總像素超過上限,後面的圖已略過。")
		return {}
	var info := {"tex": ImageTexture.create_from_image(processed), "size": Vector2i(processed.get_width(), processed.get_height()), "tag": Rect2i()}
	_sheet_cache[cache_key] = info
	return info


## 虛擬路徑指到的原圖(還沒套用圖片處理):整張圖或精靈圖切片。讀不出來回 null。
static func _base_image_of(slice: Dictionary, report: Array[String]) -> Image:
	if (slice["rect"] as Rect2i).size == Vector2i.ZERO:
		var whole := _load_image(str(slice["file"]), report)
		if whole != null and (whole.get_width() > MAX_SIDE or whole.get_height() > MAX_SIDE):
			report.append(TranslationServer.translate("圖片尺寸超過 %d,已略過:%s") % [MAX_SIDE, str(slice["file"]).get_file()])
			return null
		return whole
	var sheet := _sheet(str(slice["file"]), [0], report)
	if sheet.is_empty():
		return null
	var rect: Rect2i = slice["rect"]
	if not Rect2i(Vector2i.ZERO, sheet["size"]).encloses(rect):
		report.append(TranslationServer.translate("切片超出精靈圖範圍,已略過:%s %s") % [str(slice["file"]).get_file(), str(rect)])
		return null
	return (sheet["image"] as Image).get_region(rect)


static func _process_fx(image: Image, fx: String, path: String, report: Array[String]) -> Image:
	var ops: Variant = PackImageFx.parse(fx)
	if ops == null:
		report.append(TranslationServer.translate("圖片處理的寫法不對,已略過這一幀:%s") % fx.left(60))
		return null
	var processed := PackImageFx.apply(image, ops as Array)
	if processed == null:
		report.append(TranslationServer.translate("圖片處理的結果是空的或太大,已略過這一幀:%s(%s)") % [path.get_slice("|", 0).get_file(), fx.left(60)])
	return processed


static func _load_image(path: String, report: Array[String]) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		report.append(TranslationServer.translate("讀不了檔案:%s") % path.get_file())
		return null
	if file.get_length() > MAX_FILE_BYTES:
		report.append(TranslationServer.translate("檔案太大(> %d MB),已略過:%s") % [MAX_FILE_BYTES / 1_000_000, path.get_file()])
		return null
	var bytes := file.get_buffer(file.get_length())
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match path.get_extension().to_lower():
		"png":
			error = image.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			error = image.load_jpg_from_buffer(bytes)
		"webp":
			error = image.load_webp_from_buffer(bytes)
	if error != OK or image.is_empty():
		report.append(TranslationServer.translate("圖片毀損或格式不對,已略過:%s") % path.get_file())
		return null
	return image


## 偵測圖片底部的「烘進去的名字標籤」(例如 MapleStory 匯出的角色圖):半透明(不是全透明也不是全不透明)的橫向色塊,
## 寬度至少是圖寬的 35%(且不少於 20 像素)、連續至少 6 列,取最下面的一塊。回傳它的範圍,沒有就回空的 Rect2i。
## 標籤的水平中心 = 角色原點,標籤上緣往上幾像素 = 腳底線,所以可以用來對齊每一幀。
static func detect_nametag(image: Image) -> Rect2i:
	var rgba := image.duplicate() as Image
	rgba.convert(Image.FORMAT_RGBA8)
	var width := rgba.get_width()
	var height := rgba.get_height()
	var data := rgba.get_data()
	var min_run := maxi(20, int(width * 0.35))
	var best := Rect2i()
	var run_top := -1
	var run_min_x := width
	var run_max_x := -1
	for y in range(height + 1):
		var count := 0
		var row_min := width
		var row_max := -1
		if y < height:
			for x in width:
				var alpha := data[(y * width + x) * 4 + 3]
				if alpha > 2 and alpha < 250:
					count += 1
					row_min = mini(row_min, x)
					row_max = maxi(row_max, x)
		if count >= min_run:
			if run_top < 0:
				run_top = y
			run_min_x = mini(run_min_x, row_min)
			run_max_x = maxi(run_max_x, row_max)
		elif run_top >= 0:
			if y - run_top >= 6:
				best = Rect2i(run_min_x, run_top, run_max_x - run_min_x + 1, y - run_top)
			run_top = -1
			run_min_x = width
			run_max_x = -1
	return best


## 沒開 nametag: align 但待機幀偵測到疑似名字標籤時,提醒創作者(圖片浮空多半是這個原因)。
static func _nametag_hint(idle_path: String, aligned: bool) -> String:
	if aligned or idle_path == "":
		return ""
	var image := _load_image(idle_path, [])
	if image == null or detect_nametag(image).size == Vector2i.ZERO:
		return ""
	return "待機圖底部疑似有烘進去的名字標籤(半透明色塊),角色可能會浮在地面上方;在 pack.json 設 \"nametag\": \"align\" 可用標籤自動對齊腳底與中心,並自動裁掉標籤。"


## 這一幀的軸心(像素座標,從圖的左上角算)。優先順序見 load_pack 的說明。
static func _pivot_for(path: String, source_action: String, info: Dictionary, manifest: Dictionary, nametag_align: bool, ceiling := false) -> Vector2:
	var size: Vector2i = info["size"]
	var pivots: Dictionary = manifest.get("pivots", {}) if manifest.get("pivots") is Dictionary else {}
	var explicit: Variant = lookup_frame_key(pivots, path, source_action)
	if explicit is Array and explicit.size() >= 2 and (explicit[0] is float or explicit[0] is int) and (explicit[1] is float or explicit[1] is int):
		return Vector2(roundf(clampf(float(explicit[0]), 0.0, float(size.x))), roundf(clampf(float(explicit[1]), 0.0, float(size.y))))
	var tag: Rect2i = info["tag"]
	if nametag_align and tag.size != Vector2i.ZERO:
		var gap := _number(manifest.get("nametag_gap"), 4.0)
		return Vector2(roundf(float(tag.position.x) + float(tag.size.x) * 0.5), roundf(clampf(float(tag.position.y) - gap, 1.0, float(size.y))))
	if ceiling:
		# 天花板素材:軸心在圖的上緣(抓著天花板的那一點),水平置中(可用 pivot_x_offset 調整)。
		var ceiling_x_offset: Variant = manifest.get("pivot_x_offset")
		return Vector2(roundf(clampf(float(size.x) * 0.5 + (float(ceiling_x_offset) if ceiling_x_offset is float or ceiling_x_offset is int else 0.0), 0.0, float(size.x))), 0.0)
	var foot_from_bottom := 0.0
	var foot_value: Variant = manifest.get("foot_from_bottom")
	if foot_value is float or foot_value is int:
		foot_from_bottom = clampf(float(foot_value), 0.0, float(size.y) - 1.0)
	var x_offset := 0.0
	var x_value: Variant = manifest.get("pivot_x_offset")
	if x_value is float or x_value is int:
		x_offset = float(x_value)
	return Vector2(roundf(clampf(float(size.x) * 0.5 + x_offset, 0.0, float(size.x))), float(size.y) - foot_from_bottom)


## pivots / offsets 的查找順序(越具體越優先):"<動作名>/<檔名>"(動作資料夾式素材包的幀都叫 0、1、2,檔名會跨動作撞名時用)> 單張圖的檔名 > 整個動作名。
static func lookup_frame_key(table: Dictionary, path: String, source_action: String) -> Variant:
	# 精靈圖切片沒有自己的檔名,用它在動作裡的序號當「檔名」(所以 pivots 的鍵是 "<動作>/<序號>" 或單獨的序號)。
	var base := str(parse_virtual(path).get("index", 0)) if is_virtual(path) else path.get_file().get_basename()
	if table.has(source_action + "/" + base):
		return table[source_action + "/" + base]
	return table.get(base, table.get(source_action))


## 這一幀的圖片偏移 [dx, dy](像素;圖片相對軸心平移,x 向右、y 向下)。優先順序同 pivots:單幀檔名 > 整個動作名;沒有就 (0, 0)。
static func _offset_for(path: String, source_action: String, manifest: Dictionary) -> Vector2:
	var offsets: Dictionary = manifest.get("offsets", {}) if manifest.get("offsets") is Dictionary else {}
	var explicit: Variant = lookup_frame_key(offsets, path, source_action)
	if explicit is Array and explicit.size() >= 2 and (explicit[0] is float or explicit[0] is int) and (explicit[1] is float or explicit[1] is int):
		return Vector2(roundf(clampf(float(explicit[0]), -MAX_OFFSET, MAX_OFFSET)), roundf(clampf(float(explicit[1]), -MAX_OFFSET, MAX_OFFSET)))
	return Vector2.ZERO


## 把一幀放進 cell 大小的畫布:軸心對齊到 (畫布水平中心, 距畫布上緣 up_max),用 AtlasTexture 的 margin 做,不複製像素。
## 圖片實際貼的位置是「軸心 − offset」(offset 見 _offset_for);crop 為 true 時圖片裡軸心那一列以下的部分不畫(裁掉名字標籤、影子)。
static func _frame_texture(info: Dictionary, pivot: Vector2, offset: Vector2, cell: Vector2i, up_max: float, crop: bool) -> Texture2D:
	var size: Vector2i = info["size"]
	var used_height := clampi(int(pivot.y), 1, size.y) if crop else size.y
	var place := pivot - offset
	var origin: Vector2i = info.get("origin", Vector2i.ZERO)
	var atlas := AtlasTexture.new()
	atlas.atlas = info["tex"]
	atlas.region = Rect2(origin.x, origin.y, size.x, used_height)
	atlas.margin = Rect2(float(cell.x) * 0.5 - place.x, up_max - place.y, float(cell.x - size.x), float(cell.y - used_height))
	return atlas


# --- 給素材包編輯器用的公開介面 ---

## 讀素材包資料夾裡的 pack.json(沒有或壞掉回空字典)。
static func read_manifest(root: String) -> Dictionary:
	var ignored: Array[String] = []
	return _read_manifest(root, ignored)


## 動作名稱清理(去掉不能用的字元、限制長度);清完是空的代表名稱無效。
static func clean_action_name(action_name: String) -> String:
	return _clean_action_name(action_name)


## 掃描素材包但不建 SpriteFrames:回傳 {ok, root, manifest(pack.json 原樣), actions{動作名 → [圖片路徑…]}, nametag_align, ceiling_actions[動作名], report}。
static func inspect_pack(folder: String) -> Dictionary:
	var report: Array[String] = []
	var root := folder.strip_edges().trim_suffix("/").trim_suffix("\\")
	if root == "" or DirAccess.open(root) == null:
		return {"ok": false, "report": [TranslationServer.translate("找不到資料夾:%s") % folder]}
	var manifest := _read_manifest(root, report)
	var scanned := scan_actions(root, manifest)
	if (scanned["actions"] as Dictionary).is_empty():
		return {"ok": false, "report": ["資料夾裡找不到可用的圖片"] + (scanned["report"] as Array)}
	return {
		"ok": true, "root": root, "manifest": manifest, "actions": scanned["actions"], "report": report + (scanned["report"] as Array),
		"ceiling_actions": scanned["ceiling_actions"], "nametag_align": str(manifest.get("nametag", "off")).to_lower() == "align",
	}


## 用給定的 pack.json 內容(編輯器的工作副本,不一定和磁碟上的一樣)掃描動作:回傳 {actions{動作名 → [幀路徑…]}, ceiling_actions[動作名], animations{動作名 → [動畫基本名稱…](fps_by_action 的鍵)}, report}。
## 沒有任何圖片時 actions 是空的(新建的素材包就是這樣),不當成錯誤。
static func scan_actions(root: String, manifest: Dictionary) -> Dictionary:
	var report: Array[String] = []
	# frames 清單項目自己的軸心/偏移會被展開進 manifest 的 pivots / offsets 表,所以用複本,不動編輯器的工作副本。
	var working := manifest.duplicate(true)
	var layout := _scan(root, working, report)
	var actions: Dictionary = layout.get("actions", {})
	var ceiling_actions: Array[String] = []
	var animations: Dictionary = {}
	if not actions.is_empty():
		var plan := _plan_animations(actions, working, report)
		for animation_name: String in plan:
			var source := str(plan[animation_name]["source"])
			if animation_name.begins_with("climb_ceiling_") and not ceiling_actions.has(source):
				ceiling_actions.append(source)
			# 動畫的基本名稱(去掉尾端 _數字)= fps_by_action 的鍵
			var base_name := animation_name.substr(0, animation_name.rfind("_"))
			animations[source] = animations.get(source, [])
			if not (animations[source] as Array).has(base_name):
				(animations[source] as Array).append(base_name)
	return {"actions": actions, "ceiling_actions": ceiling_actions, "animations": animations, "report": report}


## 讀一幀的圖:一般檔案直接讀,精靈圖切片(虛擬路徑)從精靈圖裁出那一塊(複製一份,只給編輯器顯示用)。讀不出來回 null。
static func load_frame_image(path: String, report: Array[String]) -> Image:
	if not is_virtual(path):
		return _load_image(path, report)
	var slice := parse_virtual(path)
	if slice.is_empty():
		return null
	if str(slice.get("fx", "")) != "":
		var base := _base_image_of(slice, report)
		return _process_fx(base, str(slice["fx"]), path, report) if base != null else null
	if not is_slice(path):
		return _load_image(str(slice["file"]), report)
	var sheet := _sheet(str(slice["file"]), [0], report)
	if sheet.is_empty():
		return null
	var rect: Rect2i = slice["rect"]
	if not Rect2i(Vector2i.ZERO, sheet["size"]).encloses(rect):
		report.append(TranslationServer.translate("切片超出精靈圖範圍:%s") % str(rect))
		return null
	return (sheet["image"] as Image).get_region(rect)


## 一幀目前生效的資料(編輯器顯示用):{image, size, pivot(含 pivots 指定的), auto_pivot(不看 pivots 的自動值), offset}。讀不出圖回空字典。
static func frame_info(path: String, source_action: String, manifest: Dictionary, ceiling := false) -> Dictionary:
	var report: Array[String] = []
	var image := load_frame_image(path, report)
	if image == null or image.get_width() > MAX_SIDE or image.get_height() > MAX_SIDE:
		return {}
	var nametag_align := str(manifest.get("nametag", "off")).to_lower() == "align" and not ceiling and not is_slice(path) and not has_fx(path)
	var info := {"size": Vector2i(image.get_width(), image.get_height()), "tag": detect_nametag(image) if nametag_align else Rect2i()}
	var without_explicit := manifest.duplicate()
	without_explicit.erase("pivots")
	return {
		"image": image, "size": info["size"],
		"pivot": _pivot_for(path, source_action, info, manifest, nametag_align, ceiling),
		"auto_pivot": _pivot_for(path, source_action, info, without_explicit, nametag_align, ceiling),
		"offset": _offset_for(path, source_action, manifest),
	}