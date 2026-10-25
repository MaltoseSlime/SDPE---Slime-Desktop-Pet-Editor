class_name PaintPalette
extends RefCounted
## 繪圖功能的色票(一組有名字的顏色,每個色塊也可以有自己的名字),存成 GIMP Palette(.gpl)檔:
## 放在 user://paint_palettes/,也能匯出 / 匯入給別的繪圖軟體用。有半透明顏色時照 Aseprite 的擴充寫法
## 加一行「Channels: RGBA」、每色四個數字;匯入兩種都認(沒有 Channels 的就是不透明的三個數字)。

const FOLDER := "user://paint_palettes"
const MAX_SWATCHES := 256
const DEFAULT_NAME := "預設"
## GIMP 沒取名的色塊慣例寫 Untitled,讀進來當作沒有名字。
const UNTITLED := "Untitled"

var name := ""
## [{color: Color, name: String}]
var swatches: Array[Dictionary] = []


func add(color: Color, swatch_name := "") -> bool:
	if swatches.size() >= MAX_SWATCHES:
		return false
	swatches.append({"color": color, "name": swatch_name})
	return true


func duplicate_palette() -> PaintPalette:
	var copy := PaintPalette.new()
	copy.name = name
	for swatch: Dictionary in swatches:
		copy.swatches.append(swatch.duplicate())
	return copy


func same_as(other: PaintPalette) -> bool:
	if other == null or other.swatches.size() != swatches.size():
		return false
	for i in swatches.size():
		if (swatches[i]["color"] as Color).to_rgba32() != (other.swatches[i]["color"] as Color).to_rgba32() or str(swatches[i]["name"]) != str(other.swatches[i]["name"]):
			return false
	return true


func to_gpl() -> String:
	var rgba := swatches.any(func(s: Dictionary) -> bool: return (s["color"] as Color).a8 < 255)
	var lines: PackedStringArray = ["GIMP Palette"]
	if rgba:
		lines.append("Channels: RGBA")
	lines.append("Name: %s" % name)
	lines.append("Columns: 8")
	lines.append("#")
	for swatch: Dictionary in swatches:
		var color: Color = swatch["color"]
		var label := str(swatch["name"]).strip_edges().replace("\n", " ")
		if label == "":
			label = UNTITLED
		if rgba:
			lines.append("%3d %3d %3d %3d\t%s" % [color.r8, color.g8, color.b8, color.a8, label])
		else:
			lines.append("%3d %3d %3d\t%s" % [color.r8, color.g8, color.b8, label])
	return "\n".join(lines) + "\n"


## 讀 .gpl 文字。不是色票檔回 null。檔案裡沒寫名字就用 fallback_name。
static func from_gpl(text: String, fallback_name := "") -> PaintPalette:
	var lines := text.replace("\r", "").split("\n")
	if lines.is_empty() or not lines[0].strip_edges().begins_with("GIMP Palette"):
		return null
	var palette := PaintPalette.new()
	palette.name = fallback_name
	var channels := 3
	for k in range(1, lines.size()):
		var line := lines[k].strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("Name:"):
			var named := line.substr(5).strip_edges()
			if named != "":
				palette.name = named
			continue
		if line.begins_with("Columns:"):
			continue
		if line.begins_with("Channels:"):
			channels = 4 if line.substr(9).strip_edges().to_upper() == "RGBA" else 3
			continue
		var parts := line.replace("\t", " ").split(" ", false)
		if parts.size() < channels or not parts[0].is_valid_int():
			continue
		var values: Array[int] = []
		for c in channels:
			if not parts[c].is_valid_int():
				values.clear()
				break
			values.append(clampi(parts[c].to_int(), 0, 255))
		if values.is_empty():
			continue
		var label := " ".join(parts.slice(channels)).strip_edges()
		if label == UNTITLED:
			label = ""
		palette.add(Color.from_rgba8(values[0], values[1], values[2], values[3] if channels == 4 else 255), label)
	return palette


# --- 色票庫(user://paint_palettes) ---

static func _file_for(palette_name: String) -> String:
	var stem := palette_name.strip_edges().validate_filename()
	return FOLDER.path_join((stem if stem != "" else "palette") + ".gpl")


## 色票庫裡全部色票的名字(照名字排)。一個都沒有時先建立預設色票。
static func list_names() -> Array[String]:
	ensure_default()
	var names: Array[String] = []
	for file in DirAccess.get_files_at(FOLDER):
		if file.get_extension().to_lower() != "gpl":
			continue
		var palette := from_gpl(FileAccess.get_file_as_string(FOLDER.path_join(file)), file.get_basename())
		if palette != null and not names.has(palette.name):
			names.append(palette.name)
	names.sort()
	return names


static func exists(palette_name: String) -> bool:
	return FileAccess.file_exists(_file_for(palette_name))


static func load_named(palette_name: String) -> PaintPalette:
	var path := _file_for(palette_name)
	if not FileAccess.file_exists(path):
		return null
	var palette := from_gpl(FileAccess.get_file_as_string(path), palette_name)
	if palette != null:
		palette.name = palette_name
	return palette


## 存進色票庫(同名直接覆蓋;要不要覆蓋由呼叫端先問)。成功回空字串。
func save_to_library() -> String:
	if name.strip_edges() == "":
		return "色票名稱不能是空的"
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var file := FileAccess.open(_file_for(name), FileAccess.WRITE)
	if file == null:
		return "無法寫入色票檔"
	file.store_string(to_gpl())
	file.close()
	return ""


static func delete_named(palette_name: String) -> void:
	var path := _file_for(palette_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 同名已經有了:回傳「名稱(1)」「名稱(2)」…裡第一個沒用過的。
static func unique_name(palette_name: String) -> String:
	var base := palette_name.strip_edges()
	if not exists(base):
		return base
	var counter := 1
	while exists("%s(%d)" % [base, counter]):
		counter += 1
	return "%s(%d)" % [base, counter]


## 匯出到任意路徑(使用者選的 .gpl)。成功回空字串。
func export_to(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "無法寫入這個檔案"
	file.store_string(to_gpl())
	file.close()
	return ""


static func import_from(path: String) -> PaintPalette:
	if not FileAccess.file_exists(path):
		return null
	return from_gpl(FileAccess.get_file_as_string(path), path.get_file().get_basename())


## 色票庫是空的:放一組基本色(黑白灰、三原色與常用色、膚色,加一格全透明)。
static func ensure_default() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	for file in DirAccess.get_files_at(FOLDER):
		if file.get_extension().to_lower() == "gpl":
			return
	var palette := PaintPalette.new()
	palette.name = TranslationServer.translate(DEFAULT_NAME)
	for code: String in ["000000", "3f3f46", "7c7c86", "b9b9c0", "ffffff", "e53b44", "f77622", "feae34", "fee761", "63c74d",
			"3e8948", "2ce8f5", "0099db", "124e89", "68386c", "b55088", "f6757a", "e8b796", "c28569", "733e39"]:
		palette.add(Color.html(code))
	palette.add(Color(0, 0, 0, 0), TranslationServer.translate("透明"))
	palette.save_to_library()
