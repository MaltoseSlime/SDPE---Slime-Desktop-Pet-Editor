class_name PackEditorModel
extends RefCounted
## 素材包編輯器的資料層(沒有任何介面,方便無頭測試):開啟/新建素材包資料夾、匯入圖片與精靈圖(覆蓋或新增)、
## 記錄每一幀的軸心(pivots)、圖片偏移(offsets)與判定框(hitbox)的編輯,全都是 pack.json 的欄位,
## 存檔時其他欄位原樣保留(寫入前把舊檔備份成 pack.json.bak,每次開啟只備份一次)。
## 匯入只改 pack.json 的 "frames" 清單(見 SpritePackLoader._apply_frame_overrides),被覆蓋的舊檔案不會被刪,所以撤回/重做不必動檔案。
## 匯入時圖片與精靈圖會複製進素材包資料夾(.imports/、.sheets/),素材包保持自包含;撤回後這些複製出來的檔案會留著(沒被引用)。
## 名詞:軸心 = 腳底線 + 中心點,圖片偏移 = 圖片相對軸心的平移,見 docs/專有名詞表.md 與 docs/素材包格式.md。

const MAX_OFFSET := SpritePackLoader.MAX_OFFSET
const MAX_HITBOX := 4096.0
## 一次匯入最多幾張圖 / 切出幾個切片。
const MAX_IMPORT_FRAMES := 256
## 點開頭的資料夾會被載入器略過(否則裡面的圖會被當成一個叫 imports 的動作),幀靠 pack.json 的 frames 清單指過來。
const IMPORT_FOLDER := ".imports"
const SHEET_FOLDER := ".sheets"
## 撤回/重做各保留的步數上限。
const UNDO_LIMIT := 25
## 同一個標籤的連續編輯在這麼短的間隔內合併成一步(連續按方向鍵、連續改同一個數值框)。
const COALESCE_MSEC := 700

var root := ""
## pack.json 的工作副本(編輯會改它的 pivots / offsets)。
var manifest: Dictionary = {}
## 動作名 → [圖片路徑…(依幀序)],和載入器掃描結果一致。
var actions: Dictionary = {}
var ceiling_actions: Array = []
## 和上次存檔(或剛開啟)的內容不一樣就是 true;撤回回到存檔時的樣子會變回 false。
var dirty := false

## 複製的幀(項目格式同 frame_refs,連同各幀實際生效的軸心/偏移);換素材包就清掉(路徑是相對於素材包資料夾的)。
var clipboard: Array = []

var _frames: Dictionary = {}
var _animations: Dictionary = {}
var _basename_actions: Dictionary = {}
var _backed_up := false
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _saved_hash := 0
var _last_checkpoint_tag := ""
var _last_checkpoint_msec := -1000000


## 有沒有已經開啟(或新建)的素材包。
func has_pack() -> bool:
	return root != ""


## 開啟素材包資料夾。成功回空字串,失敗回原因。有圖片的、有 pack.json 的、完全空的資料夾都能開(空的就是還沒放圖的新素材包)。
func open(folder: String) -> String:
	var inspected := SpritePackLoader.inspect_pack(folder)
	if bool(inspected["ok"]):
		_start(inspected["root"], inspected["manifest"])
		return ""
	var clean := folder.strip_edges().trim_suffix("/").trim_suffix("\\")
	if clean != "" and DirAccess.dir_exists_absolute(clean) and (FileAccess.file_exists(clean.path_join("pack.json")) or _is_empty_folder(clean)):
		_start(clean, SpritePackLoader.read_manifest(clean))
		return ""
	return str((inspected["report"] as Array)[0])


static func _is_empty_folder(path: String) -> bool:
	return DirAccess.get_files_at(path).is_empty() and DirAccess.get_directories_at(path).is_empty()


## 新建素材包:資料夾不存在就建立;裡面已經有素材包內容(圖片或 pack.json)就照原樣開啟、不清空。成功回空字串。
func create(folder: String) -> String:
	var clean := folder.strip_edges().trim_suffix("/").trim_suffix("\\")
	if clean == "":
		return "沒有選擇資料夾"
	if not DirAccess.dir_exists_absolute(clean) and DirAccess.make_dir_recursive_absolute(clean) != OK:
		return tr("無法建立資料夾:%s") % clean
	_start(clean, SpritePackLoader.read_manifest(clean))
	return ""


func _start(new_root: String, new_manifest: Dictionary) -> void:
	SpritePackLoader.clear_sheet_cache()
	root = new_root.replace("\\", "/")
	manifest = new_manifest
	# 配件(overlays.json)放在工作副本的 "__overlays" 鍵裡:撤回/重做、有沒有未存變更都跟著 pack.json 的內容一起算,存檔時再拆開寫成兩個檔。
	manifest.erase(OVERLAY_KEY)
	var overlay_path := root.path_join("overlays.json")
	if FileAccess.file_exists(overlay_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(overlay_path))
		if parsed is Dictionary:
			manifest[OVERLAY_KEY] = parsed
	clipboard.clear()
	_frames.clear()
	_rebuild_actions()
	dirty = false
	_backed_up = false
	_undo_stack.clear()
	_redo_stack.clear()
	_last_checkpoint_tag = ""
	_saved_hash = manifest.hash()


## 關閉時釋放精靈圖的讀圖快取。
func release() -> void:
	SpritePackLoader.clear_sheet_cache()
	_frames.clear()


## 依目前的 pack.json 工作副本重新掃描動作(匯入、撤回、重做之後,幀清單可能變了)。
func _rebuild_actions() -> void:
	var scanned := SpritePackLoader.scan_actions(root, manifest)
	actions = scanned["actions"]
	ceiling_actions = scanned["ceiling_actions"]
	_animations = scanned["animations"]
	_basename_actions.clear()
	for action: String in actions:
		for path: String in actions[action]:
			var base := _base_of(path)
			_basename_actions[base] = _basename_actions.get(base, {})
			(_basename_actions[base] as Dictionary)[action] = true


## 幀的「檔名」:一般檔案是不含副檔名的檔名,精靈圖切片是它在動作裡的序號(和載入器的 pivots 查找一致)。
func _base_of(path: String) -> String:
	return str(SpritePackLoader.parse_virtual(path).get("index", 0)) if SpritePackLoader.is_virtual(path) else path.get_file().get_basename()


## 在「即將修改」之前呼叫,把目前的 pack.json 內容存成一個可撤回的步驟(重做記錄會清空)。
## tag 非空且和上一次相同、又在 COALESCE_MSEC 內時,視為同一步的延續,不再新增(拖曳一次、連續按方向鍵、連續改同一個數值框都只算一步)。
func checkpoint(tag := "") -> void:
	var now := Time.get_ticks_msec()
	if tag != "" and tag == _last_checkpoint_tag and now - _last_checkpoint_msec < COALESCE_MSEC:
		_last_checkpoint_msec = now
		return
	_last_checkpoint_tag = tag
	_last_checkpoint_msec = now
	_undo_stack.append(manifest.duplicate(true))
	if _undo_stack.size() > UNDO_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


## 撤回一步。沒有可撤回的回 false。
func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	_redo_stack.append(manifest.duplicate(true))
	_restore(_undo_stack.pop_back())
	return true


## 重做一步(撤回的反向)。沒有可重做的回 false。
func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	_undo_stack.append(manifest.duplicate(true))
	_restore(_redo_stack.pop_back())
	return true


func _restore(snapshot: Dictionary) -> void:
	manifest = snapshot
	_last_checkpoint_tag = ""
	_rebuild_actions()
	dirty = manifest.hash() != _saved_hash


func action_names() -> Array[String]:
	var names: Array[String] = []
	for action: String in actions:
		names.append(action)
	return names


