class_name CharacterThumbnail
extends RefCounted
## 角色庫用的縮圖與摘要:取角色的 idle 第一幀,切掉四周全透明的邊,**整體置中**縮進統一大小的方格(所有角色的縮圖一樣大)。
## 縮圖存在 user://thumbs/,素材包(pack.json 或那一幀的圖檔)沒改就直接讀快取。縮圖與摘要都不會改動素材包。
## 演算法備忘見 docs/角色庫規劃.md。

const CELL := 96
## 縮圖四周留白(像素)。
const PADDING := 6
## 放大(圖比方格小)時最多整數倍放大幾倍,並用最近點取樣保持像素風。
const MAX_UPSCALE := 4
const CACHE_DIR := "user://thumbs/"


## 挑出代表這個角色的動作:idle,沒有就依別名(stand、wait…,大小寫不分),再沒有就是名字排序最前面的動作。回傳動作名稱(素材包裡的名稱);沒有動作回空字串。
static func pick_action(actions: Dictionary) -> String:
	if actions.is_empty():
		return ""
	var lowered := {}
	for action_name: String in actions:
		lowered[action_name.to_lower()] = action_name
	for alias: String in SpritePackLoader.ALIASES["idle"]:
		if lowered.has(alias):
			return str(lowered[alias])
	var names: Array = actions.keys()
	names.sort()
	return str(names[0])


## 素材包摘要:{ok, folder, name(角色顯示名稱), actions(動作數), frames(總幀數), action(代表動作), frame_path(第一幀的路徑), error}。
static func summarize(folder: String) -> Dictionary:
	var inspected := SpritePackLoader.inspect_pack(folder)
	var base_name := folder.replace("\\", "/").trim_suffix("/").get_file()
	if not bool(inspected["ok"]):
		return {"ok": false, "folder": folder, "name": base_name, "actions": 0, "frames": 0, "action": "", "frame_path": "", "error": str((inspected["report"] as Array)[0])}
	var actions: Dictionary = inspected["actions"]
	var frames := 0
	for action_name: String in actions:
		frames += (actions[action_name] as Array).size()
	var action := pick_action(actions)
	var frame_path := str((actions[action] as Array)[0]) if action != "" and not (actions[action] as Array).is_empty() else ""
	var manifest: Dictionary = inspected["manifest"]
	var display := str(manifest.get("name", "")).strip_edges()
	return {"ok": true, "folder": folder, "name": display if display != "" else base_name, "actions": actions.size(), "frames": frames, "action": action, "frame_path": frame_path, "error": ""}


## 把一張圖做成統一大小的縮圖(純函式,方便測試):切掉全透明的邊 → 依比例縮進 cell 方格(留白 PADDING)→ 整體置中。
## 放得下就整數倍放大(最多 MAX_UPSCALE,最近點),放不下才縮小(高品質縮小)。全透明的圖回傳空白方格。
static func render(source: Image, cell := CELL) -> Image:
	var canvas := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	var image := source.duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	var used := image.get_used_rect()
	if used.size.x < 1 or used.size.y < 1:
		return canvas
	var part := image.get_region(used)
	var room := float(cell - PADDING * 2)
	var scale := minf(room / float(part.get_width()), room / float(part.get_height()))
	if scale >= 1.0:
		var factor := mini(int(floorf(scale)), MAX_UPSCALE)
		if factor > 1:
			part.resize(part.get_width() * factor, part.get_height() * factor, Image.INTERPOLATE_NEAREST)
	else:
		part.resize(maxi(int(roundf(part.get_width() * scale)), 1), maxi(int(roundf(part.get_height() * scale)), 1), Image.INTERPOLATE_LANCZOS)
	var offset := Vector2i((cell - part.get_width()) / 2, (cell - part.get_height()) / 2)
	canvas.blend_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), offset)
	return canvas


## 這個素材包的縮圖(ImageTexture)。有快取且沒過期就讀快取;讀不出圖回 null。summary 是 summarize() 的結果(省得再掃一次)。
static func texture_for(summary: Dictionary) -> ImageTexture:
	if not bool(summary.get("ok", false)) or str(summary.get("frame_path", "")) == "":
		return null
	var folder := str(summary["folder"])
	var cache_name := _cache_name(folder)
	var stamp := _stamp(folder, str(summary["frame_path"]))
	var image_path := CACHE_DIR + cache_name + ".png"
	var stamp_path := CACHE_DIR + cache_name + ".stamp"
	if FileAccess.file_exists(image_path) and FileAccess.file_exists(stamp_path) and FileAccess.get_file_as_string(stamp_path) == stamp:
		var cached := Image.load_from_file(image_path)
		if cached != null and not cached.is_empty() and cached.get_width() == CELL and cached.get_height() == CELL:
			return ImageTexture.create_from_image(cached)
	var report: Array[String] = []
	var frame := SpritePackLoader.load_frame_image(str(summary["frame_path"]), report)
	if frame == null:
		return null
	var thumbnail := render(frame)
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	thumbnail.save_png(image_path)
	var stamp_file := FileAccess.open(stamp_path, FileAccess.WRITE)
	if stamp_file != null:
		stamp_file.store_string(stamp)
		stamp_file.close()
	return ImageTexture.create_from_image(thumbnail)


## 快取檔名:資料夾名 + 完整路徑的雜湊(不同位置的同名資料夾不會互相蓋掉)。
static func _cache_name(folder: String) -> String:
	var normalized := folder.replace("\\", "/").trim_suffix("/")
	return "%s_%s" % [normalized.get_file().validate_filename().left(40), str(normalized.hash())]


## 快取是否過期的依據:pack.json 與代表那一幀的圖檔的修改時間和大小。
static func _stamp(folder: String, frame_path: String) -> String:
	var manifest_path := folder.replace("\\", "/").trim_suffix("/") + "/pack.json"
	var file_path := frame_path.get_slice("|", 0)
	return "v1|%d|%d|%d|%s" % [FileAccess.get_modified_time(manifest_path) if FileAccess.file_exists(manifest_path) else 0,
			FileAccess.get_modified_time(file_path) if FileAccess.file_exists(file_path) else 0,
			FileAccess.get_size(file_path) if FileAccess.file_exists(file_path) else 0, frame_path.get_slice("|", 1) + frame_path.get_slice("|", 3)]
