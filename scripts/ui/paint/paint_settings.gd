class_name PaintSettings
extends RefCounted
## 繪圖功能記住的設定,存在 settings.cfg 的 [paint]:工具尺寸與筆刷類型、覆蓋/疊色、筆壓(畫筆 size_pressure / opacity_pressure,橡皮擦 eraser_*)、洋蔥皮與格線、透明格子亮 / 暗、右鍵綁定的工具、
## 主副色、用哪一組色票、外部貼上的透明色、形狀 / 漸層 / 魔術棒的設定、吸色要不要吸透明度,以及繪圖板驅動程式(Windows Ink / Wintab,開機時就套用,見 apply_tablet_driver)。

const SECTION := "paint"
const DEFAULTS := {
	"brush_size": 1,
	"brush_smooth": false,
	"eraser_size": 4,
	"eraser_smooth": false,
	"blend": false,
	"size_pressure": true,
	"opacity_pressure": false,
	"eraser_size_pressure": true,
	"eraser_opacity_pressure": false,
	"checker_dark": false,
	"brush_stabilizer": 0,
	"eraser_stabilizer": 0,
	"canvas_all_pages": false,
	"onion": true,
	"grid": true,
	"reference": true,
	"right_tool": "",
	"primary": Color(0, 0, 0, 1),
	"secondary": Color(1, 1, 1, 0),
	"palette": "",
	"key_enabled": false,
	"key_color": Color(1, 1, 1, 1),
	"tablet_driver": "",
	"shape_filled": false,
	"gradient_kind": "linear",
	"gradient_steps": 0,
	"gradient_dither": false,
	"wand_tolerance": 0,
	"wand_contiguous": true,
	"pick_alpha": true,
}
const MAX_SIZE := 256
## 不是筆刷尺寸的整數設定的範圍(其他整數一律 1~MAX_SIZE)。
const INT_RANGES := {"gradient_steps": [0, 32], "wand_tolerance": [0, 255], "brush_stabilizer": [0, 10], "eraser_stabilizer": [0, 10]}
const GRADIENT_KINDS: Array[String] = ["linear", "radial"]
## 可以綁到右鍵的工具(空字串 = 沒有綁,右鍵預設是畫筆畫副色)。
const RIGHT_TOOLS: Array[String] = ["", "brush", "eraser", "picker"]


static func load_all() -> Dictionary:
	var config := ConfigFile.new()
	config.load(AppSettings.SETTINGS_PATH)
	var result := {}
	for key: String in DEFAULTS:
		result[key] = config.get_value(SECTION, key, DEFAULTS[key])
	return clean(result)


static func clean(raw: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	for key: String in DEFAULTS:
		var fallback: Variant = DEFAULTS[key]
		var value: Variant = raw.get(key, fallback)
		if fallback is bool:
			result[key] = value if value is bool else fallback
		elif fallback is int:
			var limits: Array = INT_RANGES.get(key, [1, MAX_SIZE])
			result[key] = clampi(int(value), limits[0], limits[1]) if (value is int or value is float) else fallback
		elif fallback is Color:
			result[key] = value if value is Color else fallback
		else:
			result[key] = str(value) if value is String else fallback
	if not RIGHT_TOOLS.has(str(result["right_tool"])):
		result["right_tool"] = ""
	if not GRADIENT_KINDS.has(str(result["gradient_kind"])):
		result["gradient_kind"] = "linear"
	return result


static func save_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	var config := ConfigFile.new()
	config.load(AppSettings.SETTINGS_PATH)
	config.set_value(SECTION, key, clean({key: value})[key])
	config.save(AppSettings.SETTINGS_PATH)


# --- 繪圖板驅動程式 ---

## 這台電腦可以選的繪圖板驅動程式(DisplayServer 的名稱,例如 winink、wintab)。
static func tablet_drivers() -> Array[String]:
	var names: Array[String] = []
	for i in DisplayServer.tablet_get_driver_count():
		names.append(DisplayServer.tablet_get_driver_name(i))
	return names


static func tablet_driver_label(driver: String) -> String:
	match driver:
		"winink":
			return "Windows Ink"
		"wintab":
			return "Wintab"
		"":
			return TranslationServer.translate("系統預設")
	return driver


## 換驅動程式並記下來(空字串 = 下次開機回到系統預設)。回傳現在實際用的驅動程式。
static func set_tablet_driver(driver: String) -> String:
	save_value("tablet_driver", driver)
	if driver != "" and tablet_drivers().has(driver):
		DisplayServer.tablet_set_current_driver(driver)
	return DisplayServer.tablet_get_current_driver()


## 開機時套用記下來的驅動程式(沒記過、或這台電腦沒有那個驅動程式就不動)。
static func apply_tablet_driver() -> void:
	var driver := str(load_all()["tablet_driver"])
	if driver != "" and tablet_drivers().has(driver) and DisplayServer.tablet_get_current_driver() != driver:
		DisplayServer.tablet_set_current_driver(driver)