func frame_count(action: String) -> int:
	return (actions.get(action, []) as Array).size()


func frame_path(action: String, index: int) -> String:
	return (actions[action] as Array)[index]


## 這一幀不會變的資料(讀圖、貼圖、自動軸心);讀不出圖回空字典。
func frame(action: String, index: int) -> Dictionary:
	var path := frame_path(action, index)
	if not _frames.has(path):
		var info := SpritePackLoader.frame_info(path, action, manifest, ceiling_actions.has(action))
		if not info.is_empty():
			info["texture"] = ImageTexture.create_from_image(info["image"])
		_frames[path] = info
	return _frames[path]


## 目前生效的軸心:這一幀自己在 frames 清單裡的設定 > pivots 表(逐幀鍵 > 整個動作)> 自動值。
func pivot(action: String, index: int) -> Vector2:
	var info := frame(action, index)
	if info.is_empty():
		return Vector2.ZERO
	var explicit: Variant = _effective_setting("pivot", action, index)
	if explicit is Vector2:
		return _clamp_pivot(explicit, info["size"])
	return info["auto_pivot"]


func offset(action: String, index: int) -> Vector2:
	var explicit: Variant = _effective_setting("offset", action, index)
	return _clamp_offset(explicit) if explicit is Vector2 else Vector2.ZERO


## 設定軸心。whole_action = true 寫成整個動作共用(並清掉這個動作底下逐幀的舊值),否則只改這一幀。
func set_pivot(action: String, index: int, value: Vector2, whole_action: bool) -> void:
	var info := frame(action, index)
	if info.is_empty():
		return
	_write("pivot", action, index, _clamp_pivot(value, info["size"]), whole_action)


func set_offset(action: String, index: int, value: Vector2, whole_action: bool) -> void:
	_write("offset", action, index, _clamp_offset(value), whole_action)


## 把這一幀目前的軸心與圖片偏移套用到整個動作的所有幀。
func apply_to_action(action: String, index: int) -> void:
	var current_pivot := pivot(action, index)
	var current_offset := offset(action, index)
	_write("pivot", action, index, current_pivot, true)
	_write("offset", action, index, current_offset, true)


## 重設成自動值(軸心)與 0(圖片偏移)。whole_action = true 連整個動作底下的設定一起清掉。
func reset(action: String, index: int, whole_action: bool) -> void:
	for setting: String in ["pivot", "offset"]:
		var table_name := setting + "s"
		var table: Variant = manifest.get(table_name)
		if table is Dictionary:
			if whole_action:
				_erase_action_keys(table, action)
			table.erase(_frame_key(action, index))
			if (table as Dictionary).is_empty():
				manifest.erase(table_name)
		if whole_action:
			_clear_ref_setting(action, -1, setting)
		else:
			_clear_ref_setting(action, index, setting)
	dirty = manifest.hash() != _saved_hash


## 這一幀有沒有明確指定過(逐幀或整個動作),給介面標示用。
func has_explicit(action: String, index: int) -> bool:
	return _effective_setting("pivot", action, index) != null or _effective_setting("offset", action, index) != null


## 這一幀明確指定的 pivot / offset(沒有回 null):frames 清單裡這一幀自己的設定優先,再來是 pivots / offsets 表。
func _effective_setting(setting: String, action: String, index: int) -> Variant:
	var own: Variant = _ref_setting(action, index, setting)
	if own != null:
		return own
	return _explicit(manifest.get(setting + "s"), action, index)


## 這一幀在 frames 清單裡自己的設定(項目是字典且有這個鍵);沒有回 null。
func _ref_setting(action: String, index: int, setting: String) -> Variant:
	var ref_index := _ref_index(action, index)
	var stored := _stored_refs(action)
	if ref_index < 0 or ref_index >= stored.size() or not stored[ref_index] is Dictionary:
		return null
	var pair: Variant = (stored[ref_index] as Dictionary).get(setting)
	if pair is Array and pair.size() >= 2 and (pair[0] is float or pair[0] is int) and (pair[1] is float or pair[1] is int):
		return Vector2(float(pair[0]), float(pair[1]))
	return null


## manifest["frames"][動作](沒有這個動作的清單回空陣列;直接回傳裡面的參考,不是複本)。
func _stored_refs(action: String) -> Array:
	var frames_table: Variant = manifest.get("frames")
	if frames_table is Dictionary and (frames_table as Dictionary).get(action) is Array:
		return (frames_table as Dictionary)[action]
	return []


func _has_stored_refs(action: String) -> bool:
	var frames_table: Variant = manifest.get("frames")
	return frames_table is Dictionary and (frames_table as Dictionary).get(action) is Array


## 第 index 幀在 frames 清單裡的位置(虛擬路徑帶序號;不是 frames 清單的幀就是 -1)。
func _ref_index(action: String, index: int) -> int:
	var path := frame_path(action, index)
	return int(SpritePackLoader.parse_virtual(path).get("index", -1)) if SpritePackLoader.is_virtual(path) else -1


## 清掉 frames 清單裡幀自己的設定:index = -1 是這個動作的所有幀。
func _clear_ref_setting(action: String, index: int, setting: String) -> void:
	var stored := _stored_refs(action)
	if stored.is_empty():
		return
	var targets: Array[int] = []
	if index < 0:
		for i in stored.size():
			targets.append(i)
	else:
		var ref_index := _ref_index(action, index)
		if ref_index >= 0:
			targets.append(ref_index)
	for i in targets:
		if i < stored.size() and stored[i] is Dictionary:
			stored[i] = _normalize_ref(_without_key(stored[i], setting))


## 幀項目的正規形式:只有 file 沒有別的設定就縮成單純的路徑字串。
func _normalize_ref(ref: Variant) -> Variant:
	if ref is Dictionary and (ref as Dictionary).size() == 1 and (ref as Dictionary).has("file"):
		return (ref as Dictionary)["file"]
	return ref


func _without_key(ref: Dictionary, key: String) -> Dictionary:
	var copy := ref.duplicate(true)
	copy.erase(key)
	return copy


## 幀項目加上(或換掉)一個設定;字串項目先變成 {"file": …} 字典。
func _with_setting(ref: Variant, setting: String, value: Vector2) -> Dictionary:
	var result: Dictionary = {"file": ref} if ref is String else (ref as Dictionary).duplicate(true)
	result[setting] = [int(value.x), int(value.y)]
	return result


## 給寫檔用的 pack.json 內容:不含配件(配件寫在另一個檔 overlays.json)。
func _manifest_for_file() -> Dictionary:
	var clean := manifest.duplicate(true)
	clean.erase(OVERLAY_KEY)
	return clean


## 把配件寫進 overlays.json(沒有配件、原本也沒有檔案就不寫)。成功回空字串。
func _save_overlays(folder: String) -> String:
	var path := folder.path_join("overlays.json")
	var spec: Variant = manifest.get(OVERLAY_KEY)
	if not spec is Dictionary or ((spec as Dictionary).get("overlays", []) as Array).is_empty() and not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return tr("無法寫入 %s") % path
	file.store_string(JSON.stringify(spec, "  ") + "\n")
	file.close()
	return ""


# --- 配件(overlays.json,見 PetOverlays;座標空間固定 pivot = 相對腳底軸心) ---

const OVERLAY_KEY := "__overlays"
const ACCESSORY_FOLDER := ".imports"


## 目前的配件清單(部件字典的複本,格式見 PetOverlays 的說明)。
func accessories() -> Array:
	var spec: Variant = manifest.get(OVERLAY_KEY)
	return ((spec as Dictionary).get("overlays", []) as Array).duplicate(true) if spec is Dictionary and (spec as Dictionary).get("overlays") is Array else []


func set_accessories(list: Array) -> void:
	var spec: Dictionary = (manifest.get(OVERLAY_KEY) as Dictionary) if manifest.get(OVERLAY_KEY) is Dictionary else {}
	spec["space"] = "pivot"
	spec["overlays"] = list.duplicate(true)
	manifest[OVERLAY_KEY] = spec
	dirty = manifest.hash() != _saved_hash


## 把圖片複製進素材包給配件用(和匯入動作圖片同一個隱藏資料夾)。回傳相對路徑清單;失敗回空陣列。
func import_accessory_images(paths: Array) -> Array[String]:
	var result: Array[String] = []
	if not has_pack():
		return result
	for path: String in paths:
		var errors: Array[String] = []
		if _check_image(path, errors) == null:
			return [] as Array[String]
		var relative := _copy_into_pack(path, ACCESSORY_FOLDER)
		if relative == "":
			return [] as Array[String]
		result.append(relative)
	return result


## 存進 pack.json。成功回空字串,失敗回原因。
func save() -> String:
	var path := root.path_join("pack.json")
	if FileAccess.file_exists(path) and not _backed_up:
		if DirAccess.copy_absolute(path, path + ".bak") != OK:
			return "無法備份舊的 pack.json,已取消存檔"
		_backed_up = true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return tr("無法寫入 %s") % path
	file.store_string(JSON.stringify(_manifest_for_file(), "  ") + "\n")
	file.close()
	var overlay_error := _save_overlays(root)
	if overlay_error != "":
		return overlay_error
	dirty = false
	_saved_hash = manifest.hash()
	return ""


# --- 匯入圖片 / 精靈圖 ---

## 這個動作目前的幀清單(和 actions[動作] 一一對應的複本)。項目格式見 SpritePackLoader._apply_frame_overrides:
## 路徑字串、{"file", "pivot"?, "offset"?},或精靈圖切片 {"sheet", "rect", "pivot"?, "offset"?}。
## 動作已經在 pack.json 的 frames 裡就用那份(保留每一幀自己的設定),否則從掃到的檔案推出來。
func frame_refs(action: String) -> Array:
	var stored := _stored_refs(action)
	var refs: Array = []
	for i in frame_count(action):
		var ref_index := _ref_index(action, i)
		var ref: Variant = null
		if ref_index >= 0 and ref_index < stored.size():
			ref = stored[ref_index]
			if ref is Dictionary:
				ref = (ref as Dictionary).duplicate(true)
		else:
			ref = _plain_ref(frame_path(action, i))
		if ref != null:
			refs.append(ref)
	return refs


## 由幀路徑推出最單純的項目:切片是 {sheet, rect},其餘是相對路徑字串;有圖片處理(fx)的都要用字典帶著 fx。不在素材包資料夾裡的回 null。
func _plain_ref(path: String) -> Variant:
	if SpritePackLoader.is_virtual(path):
		var parsed := SpritePackLoader.parse_virtual(path)
		var relative_file := _relative(str(parsed.get("file", "")))
		if relative_file == "":
			return null
		var fx := str(parsed.get("fx", ""))
		if not SpritePackLoader.is_slice(path):
			return relative_file if fx == "" else {"file": relative_file, "fx": fx}
		var rect: Rect2i = parsed["rect"]
		var slice_ref := {"sheet": relative_file, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
		if fx != "":
			slice_ref["fx"] = fx
		return slice_ref
	var file_relative := _relative(path)
	return file_relative if file_relative != "" else null


## 複製用:項目加上這一幀「實際生效」的軸心/圖片偏移(含整個動作共用的值),貼到別的動作才會長得一樣。
func _ref_with_effective_settings(action: String, index: int) -> Variant:
	var ref: Variant = _plain_ref(frame_path(action, index))
	var stored := _stored_refs(action)
	var ref_index := _ref_index(action, index)
	if ref_index >= 0 and ref_index < stored.size():
		ref = stored[ref_index].duplicate(true) if stored[ref_index] is Dictionary else stored[ref_index]
	if ref == null:
		return null
	for setting: String in ["pivot", "offset"]:
		var effective: Variant = _effective_setting(setting, action, index)
		if effective is Vector2 and not (ref is Dictionary and (ref as Dictionary).has(setting)):
			ref = _with_setting(ref, setting, effective)
	return ref


## 把動作固定成 frames 清單:之後調換順序、刪幀、複製貼上都只改這份清單。舊版依檔名存的逐幀軸心/偏移(pivots / offsets 表的逐幀鍵)
## 會搬進各幀自己的項目(否則幀變成清單項目後,依檔名的鍵就對不上了)。已經固定過的動作只會把清單整理成和目前的幀一一對應。
func materialize(action: String) -> void:
	var refs := frame_refs(action)
	if not _has_stored_refs(action):
		for setting: String in ["pivot", "offset"]:
			var table_name := setting + "s"
			var table: Variant = manifest.get(table_name)
			if not table is Dictionary:
				continue
			for i in refs.size():
				# 載入器兩種逐幀鍵都認:"<動作>/<檔名>"(較優先)與單獨的檔名;檔名鍵若也適用於別的動作(整包不只這個動作有這個檔名)只讀不刪。
				var base := _base_of(frame_path(action, i))
				var shared := (_basename_actions.get(base, {}) as Dictionary).size() > 1
				for key: String in ["%s/%s" % [action, base], base]:
					var pair: Variant = (table as Dictionary).get(key)
					if pair is Array and pair.size() >= 2 and (pair[0] is float or pair[0] is int) and (pair[1] is float or pair[1] is int):
						refs[i] = _with_setting(refs[i], setting, Vector2(float(pair[0]), float(pair[1])))
						if not (shared and key == base):
							(table as Dictionary).erase(key)
						break
			if (table as Dictionary).is_empty():
				manifest.erase(table_name)
	_set_refs(action, refs)


## 寫回這個動作的 frames 清單並重新掃描。呼叫端要先 checkpoint()。
func _set_refs(action: String, refs: Array) -> void:
	var frames_table: Dictionary = manifest.get("frames", {}) if manifest.get("frames") is Dictionary else {}
	frames_table[action] = refs
	manifest["frames"] = frames_table
	_rebuild_actions()
	dirty = manifest.hash() != _saved_hash


func _sorted_indices(action: String, indices: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in indices:
		var i := int(value)
		if i >= 0 and i < frame_count(action) and not result.has(i):
			result.append(i)
	result.sort()
	return result


## 刪掉這些幀,可以刪到整個動作都沒有幀。成功回空字串。
## 刪光之後:精靈圖切片(引用共用圖檔,例如整張精靈圖切出來的素材包)這個動作就真的消失,不再出現在動作清單;
## 平放的圖檔或「動作資料夾」型的動作,幀清單設定清空後會退回照原本掃到的實體檔案顯示(檔案還在磁碟上,不會憑空消失)——
## 這種情況呼叫端(見 pack_editor_window.gd 的 all_frames_deleted())要另外提示可以用「清理未使用檔案」的「清除動作檔案」整個清掉。
func delete_frames(action: String, indices: Array) -> String:
	var picked := _sorted_indices(action, indices)
	if picked.is_empty():
		return "沒有選擇要刪除的幀"
	checkpoint()
	materialize(action)
	var refs := frame_refs(action)
	for i in range(picked.size() - 1, -1, -1):
		refs.remove_at(picked[i])
	_set_refs(action, refs)
	return ""


## 把這些幀原地複製一份,接在選取範圍最後一幀的後面。回傳新複製出來的幀的位置。
func duplicate_frames(action: String, indices: Array) -> Array[int]:
	var picked := _sorted_indices(action, indices)
	var created: Array[int] = []
	if picked.is_empty():
		return created
	checkpoint()
	materialize(action)
	var refs := frame_refs(action)
	var insert_at: int = picked[picked.size() - 1] + 1
	for i in picked.size():
		var ref: Variant = refs[picked[i]]
		refs.insert(insert_at + i, ref.duplicate(true) if ref is Dictionary else ref)
		created.append(insert_at + i)
	_set_refs(action, refs)
	return created


## 把選取的幀往前(delta = -1)或往後(+1)移一格,選取的幀之間的相對順序不變。回傳移動後的位置(已經在邊界就原樣回傳,不動也不存撤回點)。
func move_frames(action: String, indices: Array, delta: int) -> Array[int]:
	var picked := _sorted_indices(action, indices)
	if picked.is_empty() or delta == 0:
		return picked
	var count := frame_count(action)
	if (delta < 0 and picked[0] == 0) or (delta > 0 and picked[picked.size() - 1] == count - 1):
		return picked
	checkpoint()
	materialize(action)
	var refs := frame_refs(action)
	var moved: Array[int] = []
	if delta < 0:
		for i in picked:
			var swap: Variant = refs[i - 1]
			refs[i - 1] = refs[i]
			refs[i] = swap
			moved.append(i - 1)
	else:
		for k in range(picked.size() - 1, -1, -1):
			var i: int = picked[k]
			var swap: Variant = refs[i + 1]
			refs[i + 1] = refs[i]
			refs[i] = swap
			moved.append(i + 1)
		moved.reverse()
	_set_refs(action, refs)
	return moved


## 複製這些幀到剪貼簿(連同每一幀實際生效的軸心/圖片偏移)。剪貼簿只在同一個素材包裡有效。回傳複製了幾幀。
func copy_frames(action: String, indices: Array) -> int:
	clipboard.clear()
	for i in _sorted_indices(action, indices):
		var ref: Variant = _ref_with_effective_settings(action, i)
		if ref != null:
			clipboard.append(ref)
	return clipboard.size()


## 把剪貼簿的幀貼進動作:at_index = 要插入的位置(0 = 最前面),-1 或超過幀數 = 接在最後面。可以貼到別的動作,也可以貼回同一個動作。
## 動作還不存在(貼進空的動作槽)就用這個名字建立新動作。回傳貼進去的幀的位置(剪貼簿是空的回空陣列)。
func paste_frames(action: String, at_index := -1) -> Array[int]:
	var created: Array[int] = []
	if clipboard.is_empty() or (not actions.has(action) and (action == "" or SpritePackLoader.clean_action_name(action) != action)):
		return created
	checkpoint()
	if actions.has(action):
		materialize(action)
	var refs := frame_refs(action)
	var insert_at := refs.size() if at_index < 0 or at_index > refs.size() else at_index
	for i in clipboard.size():
		var ref: Variant = clipboard[i]
		refs.insert(insert_at + i, ref.duplicate(true) if ref is Dictionary else ref)
		created.append(insert_at + i)
	_set_refs(action, refs)
	return created


# --- 圖片處理(裁切 / 翻轉 / 旋轉,見 PackImageFx):寫在幀項目的 fx 欄位,不改原圖檔 ---

## 這一幀目前的圖片處理步驟(沒有回空陣列)。
func fx_ops(action: String, index: int) -> Array:
	var ops: Variant = PackImageFx.parse(str(SpritePackLoader.parse_virtual(frame_path(action, index)).get("fx", "")))
	return ops if ops is Array else []


## 這一幀的圖片處理文字(沒有回空字串)。
func fx_text(action: String, index: int) -> String:
	return PackImageFx.serialize(fx_ops(action, index))


## 對選取的幀各加一步圖片處理(op 見 PackImageFx:{op:"h"}、{op:"v"}、{op:"r", degrees}、{op:"c", rect})。
## 已經設定過的軸心會跟著換算,圖片偏移不動。全部檢查通過才會改(任何一幀不行就整個不做),成功回空字串。
func apply_fx(action: String, indices: Array, op: Dictionary) -> String:
	var picked := _sorted_indices(action, indices)
	if picked.is_empty():
		return "沒有選取的幀"
	var plans: Array = []
	for i in picked:
		var info := frame(action, i)
		if info.is_empty():
			return tr("第 %d 幀讀不出圖") % i
		var size: Vector2i = info["size"]
		var next_size := PackImageFx.size_after(size, op)
		if next_size.x < 1 or next_size.y < 1:
			return tr("第 %d 幀:裁切範圍在圖片之外") % i
		if next_size.x > PackImageFx.MAX_SIDE or next_size.y > PackImageFx.MAX_SIDE:
			return tr("第 %d 幀:處理後的圖太大(單邊超過 %d)") % [i, PackImageFx.MAX_SIDE]
		var merged: Variant = PackImageFx.with_op(fx_ops(action, i), op)
		if merged == null:
			return tr("第 %d 幀:圖片處理的步驟太多了(上限 %d 步),請先「還原圖片處理」") % [i, PackImageFx.MAX_OPS]
		var explicit: Variant = _effective_setting("pivot", action, i)
		var next_pivot: Variant = _clamp_pivot(PackImageFx.map_point(explicit, size, op), next_size) if explicit is Vector2 else null
		plans.append({"index": i, "fx": PackImageFx.serialize(merged as Array), "pivot": next_pivot})
	checkpoint()
	materialize(action)
	var refs := frame_refs(action)
	for plan: Dictionary in plans:
		var ref: Variant = refs[plan["index"]]
		var entry: Dictionary = {"file": ref} if ref is String else (ref as Dictionary).duplicate(true)
		if str(plan["fx"]) == "":
			entry.erase("fx")
		else:
			entry["fx"] = plan["fx"]
		if plan["pivot"] is Vector2:
			entry["pivot"] = [int((plan["pivot"] as Vector2).x), int((plan["pivot"] as Vector2).y)]
		refs[plan["index"]] = _normalize_ref(entry)
	_set_refs(action, refs)
	return ""


## 拿掉選取的幀的所有圖片處理(回到原圖)。這些幀手動設定過的軸心是相對處理後的圖,拿掉處理後就不對了,一併清掉(回到自動軸心)。回傳有幾幀被還原。
func clear_fx(action: String, indices: Array) -> int:
	var targets: Array[int] = []
	for i in _sorted_indices(action, indices):
		if fx_text(action, i) != "":
			targets.append(i)
	if targets.is_empty():
		return 0
	checkpoint()
	materialize(action)
	var refs := frame_refs(action)
	for i in targets:
		var ref: Variant = refs[i]
		if ref is Dictionary:
			var entry: Dictionary = (ref as Dictionary).duplicate(true)
			entry.erase("fx")
			entry.erase("pivot")
			refs[i] = _normalize_ref(entry)
	_set_refs(action, refs)
	return targets.size()


# --- 動作槽:系統動作(idle、walk…)與素材包裡的動作怎麼對應 ---

## 系統動作 → 目前素材包裡「填這個槽」的動作名稱(依素材包的自動別名與 pack.json 的 actions 對應算出來;沒有素材的槽不在裡面)。
func slot_sources() -> Dictionary:
	var result := {}
	for action in action_names():
		for animation_name: String in animation_names_of(action):
			if SpritePackLoader.ALIASES.has(animation_name) and not result.has(animation_name):
				result[animation_name] = action
	return result


# --- 動作對應(系統動作要用素材包裡哪個動作的素材;見 SpritePackLoader.ALIASES 與 docs/素材包格式.md 的 "actions") ---

## 給 UI 用的「明確不共用」記號(不會真的存成這個字串,set_action_source 存檔時轉成 false)。
const ACTION_SOURCE_NONE := "__none__"

## 這個系統動作槽(slot,ALIASES 的鍵)目前在 pack.json "actions" 裡的原始設定:
## null = 自動(依 ALIASES 的別名表找)、false = 明確不共用(不查別名,這個動作沒有素材,交給引擎原本的降級規則,例如 lay → sit → idle)、
## String = 手動指定要共用哪個(素材包裡真實存在的)動作的全部幀、Dictionary/Array = 進階設定(只取某幾幀、或多個隨機差分,這個編輯器只能整個取代,不能個別編輯)。
func action_override(slot: String) -> Variant:
	var configured: Dictionary = manifest.get("actions", {}) if manifest.get("actions") is Dictionary else {}
	return configured.get(slot)


## 設定系統動作槽的對應(source 的意思見 ACTION_SOURCE_NONE 的說明;"" = 清掉設定、改回自動)。呼叫端要先 checkpoint()。
func set_action_source(slot: String, source: String) -> void:
	var configured: Dictionary = manifest.get("actions", {}).duplicate(true) if manifest.get("actions") is Dictionary else {}
	if source == "":
		configured.erase(slot)
	elif source == ACTION_SOURCE_NONE:
		configured[slot] = false
	else:
		configured[slot] = source
	if configured.is_empty():
		manifest.erase("actions")
	else:
		manifest["actions"] = configured
	_rebuild_actions()
	dirty = manifest.hash() != _saved_hash


# --- 動作的播放速度(fps_by_action) ---

## 這個動作(素材包裡的名稱)對應的動畫基本名稱(fps_by_action 的鍵):例如來源動作 stand1 會播成 idle,速度要寫在 idle 底下。沒有對應就用動作自己的名字。
func animation_names_of(action: String) -> Array:
	var names: Array = _animations.get(action, [])
	return names if not names.is_empty() else [action]


## 目前生效的播放速度(fps)。
func fps_of(action: String) -> float:
	var table: Variant = manifest.get("fps_by_action")
	if table is Dictionary:
		for animation_name: String in animation_names_of(action):
			if (table as Dictionary).has(animation_name) and ((table as Dictionary)[animation_name] is float or (table as Dictionary)[animation_name] is int):
				return clampf(float((table as Dictionary)[animation_name]), 1.0, 60.0)
	var global_fps: Variant = manifest.get("fps")
	return clampf(float(global_fps), 1.0, 60.0) if global_fps is float or global_fps is int else SpritePackLoader.DEFAULT_FPS


## 設定這個動作的播放速度;和整包預設 fps 一樣就不特別記(清掉這個動作的設定)。
func set_fps(action: String, value: float) -> void:
	var clamped := clampf(roundf(value), 1.0, 60.0)
	var table: Dictionary = manifest.get("fps_by_action", {}) if manifest.get("fps_by_action") is Dictionary else {}
	var global_fps: Variant = manifest.get("fps")
	var default_fps := float(global_fps) if global_fps is float or global_fps is int else SpritePackLoader.DEFAULT_FPS
	for animation_name: String in animation_names_of(action):
		if clamped == default_fps:
			table.erase(animation_name)
		else:
			table[animation_name] = int(clamped)
	if table.is_empty():
		manifest.erase("fps_by_action")
	else:
		manifest["fps_by_action"] = table
	dirty = manifest.hash() != _saved_hash


# --- 動作的循環設定(loop_by_action,見 PackLoop) ---

## 這個動作目前的循環設定({} = 沒特別設定,整段循環)。
func loop_of(action: String) -> Dictionary:
	var table: Variant = manifest.get("loop_by_action")
	if table is Dictionary:
		for animation_name: String in animation_names_of(action):
			var entry := PackLoop.clean_entry((table as Dictionary).get(animation_name))
			if not entry.is_empty():
				return entry
	return {}


## 設定這個動作的循環方式(entry 見 PackLoop.clean_entry;空字典 = 清掉設定,回到整段循環)。
func set_loop(action: String, entry: Dictionary) -> void:
	var cleaned := PackLoop.clean_entry(entry)
	var table: Dictionary = manifest.get("loop_by_action", {}) if manifest.get("loop_by_action") is Dictionary else {}
	for animation_name: String in animation_names_of(action):
		if cleaned.is_empty():
			table.erase(animation_name)
		else:
			table[animation_name] = cleaned.duplicate()
	if table.is_empty():
		manifest.erase("loop_by_action")
	else:
		manifest["loop_by_action"] = table
	dirty = manifest.hash() != _saved_hash


# --- 匯出獨立圖檔 / 清理未使用的檔案 ---

## 把每個動作的每一幀存成獨立的 PNG(已套用精靈圖切片與每幀的裁切、翻轉、旋轉),檔名 <動作>_<編號>.png(編號 0 起算),
## 另外寫一份 frames.json:每個動作的播放速度與每一幀的檔名、軸心、圖片偏移,拿去別的工具或自己整理都方便。
## 目的資料夾不存在會建立;已經有同名檔案的會被蓋掉。回傳 {ok, error, count, folder}。
func export_frames(destination: String) -> Dictionary:
	var target := destination.strip_edges().replace("\\", "/").trim_suffix("/")
	if not has_pack():
		return {"ok": false, "error": "還沒有開啟素材包", "count": 0, "folder": target}
	if target == "":
		return {"ok": false, "error": "沒有選擇資料夾", "count": 0, "folder": target}
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return {"ok": false, "error": tr("無法建立資料夾:%s") % target, "count": 0, "folder": target}
	var listing := {"format": "slime_pet_frames", "actions": {}}
	var count := 0
	for action: String in action_names():
		var frames_list: Array = []
		for index in frame_count(action):
			var info := frame(action, index)
			if info.is_empty():
				continue
			var file_name := "%s_%d.png" % [action, index]
			if (info["image"] as Image).save_png(target.path_join(file_name)) != OK:
				return {"ok": false, "error": tr("無法寫入:%s") % file_name, "count": count, "folder": target}
			var pivot_value := pivot(action, index)
			var offset_value := offset(action, index)
			frames_list.append({"file": file_name, "pivot": [pivot_value.x, pivot_value.y], "offset": [offset_value.x, offset_value.y]})
			count += 1
		if not frames_list.is_empty():
			(listing["actions"] as Dictionary)[action] = {"fps": fps_of(action), "frames": frames_list}
	var file := FileAccess.open(target.path_join("frames.json"), FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "無法寫入 frames.json", "count": count, "folder": target}
	file.store_string(JSON.stringify(listing, "  ") + "\n")
	file.close()
	return {"ok": true, "error": "", "count": count, "folder": target}


## 素材包隱藏資料夾(.imports、.sheets)裡沒有被任何動作、精靈圖切片或配件用到的檔案(素材包內的相對路徑)。
## 判斷方式:這個檔案的相對路徑沒有出現在目前的 pack.json 內容(含幀清單、配件)或任何動作的幀路徑裡。
func unused_files() -> Array[String]:
	var result: Array[String] = []
	if not has_pack():
		return result
	var haystack := JSON.stringify(manifest)
	for action: String in action_names():
		for path: String in (actions[action] as Array):
			haystack += "\n" + path
	haystack = haystack.replace("\\", "/")
	for folder: String in [IMPORT_FOLDER, SHEET_FOLDER]:
		for relative in PetPackage._list_files(root.path_join(folder), ""):
			var full := folder + "/" + relative
			if not haystack.contains(full) and not haystack.contains(root.path_join(full)):
				result.append(full)
	return result


## 哪些動作可以整個清掉自己的實體檔案(至少有一個檔案是這個動作獨有,沒有被別的動作或配件一起用到)。
func actions_with_own_files() -> Array[String]:
	var result: Array[String] = []
	for action_name in action_names():
		if not own_files_of(action_name).is_empty():
			result.append(action_name)
	return result


## 這個動作目前用到、而且「只有這個動作在用」的實體檔案(素材包內的相對路徑;精靈圖切片算它切自的那張圖)。
## 同一張圖被別的動作也切、或複製貼上到別的動作共用同一張圖,都不算獨有,不會列進來(不會誤刪別人還在用的圖)。
func own_files_of(action_name: String) -> Array[String]:
	var mine: Array[String] = []
	for path: Variant in actions.get(action_name, []):
		var relative := _relative(_raw_file_of(str(path)))
		if relative != "" and not mine.has(relative):
			mine.append(relative)
	if mine.is_empty():
		return mine
	# 這個動作自己在 manifest 裡的 frames 項目不算「別人在用」,要先拿掉再比對。
	var manifest_without_action: Dictionary = manifest.duplicate(true)
	if manifest_without_action.get("frames") is Dictionary:
		(manifest_without_action["frames"] as Dictionary).erase(action_name)
	var haystack := JSON.stringify(manifest_without_action).replace("\\", "/")
	for other_name in action_names():
		if other_name == action_name:
			continue
		for path: String in (actions[other_name] as Array):
			haystack += "\n" + path.replace("\\", "/")
	return mine.filter(func(relative: String) -> bool: return not haystack.contains(relative) and not haystack.contains(root.path_join(relative)))


## 一幀的路徑背後真正的圖檔(整張圖的虛擬路徑、精靈圖切片的虛擬路徑,或本來就是平放的相對/絕對路徑)。
static func _raw_file_of(path: String) -> String:
	if SpritePackLoader.is_virtual(path):
		return str(SpritePackLoader.parse_virtual(path).get("file", ""))
	return path


## 整個清掉一個動作:清空它的幀清單設定(之後 action_names() 就不會再列出它),並把它獨佔的實體檔案搬到備份資料夾(不直接刪)。
## 精靈圖切片(可能跟別的動作共用同一張圖)不適用,回傳原因;檔案搬移中途失敗會停在那裡(已經清掉的幀清單設定不會復原,呼叫端可以用撤回)。
func clear_action_files(action_name: String) -> Dictionary:
	if not actions.has(action_name):
		return {"ok": false, "error": "找不到這個動作", "moved": 0, "backup": ""}
	if not actions_with_own_files().has(action_name):
		return {"ok": false, "error": "這個動作用到的檔案都被別的動作或配件共用,沒有它獨有、可以搬走的圖(共用的圖沒人用時,「清理未使用檔案」會抓到)", "moved": 0, "backup": ""}
	var files := own_files_of(action_name)
	checkpoint()
	_set_refs(action_name, [])
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	var backup := SpriteLibrary.backup_root_dir().path_join("%s_動作_%s_%s" % [root.get_file(), action_name, stamp])
	var moved := 0
	for relative in files:
		var source := root.path_join(relative)
		if not FileAccess.file_exists(source):
			continue
		var target := backup.path_join(relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if DirAccess.rename_absolute(source, target) == OK:
			moved += 1
	return {"ok": true, "error": "", "moved": moved, "backup": backup}


## 把未使用的檔案搬到 user://backup/<素材包名>_未使用_<時間>/(不直接刪),回傳 {moved, backup, error}。
func remove_unused_files() -> Dictionary:
	var list := unused_files()
	if list.is_empty():
		return {"moved": 0, "backup": "", "error": ""}
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	var backup := SpriteLibrary.backup_root_dir().path_join("%s_unused_%s" % [root.get_file(), stamp])
	var moved := 0
	for relative in list:
		var target := backup.path_join(relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if DirAccess.rename_absolute(root.path_join(relative), target) == OK:
			moved += 1
		else:
			return {"moved": moved, "backup": backup, "error": tr("無法搬移:%s") % relative}
	return {"moved": moved, "backup": backup, "error": ""}


# --- 換精靈圖 / 另存新素材包(把設定好的素材包當範本,換一張圖就完成新角色的綁定) ---

## 目前被 frames 清單引用的精靈圖(素材包內的相對路徑)。
func sheets_in_use() -> Array[String]:
	var found: Array[String] = []
	var frames_table: Variant = manifest.get("frames")
	if frames_table is Dictionary:
		for action_key: Variant in frames_table:
			if not frames_table[action_key] is Array:
				continue
			for ref: Variant in frames_table[action_key]:
				if ref is Dictionary and (ref as Dictionary).get("sheet") is String and not found.has(ref["sheet"]):
					found.append(ref["sheet"])
	return found


## 用新的圖取代一張正在使用的精靈圖:所有引用它的切片範圍、每一幀的軸心/圖片偏移、動作與播放速度都原封不動,只有圖換了。
## 新圖的尺寸必須和舊圖一樣(格線才對得上);尺寸不同回錯誤原因。舊圖檔不會被刪。成功回空字串。
func replace_sheet(old_relative: String, new_source: String) -> String:
	if not sheets_in_use().has(old_relative):
		return tr("這張精靈圖沒有被任何動作使用:%s") % old_relative
	var errors: Array[String] = []
	var new_image := _check_image(new_source, errors)
	if new_image == null:
		return errors[0]
	var report: Array[String] = []
	var old_image := SpritePackLoader.load_frame_image(root.path_join(old_relative), report)
	if old_image == null:
		return tr("讀不出原本的精靈圖:%s") % old_relative
	if old_image.get_size() != new_image.get_size():
		return tr("新圖的尺寸和原本的精靈圖不同(原本 %d×%d,新圖 %d×%d),切片範圍會對不上;請把新圖排成和原本一樣的尺寸與格線。") % [old_image.get_width(), old_image.get_height(), new_image.get_width(), new_image.get_height()]
	var new_relative := _copy_into_pack(new_source, SHEET_FOLDER)
	if new_relative == "":
		return tr("無法複製新圖進素材包:%s") % new_source.get_file()
	checkpoint()
	var frames_table: Dictionary = manifest["frames"]
	for action_key: Variant in frames_table:
		if frames_table[action_key] is Array:
			for ref: Variant in frames_table[action_key]:
				if ref is Dictionary and (ref as Dictionary).get("sheet") == old_relative:
					ref["sheet"] = new_relative
	SpritePackLoader.clear_sheet_cache()
	_frames.clear()
	_rebuild_actions()
	dirty = manifest.hash() != _saved_hash
	return ""


## 另存成新的素材包資料夾:把整個素材包(含目前還沒存檔的編輯)複製過去,之後編輯的就是新資料夾。目的資料夾必須不存在或是空的,而且不能在現在這個素材包裡面。
## 用來把設定好的素材包當範本:另存 → 換精靈圖 → 新角色。成功回空字串。
func save_as(destination: String) -> String:
	if not has_pack():
		return "還沒有開啟素材包"
	var target := destination.strip_edges().replace("\\", "/").trim_suffix("/")
	if target == "":
		return "沒有選擇資料夾"
	if target == root or target.begins_with(root + "/"):
		return "新資料夾不能是目前素材包本身或它的子資料夾"
	if DirAccess.dir_exists_absolute(target):
		var existing := DirAccess.open(target)
		if existing != null and (not existing.get_files().is_empty() or not existing.get_directories().is_empty()):
			return tr("目的資料夾必須是空的:%s") % target
	elif DirAccess.make_dir_recursive_absolute(target) != OK:
		return tr("無法建立資料夾:%s") % target
	var copy_error := _copy_tree(root, target)
	if copy_error != "":
		return copy_error
	var file := FileAccess.open(target.path_join("pack.json"), FileAccess.WRITE)
	if file == null:
		return "無法寫入新資料夾的 pack.json"
	file.store_string(JSON.stringify(_manifest_for_file(), "  ") + "\n")
	file.close()
	var overlay_copy_error := _save_overlays(target)
	if overlay_copy_error != "":
		return overlay_copy_error
	root = target
	SpritePackLoader.clear_sheet_cache()
	_frames.clear()
	_rebuild_actions()
	_saved_hash = manifest.hash()
	dirty = false
	_backed_up = false
	return ""


## 遞迴複製資料夾(略過 .bak 備份檔)。成功回空字串。
func _copy_tree(from: String, to: String) -> String:
	return SpriteLibrary.copy_tree(from, to)


func _relative(path: String) -> String:
	var prefix := root + "/"
	var normalized := path.replace("\\", "/")
	return normalized.trim_prefix(prefix) if normalized.begins_with(prefix) else ""


## 檢查一張要匯入的圖讀得出來(格式、大小);回傳 Image,失敗回 null 並把原因放進 errors。
func _check_image(path: String, errors: Array[String]) -> Image:
	if not SpritePackLoader.IMAGE_EXTENSIONS.has(path.get_extension().to_lower()):
		errors.append(tr("不支援的檔案格式:%s(支援 png / jpg / webp)") % path.get_file())
		return null
	var report: Array[String] = []
	var image := SpritePackLoader.load_frame_image(path, report)
	if image == null:
		errors.append(tr("讀不出圖片:%s") % path.get_file())
		return null
	if image.get_width() > SpritePackLoader.MAX_SIDE or image.get_height() > SpritePackLoader.MAX_SIDE:
		errors.append(tr("圖片太大(單邊超過 %d):%s") % [SpritePackLoader.MAX_SIDE, path.get_file()])
		return null
	return image


## 把檔案複製進素材包的子資料夾,檔名衝突就加序號;回傳素材包內的相對路徑,失敗回空字串。
func _copy_into_pack(source: String, subfolder: String) -> String:
	var folder := root.path_join(subfolder)
	if DirAccess.make_dir_recursive_absolute(folder) != OK and not DirAccess.dir_exists_absolute(folder):
		return ""
	var base := source.get_file().get_basename().replace(" ", "_")
	var extension := source.get_extension().to_lower()
	var target := folder.path_join("%s.%s" % [base, extension])
	var counter := 2
	while FileAccess.file_exists(target):
		target = folder.path_join("%s_%d.%s" % [base, counter, extension])
		counter += 1
	if DirAccess.copy_absolute(source, target) != OK:
		return ""
	return _relative(target)


## 匯入一張或多張圖片,當成一個動作的幀(單張圖 = 單幀動作)。mode:"replace" 覆蓋這個動作原本的幀、"append" 接在原本的幀後面。
## 動作不存在時兩種一樣。成功回空字串,失敗回原因(失敗時什麼都不會改)。
func import_images(paths: Array, action_name: String, mode: String) -> String:
	if not has_pack():
		return "還沒有開啟素材包"
	var clean_name := SpritePackLoader.clean_action_name(action_name)
	if clean_name == "":
		return "動作名稱不能是空的"
	if paths.is_empty():
		return "沒有選擇圖片"
	if paths.size() > MAX_IMPORT_FRAMES:
		return tr("一次最多匯入 %d 張圖") % MAX_IMPORT_FRAMES
	var errors: Array[String] = []
	for path: String in paths:
		if _check_image(path, errors) == null:
			return errors[0]
	var new_refs: Array = []
	for path: String in paths:
		var relative := _copy_into_pack(path, IMPORT_FOLDER)
		if relative == "":
			return tr("無法複製檔案進素材包:%s") % path.get_file()
		new_refs.append(relative)
	_apply_frame_refs(clean_name, new_refs, mode)
	return ""


## 精靈圖的格線切片。grid:{cols, rows} 或 {cell: Vector2i};邊距 margin、間距 spacing(Vector2i);skip_empty 略過全透明的格子;count > 0 只取前 count 個。
## 回傳依「由左到右、由上到下」排好的切片範圍;算不出來回空陣列。image 給 skip_empty 檢查透明用。
static func sheet_rects(size: Vector2i, grid: Dictionary, image: Image = null) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var margin: Vector2i = grid.get("margin", Vector2i.ZERO)
	var spacing: Vector2i = grid.get("spacing", Vector2i.ZERO)
	var cell: Vector2i = grid.get("cell", Vector2i.ZERO)
	var cols := int(grid.get("cols", 0))
	var rows := int(grid.get("rows", 0))
	var usable := size - margin * 2
	if cell.x > 0 and cell.y > 0:
		cols = (usable.x + spacing.x) / (cell.x + spacing.x)
		rows = (usable.y + spacing.y) / (cell.y + spacing.y)
	elif cols > 0 and rows > 0:
		cell = Vector2i((usable.x - spacing.x * (cols - 1)) / cols, (usable.y - spacing.y * (rows - 1)) / rows)
	if cell.x < 1 or cell.y < 1 or cols < 1 or rows < 1:
		return rects
	var limit := int(grid.get("count", 0))
	var skip_empty := bool(grid.get("skip_empty", false)) and image != null
	for row in rows:
		for column in cols:
			var rect := Rect2i(margin.x + column * (cell.x + spacing.x), margin.y + row * (cell.y + spacing.y), cell.x, cell.y)
			if not Rect2i(Vector2i.ZERO, size).encloses(rect):
				continue
			if skip_empty and image.get_region(rect).is_invisible():
				continue
			rects.append(rect)
			if rects.size() >= MAX_IMPORT_FRAMES or (limit > 0 and rects.size() >= limit):
				return rects
	return rects


## 匯入精靈圖:依 grid(見 sheet_rects)切成切片當一個動作的幀。切片只是「引用精靈圖的區域」,不複製像素、不產生多個檔案;
## 精靈圖本身複製進素材包的 sheets/。mode 同 import_images。成功回空字串,失敗回原因(失敗時什麼都不會改)。
func import_sheet(path: String, grid: Dictionary, action_name: String, mode: String) -> String:
	if not has_pack():
		return "還沒有開啟素材包"
	var clean_name := SpritePackLoader.clean_action_name(action_name)
	if clean_name == "":
		return "動作名稱不能是空的"
	var errors: Array[String] = []
	var image := _check_image(path, errors)
	if image == null:
		return errors[0]
	var rects := sheet_rects(Vector2i(image.get_width(), image.get_height()), grid, image)
	if rects.is_empty():
		return "用這組格線切不出任何切片(檢查欄列數、邊距與間距)"
	var relative := _copy_into_pack(path, SHEET_FOLDER)
	if relative == "":
		return tr("無法複製精靈圖進素材包:%s") % path.get_file()
	var new_refs: Array = []
	for rect in rects:
		new_refs.append({"sheet": relative, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	_apply_frame_refs(clean_name, new_refs, mode)
	return ""


## 把新的幀清單寫進 pack.json 的 "frames"。覆蓋時要先清掉這個動作底下依「幀序號/檔名」存的軸心與圖片偏移(換了幀,舊的值不再對得上)。
func _apply_frame_refs(action_name: String, new_refs: Array, mode: String) -> void:
	checkpoint()
	var refs: Array = new_refs
	if actions.has(action_name):
		if mode == "append":
			# 先固定成 frames 清單(舊版依檔名存的逐幀設定搬進各幀項目),不然接上新幀後檔名鍵就對不上了
			materialize(action_name)
			refs = frame_refs(action_name) + new_refs
		else:
			for table_name: String in ["pivots", "offsets"]:
				var table: Variant = manifest.get(table_name)
				if table is Dictionary:
					_erase_action_keys(table, action_name)
					if (table as Dictionary).is_empty():
						manifest.erase(table_name)
	var frames_table: Dictionary = manifest.get("frames", {}) if manifest.get("frames") is Dictionary else {}
	frames_table[action_name] = refs
	manifest["frames"] = frames_table
	_rebuild_actions()
	dirty = manifest.hash() != _saved_hash


# --- 判定框(hitbox) ---

## 沒有設定判定框時的預設大小:待機動作第一幀的本體(圖寬 × 腳底線以上的高度),偏移 0。
func default_hitbox() -> Dictionary:
	var idle_action := ""
	for alias: String in SpritePackLoader.ALIASES["idle"]:
		for action: String in actions:
			if action.to_lower() == alias:
				idle_action = action
				break
		if idle_action != "":
			break
	if idle_action == "" and not actions.is_empty():
		idle_action = str(actions.keys()[0])
	var info := frame(idle_action, 0) if idle_action != "" and frame_count(idle_action) > 0 else {}
	if info.is_empty():
		return {"size": Vector2(64, 64), "offset": Vector2.ZERO}
	var image_size: Vector2i = info["size"]
	var foot: Vector2 = pivot(idle_action, 0)
	return {"size": Vector2(float(image_size.x), minf(foot.y, float(image_size.y))), "offset": Vector2.ZERO}


## 目前生效的判定框 {size, offset, explicit}(explicit = pack.json 有明確設定)。單位是縮放前的像素,錨點是腳底線的中心點。
func hitbox() -> Dictionary:
	var size_value: Variant = manifest.get("hitbox")
	if size_value is Array and size_value.size() >= 2 and (size_value[0] is float or size_value[0] is int) and (size_value[1] is float or size_value[1] is int) and float(size_value[0]) > 0.0 and float(size_value[1]) > 0.0:
		var offset_value: Variant = manifest.get("hitbox_offset")
		var box_offset := Vector2.ZERO
		if offset_value is Array and offset_value.size() >= 2 and (offset_value[0] is float or offset_value[0] is int) and (offset_value[1] is float or offset_value[1] is int):
			box_offset = Vector2(float(offset_value[0]), float(offset_value[1]))
		return {"size": Vector2(float(size_value[0]), float(size_value[1])), "offset": box_offset, "explicit": true}
	var fallback := default_hitbox()
	fallback["explicit"] = false
	return fallback


func set_hitbox(box_size: Vector2, box_offset: Vector2) -> void:
	var clamped_size := Vector2(roundf(clampf(box_size.x, 1.0, MAX_HITBOX)), roundf(clampf(box_size.y, 1.0, MAX_HITBOX)))
	var clamped_offset := Vector2(roundf(clampf(box_offset.x, -MAX_HITBOX, MAX_HITBOX)), roundf(clampf(box_offset.y, -MAX_HITBOX, MAX_HITBOX)))
	manifest["hitbox"] = [int(clamped_size.x), int(clamped_size.y)]
	if clamped_offset == Vector2.ZERO:
		manifest.erase("hitbox_offset")
	else:
		manifest["hitbox_offset"] = [int(clamped_offset.x), int(clamped_offset.y)]
	dirty = manifest.hash() != _saved_hash


## 清除判定框設定,回到自動(素材包沒設就用待機幀本體大小)。
func clear_hitbox() -> void:
	manifest.erase("hitbox")
	manifest.erase("hitbox_offset")
	dirty = manifest.hash() != _saved_hash


# --- 光源(lights;見 PackLights) ---

## 目前 pack.json 的光源清單(已整理過)。
func lights() -> Array[Dictionary]:
	return PackLights.clean(manifest.get("lights"))


## 寫回光源清單(整理後;空的就從 pack.json 拿掉)。
func set_lights(list: Array) -> void:
	var cleaned := PackLights.clean(list)
	if cleaned.is_empty():
		manifest.erase("lights")
	else:
		manifest["lights"] = cleaned
	dirty = manifest.hash() != _saved_hash


## 持有錨點(桌寵手拿道具的位置,pack.json 的 hold_anchor):Vector2 或 null(沒設 = 用預設位置)。
func hold_anchor() -> Variant:
	return PackLights.anchor_of(manifest.get("hold_anchor"))


func set_hold_anchor(value: Variant) -> void:
	if value is Vector2:
		manifest["hold_anchor"] = [roundf((value as Vector2).x), roundf((value as Vector2).y)]
	else:
		manifest.erase("hold_anchor")
	dirty = manifest.hash() != _saved_hash


# --- 內部 ---

func _clamp_pivot(value: Vector2, size: Vector2i) -> Vector2:
	return Vector2(roundf(clampf(value.x, 0.0, float(size.x))), roundf(clampf(value.y, 0.0, float(size.y))))


func _clamp_offset(value: Vector2) -> Vector2:
	return Vector2(roundf(clampf(value.x, -MAX_OFFSET, MAX_OFFSET)), roundf(clampf(value.y, -MAX_OFFSET, MAX_OFFSET)))


## 用載入器同一套查找順序(動作/檔名 > 檔名 > 動作名)讀 pack.json 的明確值;沒有(或格式不對)回 null。
func _explicit(table: Variant, action: String, index: int) -> Variant:
	if not table is Dictionary:
		return null
	var value: Variant = SpritePackLoader.lookup_frame_key(table, frame_path(action, index), action)
	if value is Array and value.size() >= 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2(float(value[0]), float(value[1]))
	return null


## 逐幀寫入 pivots / offsets 表用的鍵:frames 清單裡的幀一律是 "<動作名>/<序號>";一般掃到的檔案,檔名在整包只出現在這個動作就直接用檔名,否則(動作資料夾式素材包的 0、1、2…)用 "<動作名>/<檔名>"。
func _frame_key(action: String, index: int) -> String:
	var path := frame_path(action, index)
	var base := _base_of(path)
	if SpritePackLoader.is_virtual(path):
		return "%s/%s" % [action, base]
	return base if (_basename_actions.get(base, {}) as Dictionary).size() <= 1 else "%s/%s" % [action, base]


func _erase_action_keys(table: Dictionary, action: String) -> void:
	table.erase(action)
	for i in frame_count(action):
		table.erase(_frame_key(action, i))


## 寫入一個軸心 / 圖片偏移。setting = "pivot" 或 "offset"。
## whole_action:寫成整個動作共用的值(並清掉這個動作底下逐幀的舊值,包含 frames 清單裡幀自己的設定)。
## 逐幀:這一幀在 frames 清單裡就寫在它自己的項目上(跟著幀走,調換順序、複製貼上都不會對不上),否則寫進 pivots / offsets 表的逐幀鍵。
func _write(setting: String, action: String, index: int, value: Vector2, whole_action: bool) -> void:
	var table_name := setting + "s"
	var table: Dictionary = manifest.get(table_name, {}) if manifest.get(table_name) is Dictionary else {}
	var stored: Array = [int(value.x), int(value.y)]
	if whole_action:
		_erase_action_keys(table, action)
		_clear_ref_setting(action, -1, setting)
		# 圖片偏移 (0, 0) 就是預設,不必寫進檔案
		if not (setting == "offset" and value == Vector2.ZERO):
			table[action] = stored
	else:
		var inherited: Variant = table.get(action)
		# 逐幀的值和「沒指定時本來的值」一樣就不留(避免檔案塞滿等於預設的資料);整個動作有指定時要留,才蓋得過它。
		var is_default: bool = (value == Vector2.ZERO) if setting == "offset" else (value == frame(action, index)["auto_pivot"])
		var ref_index := _ref_index(action, index)
		if ref_index >= 0 and _has_stored_refs(action):
			var refs := _stored_refs(action)
			table.erase(_frame_key(action, index))
			if is_default and inherited == null:
				if refs[ref_index] is Dictionary:
					refs[ref_index] = _normalize_ref(_without_key(refs[ref_index], setting))
			else:
				refs[ref_index] = _with_setting(refs[ref_index], setting, value)
		else:
			var key := _frame_key(action, index)
			if is_default and inherited == null:
				table.erase(key)
			else:
				table[key] = stored
	if table.is_empty():
		manifest.erase(table_name)
	else:
		manifest[table_name] = table
	dirty = manifest.hash() != _saved_hash