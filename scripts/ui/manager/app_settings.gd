class_name AppSettings
extends RefCounted
## 程式本身的設定(不屬於任何一隻桌寵):效能(最高影格率)與「視窗化編輯器」的外觀(配色、字體、字級)。存在 user://settings.cfg 的 [performance]、[editor_ui] 區段
## (只覆寫自己的區段,不動別人的)。「全局設定」視窗改這些;改完立刻套用到所有開著的編輯器視窗(見 FloatingWindow.refresh_theme)。

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_MAX_FPS := 30
const MIN_MAX_FPS := 10
const MAX_MAX_FPS := 120
const DEFAULT_FONT_SIZE := 15
## 介面語系:不是寫死的清單,動態掃描哪些語系真的載得到翻譯(見 available_languages/register_user_translations)。
## 隨程式發行的幾份放在 res://translations/、登記在 project.godot 的 locale/translations 裡,開機時引擎自動載入;
## 使用者(或社群)自己補的語系檔放 user://translations/,不用重新打包,下拉選單重啟後就會多一個選項,
## 沒放檔案的語系不會出現。介面文字的原文是繁體中文;沒翻的字串顯示原文(做法見 docs/文字與翻譯指南.md)。
const DEFAULT_LANGUAGE := "zh_TW"
const USER_TRANSLATIONS_DIR := "user://translations/"
const COLOR_KEYS: Array[String] = ["bg", "panel", "text", "muted", "button", "accent"]
const COLOR_LABELS := {"bg": "視窗背景", "panel": "輸入框與清單底色", "text": "文字", "muted": "次要文字(停用、無效、提示、說明圖示)", "button": "按鈕", "accent": "強調色(選取、焦點)"}
## 預設配色組:id → {name, colors, title:{bg,text}}(title 是這組配色的標題列顏色,標題列顏色設成「自動」時用它)。使用者自己調過顏色就是 "custom"。muted 沒寫(或舊設定檔沒有)時由文字色與視窗背景混出來(default_muted),所以任何配色組的次要文字都看得到。
const PRESETS := {
	"notebook": {"name": "筆記本", "colors": {"bg": "#e3e1de", "panel": "#f1f0e9", "text": "#575151", "muted": "#98988b", "button": "#f1f0e9", "accent": "#e2dad0"}, "title": {"bg": "#cac6c3", "text": "#7f625e"}},
	"light": {"name": "明亮", "colors": {"bg": "#eef0f4", "panel": "#ffffff", "text": "#23262e", "muted": "#6b7180", "button": "#d9dde6", "accent": "#f8c054"}, "title": {"bg": "#f7d121", "text": "#2e2e2e"}},
	"gray": {"name": "灰暗", "colors": {"bg": "#444745", "panel": "#312f2d", "text": "#f2f4ed", "muted": "#9c9a97", "button": "#656967", "accent": "#86856b"}, "title": {"bg": "#323130", "text": "#f2f4ed"}},
	"dark": {"name": "深夜", "colors": {"bg": "#23262e", "panel": "#1a1c22", "text": "#e8eaf0", "muted": "#8b91a0", "button": "#343946", "accent": "#4b8fe0"}, "title": {"bg": "#000000", "text": "#ffffff"}},
	"mint": {"name": "薄荷", "colors": {"bg": "#e4e8e6", "panel": "#d5dad4", "text": "#3b3c38", "muted": "#7b808b", "button": "#bed8cc", "accent": "#8bf0c1"}, "title": {"bg": "#6dd7b2", "text": "#138681"}},
	"nova": {"name": "新星", "colors": {"bg": "#121212", "panel": "#000202", "text": "#f0e9e9", "muted": "#929175", "button": "#183531", "accent": "#695703"}, "title": {"bg": "#685f33", "text": "#d0cca9"}},
	"matcha": {"name": "抹茶", "colors": {"bg": "#8da58d", "panel": "#879a7f", "text": "#fbfbfb", "muted": "#5c5d54", "button": "#b5bdac", "accent": "#91816b"}, "title": {"bg": "#778b7b", "text": "#6f4b46"}},
	"strawberry": {"name": "草莓", "colors": {"bg": "#ffb8b8", "panel": "#fff0f3", "text": "#b70b2d", "muted": "#d3425f", "button": "#fe959a", "accent": "#fd6f83"}, "title": {"bg": "#e02943", "text": "#ffd7e2"}},
	"pudding": {"name": "布丁", "colors": {"bg": "#ffe09e", "panel": "#fdf9dd", "text": "#ad3131", "muted": "#d38911", "button": "#ffc870", "accent": "#f79545"}, "title": {"bg": "#9a5838", "text": "#ffc377"}},
	"warm": {"name": "暖橘", "colors": {"bg": "#2e2620", "panel": "#221c17", "text": "#f3e9dc", "muted": "#a4917d", "button": "#4a3c31", "accent": "#a86910"}, "title": {"bg": "#7a4325", "text": "#e8a03a"}},
	"sky": {"name": "天藍", "colors": {"bg": "#9ee2ff", "panel": "#ccf2ff", "text": "#1951c0", "muted": "#3b87ea", "button": "#68c9f3", "accent": "#31a0fa"}, "title": {"bg": "#31a0fa", "text": "#fafafa"}},
	"midnight": {"name": "桔梗", "colors": {"bg": "#10131c", "panel": "#0a0c12", "text": "#cfd6e6", "muted": "#7c869e", "button": "#283044", "accent": "#7a6ee0"}, "title": {"bg": "#2c257a", "text": "#9e93fb"}},
}
## 預設配色組(沒設定過、還原預設外觀時用)。已經存了別的配色組的人不受影響。
const DEFAULT_PRESET := "notebook"
## 文字變體名稱(見 build_theme):次要文字(說明、狀態列、數量)、警告文字(問題、提醒)。Label 設 theme_type_variation 就會跟著配色。
const MUTED_LABEL := &"MutedLabel"
const WARN_LABEL := &"WarnLabel"


## 目前配色的文字色加上透明度:卡片底色、邊框這類「淡淡的一層」用它,不要寫死白色(淺色配色下白色的淡層看不見)。
static func ink(alpha: float) -> Color:
	return Color((appearance()["colors"] as Dictionary)["text"], alpha)


## 次要文字的預設色:文字色往視窗背景混 45%(深淺配色都會和背景保持對比)。
static func default_muted(text: Color, bg: Color) -> Color:
	return text.lerp(bg, 0.45)


# --- 重要更新(見 UpdateChecker):開機背景檢查的快取結果,系統匣圖示/選單文字用它決定要不要顯示紅點版。
# 只快取「有沒有重要更新」這一件事,不是完整的檢查結果(那個只在使用者主動按「檢查更新…」時才需要)。

## {available: 現在該不該顯示紅點, version: 該版本號(給之後想顯示在 tooltip 之類的地方用,available=false 時是空字串),
## last_check: 上一次「真的連線检查成功」的 unix 時間戳(0 = 從來沒成功過)——只有成功的檢查才會推進這個時間戳,
## 離線/逾時/格式錯誤都不算,下次開機還是會想再試一次,不會因為失敗過一次就靜默跳過 3 天。
static func important_update_state() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return {"available": false, "version": "", "last_check": 0}
	return {
		"available": bool(config.get_value("updates", "important_available", false)),
		"version": str(config.get_value("updates", "important_version", "")),
		"last_check": int(config.get_value("updates", "important_last_check", 0)),
	}


static func set_important_update_state(available: bool, version: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("updates", "important_available", available)
	config.set_value("updates", "important_version", version)
	config.set_value("updates", "important_last_check", Time.get_unix_time_from_system())
	config.save(SETTINGS_PATH)


# --- 行動框顯示螢幕(2026-09-30 使用者回報:多螢幕環境下開機後行動框預設出現在副螢幕)---

## -1 = 自動(跟系統/上次視窗位置判斷的螢幕走,不主動指定);其餘是 DisplayServer 的螢幕索引。
## 存在 [display] 的 monitor_index。只支援單一螢幕顯示(見 DesktopShell._resolve_target_screen 的說明),
## 但存成「索引」而不是「跟目前螢幕數量綁死的東西」,以後真的要做多螢幕同時顯示時這個值還能沿用。
static func action_area_monitor_index() -> int:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return int(config.get_value("display", "monitor_index", -1))
	return -1


static func set_action_area_monitor_index(index: int) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("display", "monitor_index", index)
	config.save(SETTINGS_PATH)


## 上次套用畫面配置時,視窗(=螢幕)的像素尺寸。用來偵測「沒有換螢幕,但目前這個螢幕本身解析度/縮放比例
## 換了」的情況(開機時比對目前螢幕尺寸跟這個值,不一樣就代表需要重新按比例排一次,不管是不是换了螢幕都一樣
## 處理——見 DesktopShell.apply_monitor_setting())。(0,0) = 還沒記錄過(全新安裝,不必比對)。
static func last_known_window_size() -> Vector2:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return Vector2(float(config.get_value("display", "last_w", 0.0)), float(config.get_value("display", "last_h", 0.0)))
	return Vector2.ZERO


static func set_last_known_window_size(size: Vector2) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("display", "last_w", size.x)
	config.set_value("display", "last_h", size.y)
	config.save(SETTINGS_PATH)


# --- 效能 ---

static func max_fps() -> int:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return clampi(int(config.get_value("performance", "max_fps", DEFAULT_MAX_FPS)), MIN_MAX_FPS, MAX_MAX_FPS)
	return DEFAULT_MAX_FPS


## 設定最高影格率並立刻套用、存檔。影格率越低越省電、越高動畫越順(桌寵動畫本身通常只有 8~14 fps,調高對畫面幫助有限)。
static func set_max_fps(value: int) -> void:
	var clamped := clampi(value, MIN_MAX_FPS, MAX_MAX_FPS)
	Engine.max_fps = clamped
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("performance", "max_fps", clamped)
	config.save(SETTINGS_PATH)


## 光源(發光效果)總開關:預設開;關掉就完全不畫、不佔穿透形狀(和效能有關)。存在 [performance] 的 lights。
static func lights_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return bool(config.get_value("performance", "lights", true))
	return true


static func set_lights_enabled(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("performance", "lights", enabled)
	config.save(SETTINGS_PATH)


# --- 夜間螢火蟲(見 FireflyLayer)---

## 螢火蟲的出現方式:auto = 本機時間 18:00 之後(到隔天 06:00 收起);schedule = 自己指定幾點到幾點;always = 總是;off = 總是關閉。
const FIREFLY_MODES: Array[String] = ["auto", "schedule", "always", "off"]
const FIREFLY_AUTO_START := 18 * 60
const FIREFLY_AUTO_END := 6 * 60
## 存在 settings.cfg 的 [fireflies]:start / end 是「一天的第幾分鐘」;count 總數、real 其中幾隻有真光(光暈)、speed 飄動速度倍率、brightness 亮度倍率、lights 要不要畫光暈(不勾就只有粒子假光)。
## zone 集中出現的位置(行動區由上到下三等分:top / middle / bottom;all = 全域);glow_size 真光光暈大小倍率、glow_strength 光暈濃度倍率(brightness 是整體亮度)。
const FIREFLY_ZONES: Array[String] = ["all", "top", "middle", "bottom"]
const FIREFLY_DEFAULTS := {"mode": "auto", "start": 1080, "end": 360, "count": 24, "real": 4, "speed": 1.0, "brightness": 1.0, "lights": true, "zone": "all", "glow_size": 1.0, "glow_strength": 1.0}
const FIREFLY_MAX_COUNT := 80
const FIREFLY_MAX_REAL := 20


## 目前的螢火蟲設定(逐項驗證,壞的用預設)。
static func fireflies() -> Dictionary:
	var config := ConfigFile.new()
	var loaded := config.load(SETTINGS_PATH) == OK
	var result := FIREFLY_DEFAULTS.duplicate()
	if not loaded:
		return result
	for key: String in FIREFLY_DEFAULTS:
		if config.has_section_key("fireflies", key):
			result[key] = config.get_value("fireflies", key)
	return clean_fireflies(result)


static func clean_fireflies(raw: Dictionary) -> Dictionary:
	var result := FIREFLY_DEFAULTS.duplicate()
	var mode := str(raw.get("mode", "auto"))
	result["mode"] = mode if FIREFLY_MODES.has(mode) else "auto"
	for key: String in ["start", "end"]:
		var value: Variant = raw.get(key, FIREFLY_DEFAULTS[key])
		result[key] = clampi(int(value), 0, 24 * 60 - 1) if (value is int or value is float) else FIREFLY_DEFAULTS[key]
	var count: Variant = raw.get("count", 24)
	result["count"] = clampi(int(count), 1, FIREFLY_MAX_COUNT) if (count is int or count is float) else 24
	var real: Variant = raw.get("real", 4)
	result["real"] = clampi(int(real), 0, mini(FIREFLY_MAX_REAL, int(result["count"]))) if (real is int or real is float) else 4
	for key: String in ["speed", "brightness", "glow_size", "glow_strength"]:
		var value: Variant = raw.get(key, 1.0)
		result[key] = clampf(float(value), 0.3, 3.0) if ((value is int or value is float) and is_finite(float(value))) else 1.0
	var zone := str(raw.get("zone", "all"))
	result["zone"] = zone if FIREFLY_ZONES.has(zone) else "all"
	result["lights"] = bool(raw.get("lights", true)) if raw.get("lights", true) is bool else true
	return result


static func set_fireflies(values: Dictionary) -> void:
	var cleaned := clean_fireflies(values)
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	for key: String in cleaned:
		config.set_value("fireflies", key, cleaned[key])
	config.save(SETTINGS_PATH)


## 這個時間(一天的第幾分鐘)螢火蟲該不該出現(純函式,方便測試)。時段可以跨午夜(18:00~06:00);起訖相同 = 整天。
static func firefly_active(config: Dictionary, minute_of_day: int) -> bool:
	match str(config.get("mode", "auto")):
		"always":
			return true
		"off":
			return false
	var start := FIREFLY_AUTO_START if str(config.get("mode", "auto")) == "auto" else int(config.get("start", FIREFLY_AUTO_START))
	var end := FIREFLY_AUTO_END if str(config.get("mode", "auto")) == "auto" else int(config.get("end", FIREFLY_AUTO_END))
	if start == end:
		return true
	if start < end:
		return minute_of_day >= start and minute_of_day < end
	return minute_of_day >= start or minute_of_day < end


## 本機時間現在是一天的第幾分鐘。
static func minute_of_day_now() -> int:
	var now := Time.get_datetime_dict_from_system()
	return int(now["hour"]) * 60 + int(now["minute"])


## 開機時套用存下來的效能與語系設定(沒存過就維持專案設定)。
static func apply_startup() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK and config.has_section_key("performance", "max_fps"):
		Engine.max_fps = max_fps()
	register_user_translations()
	# 一律照設定的語系(沒設過就是繁體中文),不跟著作業系統的語言跑;介面用詞的修正也走這條(見 translations/ui_strings.csv)。
	TranslationServer.set_locale(language())


## 使用者自己放進 user://translations/ 的翻譯檔(檔名比照 res://translations/ 那幾份的格式:
## ui_strings.<語系代碼>.translation)在開機時載入註冊,不用重新打包就能多一個語系選項。
## res:// 裡隨程式發行的那幾份已經由 project.godot 的 locale/translations 自動載入,這裡不用重複處理。
static func register_user_translations() -> void:
	var dir := DirAccess.open(USER_TRANSLATIONS_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".translation"):
			continue
		var translation := load(USER_TRANSLATIONS_DIR + file_name) as Translation
		if translation != null:
			TranslationServer.add_translation(translation)


## 語系代碼 → 選單顯示文字,使用者指定的字面(不是語系代碼的正式寫法,不要因為「不精確」自作主張改掉)。
## 沒在這裡列出的語系(使用者/社群自己補的翻譯檔)才退回 Godot 內建的語系名稱表。
const DISPLAY_NAME_OVERRIDES := {
	"zh_TW": "繁體中文(ZH-CN)",
	"en": "英文(EN)",
}


## 目前真的載得到翻譯的語系(代碼 → 顯示名稱),給語系下拉選單用。顯示名稱優先用 DISPLAY_NAME_OVERRIDES,
## 查不到就用 Godot 內建的語系名稱表,再查不到(自訂/罕見代碼)就顯示代碼本身。永遠至少有 DEFAULT_LANGUAGE 這個保底選項。
static func available_languages() -> Dictionary:
	var result := {}
	for code: String in TranslationServer.get_loaded_locales():
		if DISPLAY_NAME_OVERRIDES.has(code):
			result[code] = DISPLAY_NAME_OVERRIDES[code]
			continue
		var display_name := TranslationServer.get_locale_name(code)
		result[code] = display_name if display_name != "" else code
	if not result.has(DEFAULT_LANGUAGE):
		result[DEFAULT_LANGUAGE] = DISPLAY_NAME_OVERRIDES.get(DEFAULT_LANGUAGE, "繁體中文")
	return result


## 浮動視窗(管理視窗、編輯器…,不含行動區裡的懸浮球與道具欄)是否永遠置頂;存在 [editor_ui] 的 floating_on_top。
## 2026-09-30 曾經因為置頂跟原生子視窗(對話框)的 transient 關係衝突(godotengine/godot#117698)整個強制關閉過;
## 2026-09-29 改成讓 ConfirmationDialog/AcceptDialog 全程不當 transient 子視窗(見 FloatingWindow.popup_child_dialog()
## 的說明)繞開這個限制,使用者實機驗證過置頂開著也不會卡死,恢復成真正的開關。萬一以後又冒出別的置頂相關卡死
## 情境,系統匣「浮動視窗重設」有獨立於這個設定的自救機制(見 DesktopShell.reset_floating_windows())。
static func floating_on_top() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return bool(config.get_value("editor_ui", "floating_on_top", false))
	return false


static func set_floating_on_top(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("editor_ui", "floating_on_top", enabled)
	config.save(SETTINGS_PATH)


# --- 對話氣泡顯示方式(2026-09-30 使用者回饋單,「氣泡固定」)---

## follow = 預設,氣泡跟著桌寵移動(既有行為);pinned = 氣泡式,使用者把某隻桌寵的氣泡拖到哪,之後那隻
## 桌寵的氣泡就固定生成在那個位置(左上角對齊),不再跟著桌寵跑;chatroom = 聊天室式,把「純資訊、不用等
## 使用者互動」的句子(沒有選項、也不是等點擊的重要提問)改成寫進一個可收合的聊天室視窗,需要互動的句子
## (問題、選項)仍然照舊用浮動氣泡顯示——不然使用者沒辦法在聊天室視窗裡點選項。存在 [dialogue] 的 bubble_mode。
const BUBBLE_MODES: Array[String] = ["follow", "pinned", "chatroom"]


static func bubble_display_mode() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var mode := str(config.get_value("dialogue", "bubble_mode", "follow"))
		if BUBBLE_MODES.has(mode):
			return mode
	return "follow"


static func set_bubble_display_mode(mode: String) -> void:
	if not BUBBLE_MODES.has(mode):
		return
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("dialogue", "bubble_mode", mode)
	config.save(SETTINGS_PATH)


# --- 標題列 ---

## 視窗標題列用自畫的(無邊框視窗,顏色跟著編輯器配色或自訂,見 FloatingWindow);預設開,關掉就用作業系統的標題列(顏色由系統決定)。
static func themed_title_bar() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return bool(config.get_value("editor_ui", "themed_title_bar", true))
	return true


static func set_themed_title_bar(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("editor_ui", "themed_title_bar", enabled)
	config.save(SETTINGS_PATH)


## 標題列顏色是否自動依強調色決定(預設是);否就用自己選的底色與文字色。
static func title_bar_auto() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return bool(config.get_value("editor_ui", "title_auto", true))
	return true


static func set_title_bar_auto(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("editor_ui", "title_auto", enabled)
	config.save(SETTINGS_PATH)


## 自己選的標題列顏色 {bg, text}(還沒選過就用自動算出來的那組當起點)。
static func title_bar_custom() -> Dictionary:
	var automatic := auto_title_bar_colors()
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	var bg := str(config.get_value("editor_ui", "title_bg", ""))
	var fg := str(config.get_value("editor_ui", "title_text", ""))
	return {"bg": Color.html(bg) if Color.html_is_valid(bg) else automatic["bg"], "text": Color.html(fg) if Color.html_is_valid(fg) else automatic["text"]}


static func set_title_bar_custom(background: Color, text_color: Color) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("editor_ui", "title_bg", background.to_html(false))
	config.set_value("editor_ui", "title_text", text_color.to_html(false))
	config.save(SETTINGS_PATH)


## 標題列的顏色 {bg, text}:自動 = 用目前配色組自己的標題列顏色(見 PRESETS 的 title);自訂配色沒有就用強調色當底、文字依底色亮度選黑或白;否則是自己選的。
static func title_bar_colors() -> Dictionary:
	if title_bar_auto():
		return auto_title_bar_colors()
	return title_bar_custom()


static func auto_title_bar_colors() -> Dictionary:
	var preset := str(appearance()["preset"])
	if PRESETS.has(preset) and (PRESETS[preset] as Dictionary).has("title"):
		var title: Dictionary = (PRESETS[preset] as Dictionary)["title"]
		return {"bg": Color.html(str(title["bg"])), "text": Color.html(str(title["text"]))}
	var accent: Color = (appearance()["colors"] as Dictionary)["accent"]
	var background := accent
	return {"bg": background, "text": Color.BLACK if background.get_luminance() > 0.55 else Color.WHITE}

# --- 介面語系 ---

## 目前的介面語系代碼;設定檔沒有或不認得就是預設(繁體中文)。
static func language() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var code := str(config.get_value("general", "language", DEFAULT_LANGUAGE))
		if available_languages().has(code):
			return code
	return DEFAULT_LANGUAGE


## 設定介面語系並存檔、立刻套用給 tr()(不認得的代碼忽略)。
static func set_language(code: String) -> void:
	if not available_languages().has(code):
		return
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("general", "language", code)
	config.save(SETTINGS_PATH)
	TranslationServer.set_locale(code)


## 首次啟動的中英選擇彈窗(見 DesktopShell._maybe_offer_language_choice)問過了沒有;跟 AppDefaults 的
## first_run(有沒有簽章檔)是不同的旗標——既有使用者升級到有這個彈窗的版本時,AppDefaults 的 first_run
## 已經是 false(簽章檔早就存在),但這個彈窗對他們來說仍然是「第一次看到」,要用獨立的旗標才問得到。
static func language_choice_prompted() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return bool(config.get_value("general", "language_prompted", false))
	return false


static func mark_language_choice_prompted() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("general", "language_prompted", true)
	config.save(SETTINGS_PATH)


# --- 編輯器外觀 ---

## 目前的外觀設定:{preset, colors:{bg,panel,text,muted,button,accent → Color}, font, font_size}。設定檔壞掉或缺項就用預設(筆記本)。
static func appearance() -> Dictionary:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	var preset := str(config.get_value("editor_ui", "preset", DEFAULT_PRESET))
	var base: Dictionary = (PRESETS[DEFAULT_PRESET] as Dictionary)["colors"]
	if PRESETS.has(preset):
		base = (PRESETS[preset] as Dictionary)["colors"]
	var colors := {}
	for key in COLOR_KEYS:
		var stored: Variant = config.get_value("editor_ui", "color_" + key, "") if preset == "custom" else ""
		if str(stored) != "" and Color.html_is_valid(str(stored)):
			colors[key] = Color.html(str(stored))
		elif key == "muted" and (preset == "custom" or not base.has(key)):
			colors[key] = default_muted(colors["text"], colors["bg"])   # 自訂配色(或舊設定檔)沒有 muted:由文字與背景混出來
		elif base.has(key):
			colors[key] = Color.html(str(base[key]))
		else:
			colors[key] = Color.WHITE
	var font_name := str(config.get_value("editor_ui", "font", "黑體"))
	if not UiFonts.FONT_NAMES.has(font_name):
		font_name = "黑體"
	return {"preset": preset if preset == "custom" or PRESETS.has(preset) else DEFAULT_PRESET, "colors": colors, "font": font_name,
			"font_size": clampi(int(config.get_value("editor_ui", "font_size", DEFAULT_FONT_SIZE)), 11, 28)}


static func save_appearance(preset: String, colors: Dictionary, font_name: String, font_size: int) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("editor_ui", "preset", preset)
	for key in COLOR_KEYS:
		if colors.get(key) is Color:   # 舊的呼叫端(或舊資料)可能沒有 muted:不存,讀的時候由文字色與背景混出來
			config.set_value("editor_ui", "color_" + key, (colors[key] as Color).to_html(false))
	config.set_value("editor_ui", "font", font_name)
	config.set_value("editor_ui", "font_size", clampi(font_size, 11, 28))
	config.save(SETTINGS_PATH)


## 還原成預設外觀(筆記本配色、黑體、15 號字)。
static func reset_appearance() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	if config.has_section("editor_ui"):
		var keep_title_bar := bool(config.get_value("editor_ui", "themed_title_bar", true))
		config.erase_section("editor_ui")
		if not keep_title_bar:
			config.set_value("editor_ui", "themed_title_bar", false)
	config.save(SETTINGS_PATH)


## 依外觀設定做出視窗化編輯器共用的主題:字體、字級、按鈕/輸入框/清單/分頁的配色與只有滾輪的細捲軸。
static func build_theme() -> Theme:
	var look := appearance()
	var c: Dictionary = look["colors"]
	var theme := Theme.new()
	theme.default_font = UiFonts.get_font(str(look["font"]))
	theme.default_font_size = int(look["font_size"])
	var bg: Color = c["bg"]
	var panel: Color = c["panel"]
	var text: Color = c["text"]
	var button: Color = c["button"]
	var accent: Color = c["accent"]
	var muted: Color = c["muted"]
	var faded := muted
	theme.set_stylebox("panel", "Panel", _flat(bg, 0))
	theme.set_stylebox("panel", "PanelContainer", _flat(bg, 0))
	theme.set_color("font_color", "Label", text)
	for control_type in ["Button", "CheckBox", "CheckButton", "OptionButton"]:
		theme.set_color("font_color", control_type, text)
		theme.set_color("font_hover_color", control_type, text)
		theme.set_color("font_pressed_color", control_type, text)
		theme.set_color("font_focus_color", control_type, text)
		theme.set_color("font_hover_pressed_color", control_type, text)
		theme.set_color("font_disabled_color", control_type, faded)
		# 圖示:引擎預設是白色(淺色配色下看不見),改跟著文字色;停用時用次要文字色
		theme.set_color("icon_normal_color", control_type, text)
		theme.set_color("icon_hover_color", control_type, text)
		theme.set_color("icon_pressed_color", control_type, text)
		theme.set_color("icon_focus_color", control_type, text)
		theme.set_color("icon_hover_pressed_color", control_type, text)
		theme.set_color("icon_disabled_color", control_type, faded)
	theme.set_stylebox("normal", "Button", _flat(button, 5, 10, 5))
	theme.set_stylebox("hover", "Button", _flat(button.lightened(0.14), 5, 10, 5))
	theme.set_stylebox("pressed", "Button", _flat(accent, 5, 10, 5))   # 強調色一律用原色,不要調暗或加透明(配色組是使用者調好的)
	theme.set_stylebox("disabled", "Button", _flat(Color(button, 0.5), 5, 10, 5))
	# focus 外框的 content_margin 要跟 normal 完全一樣(不能留給引擎自動算),不然拿到焦點的瞬間控制項的最小尺寸會變,
	# 逼旁邊自動換行的文字重排、焦點框又跟著重排後的新位置再抖一次,兩個一直互相觸發就會閃爍。
	theme.set_stylebox("focus", "Button", _outline(accent, 5, 10, 5))
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "OptionButton", theme.get_stylebox(state, "Button"))
	theme.set_stylebox("focus", "OptionButton", theme.get_stylebox("focus", "Button"))
	for input_type in ["LineEdit", "TextEdit"]:
		theme.set_color("font_color", input_type, text)
		theme.set_color("font_selected_color", input_type, text)
		theme.set_color("font_placeholder_color", input_type, faded)
		theme.set_color("font_uneditable_color", input_type, faded)   # 停用 / 唯讀的輸入框(引擎預設是半透明淺灰,淺色配色下會隱形)
		theme.set_color("caret_color", input_type, text)
		theme.set_color("selection_color", input_type, accent)
		theme.set_stylebox("normal", input_type, _flat(panel, 4, 6, 4))
		theme.set_stylebox("focus", input_type, _flat(panel, 4, 6, 4, accent))
		theme.set_stylebox("read_only", input_type, _flat(panel.darkened(0.1), 4, 6, 4))
	theme.set_color("clear_button_color", "LineEdit", text)
	theme.set_color("clear_button_color_pressed", "LineEdit", accent)
	theme.set_color("font_readonly_color", "TextEdit", faded)
	theme.set_color("current_line_color", "TextEdit", Color(text, 0.06))
	theme.set_stylebox("panel", "ItemList", _flat(panel, 4, 4, 4))
	theme.set_stylebox("focus", "ItemList", _outline(accent, 4, 4, 4))
	theme.set_stylebox("selected", "ItemList", _flat(accent, 3, 4, 2))
	theme.set_stylebox("selected_focus", "ItemList", _flat(accent, 3, 4, 2))
	theme.set_stylebox("hovered", "ItemList", _flat(Color(text, 0.08), 3, 4, 2))
	theme.set_stylebox("hovered_selected", "ItemList", _flat(accent, 3, 4, 2))
	theme.set_stylebox("hovered_selected_focus", "ItemList", _flat(accent, 3, 4, 2))
	theme.set_stylebox("cursor", "ItemList", _outline(Color(text, 0.35), 3, 4, 2))
	theme.set_stylebox("cursor_unfocused", "ItemList", _outline(Color(text, 0.2), 3, 4, 2))
	theme.set_color("font_color", "ItemList", text)
	theme.set_color("font_selected_color", "ItemList", text)
	theme.set_color("font_hovered_color", "ItemList", text)
	theme.set_color("font_hovered_selected_color", "ItemList", text)
	theme.set_stylebox("panel", "TabContainer", _flat(bg.lightened(0.04), 4, 8, 8))
	theme.set_stylebox("tab_selected", "TabContainer", _flat(accent, 4, 12, 6))
	theme.set_stylebox("tab_hovered", "TabContainer", _flat(button.lightened(0.14), 4, 12, 6))
	theme.set_stylebox("tab_unselected", "TabContainer", _flat(button, 4, 12, 6))
	theme.set_stylebox("tab_focus", "TabContainer", _outline(accent, 4, 12, 6))
	theme.set_color("font_selected_color", "TabContainer", text)
	theme.set_color("font_hovered_color", "TabContainer", text)
	theme.set_color("font_unselected_color", "TabContainer", Color(text, 0.75))
	theme.set_color("font_disabled_color", "TabContainer", faded)
	for state in ["selected", "hovered", "unselected"]:
		theme.set_color("icon_%s_color" % state, "TabContainer", text)
	theme.set_stylebox("panel", "PopupMenu", _flat(panel, 4, 6, 4, accent))
	theme.set_stylebox("hover", "PopupMenu", _flat(accent, 3, 6, 2))
	theme.set_color("font_color", "PopupMenu", text)
	theme.set_color("font_hover_color", "PopupMenu", text)
	theme.set_color("font_disabled_color", "PopupMenu", faded)
	theme.set_color("font_accelerator_color", "PopupMenu", faded)
	theme.set_color("font_separator_color", "PopupMenu", faded)
	theme.set_stylebox("panel", "TooltipPanel", _flat(panel.darkened(0.15), 4, 8, 6, accent))
	theme.set_color("font_color", "TooltipLabel", text)
	theme.set_color("separator", "HSeparator", Color(text, 0.2))
	theme.set_color("font_disabled_color", "Label", faded)
	# 對話框(確認視窗)與彈出面板(色票的取色器)的底:預設是深灰色,淺色配色下文字會看不見
	theme.set_stylebox("panel", "AcceptDialog", _flat(bg, 0, 8, 8))
	theme.set_stylebox("panel", "PopupPanel", _flat(bg, 4, 8, 8, accent))
	# 富文字(署名清單這類)預設是白字
	theme.set_color("default_color", "RichTextLabel", text)
	theme.set_color("font_selected_color", "RichTextLabel", text)
	theme.set_color("selection_color", "RichTextLabel", accent)
	theme.set_color("table_border", "RichTextLabel", Color(text, 0.3))
	# 核取方塊與單選鈕的圖示(預設是白色,淺色配色下看不見)、數字框的上下箭頭
	for control_type in ["CheckBox", "CheckButton"]:
		theme.set_color("checkbox_checked_color", control_type, text)
		theme.set_color("checkbox_unchecked_color", control_type, text)
	for direction in ["up", "down"]:
		theme.set_color("%s_icon_modulate" % direction, "SpinBox", text)
		theme.set_color("%s_hover_icon_modulate" % direction, "SpinBox", text)
		theme.set_color("%s_pressed_icon_modulate" % direction, "SpinBox", text)
		theme.set_color("%s_disabled_icon_modulate" % direction, "SpinBox", faded)
	# 滑桿:軌道用文字色淡淡一條,已填的部分用強調色
	theme.set_stylebox("slider", "HSlider", _flat(Color(text, 0.25), 2, 0, 2))
	theme.set_stylebox("grabber_area", "HSlider", _flat(accent, 2, 0, 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _flat(accent, 2, 0, 2))
	# 引擎預設的圖示是給深色底畫的淺色圖,沒有顏色調節項的地方改成「用目前配色染過的版本」
	_tint_icons(theme, "OptionButton", ["arrow"], text)
	_tint_icons(theme, "PopupMenu", ["checked", "unchecked", "radio_checked", "radio_unchecked", "submenu", "submenu_mirrored"], text)
	_tint_icons(theme, "PopupMenu", ["checked_disabled", "unchecked_disabled", "radio_checked_disabled", "radio_unchecked_disabled"], faded)
	_tint_icons(theme, "TabContainer", ["increment", "increment_highlight", "decrement", "decrement_highlight"], text)
	_tint_icons(theme, "HSlider", ["grabber", "grabber_highlight", "tick"], text)
	_tint_icons(theme, "HSlider", ["grabber_disabled"], faded)
	# 自訂項目:供各視窗取用(見 ManagerUi.muted_color)
	theme.set_color("muted", "Label", muted)
	theme.set_color("accent", "Label", accent)
	theme.set_color("bg", "Label", bg)
	theme.set_color("panel", "Label", panel)
	# 文字變體(Label.theme_type_variation):次要文字、警告文字。用它取代「把 modulate 改成半透明白色 / 固定的橘紅色」,才會跟著配色(淺色底上白色與淺橘紅都看不見)。
	theme.set_type_variation(MUTED_LABEL, "Label")
	theme.set_color("font_color", MUTED_LABEL, muted)
	theme.set_type_variation(WARN_LABEL, "Label")
	theme.set_color("font_color", WARN_LABEL, warning_color(bg))
	_style_scrollbars(theme, Color(text, 1.0))
	return theme


## 警告文字色:深色底用淺橘紅,淺色底用深紅褐(固定一個顏色在兩邊總有一邊看不清楚)。
static func warning_color(bg: Color) -> Color:
	# 淺橘紅與深紅褐兩個候選,取和底色亮度差比較大的(中間亮度的底色也分得開)
	var light := Color(1.0, 0.62, 0.52)
	var dark := Color(0.62, 0.10, 0.06)
	return light if absf(light.get_luminance() - bg.get_luminance()) >= absf(dark.get_luminance() - bg.get_luminance()) else dark


static var _tint_cache := {}


## 把引擎預設主題裡某類控制項的圖示乘上一個顏色放進 theme(等於加上 modulate);找不到圖示或沒有畫面(無頭)就跳過。結果照顏色快取。
static func _tint_icons(theme: Theme, control_type: String, icon_names: Array, color: Color) -> void:
	var default_theme := ThemeDB.get_default_theme()
	for icon_name: String in icon_names:
		if not default_theme.has_icon(icon_name, control_type):
			continue
		var key := "%s/%s/%s" % [control_type, icon_name, color.to_html()]
		if not _tint_cache.has(key):
			var source := default_theme.get_icon(icon_name, control_type)
			var image := source.get_image() if source != null else null
			if image == null or image.is_empty():
				_tint_cache[key] = null
			else:
				image = image.duplicate()
				image.convert(Image.FORMAT_RGBA8)
				for y in image.get_height():
					for x in image.get_width():
						var pixel := image.get_pixel(x, y)
						image.set_pixel(x, y, Color(pixel.r * color.r, pixel.g * color.g, pixel.b * color.b, pixel.a * color.a))
				_tint_cache[key] = ImageTexture.create_from_image(image)
		if _tint_cache[key] != null:
			theme.set_icon(icon_name, control_type, _tint_cache[key])


static func _flat(color: Color, radius: int, margin_x := 6, margin_y := 4, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(1)
	return box


## 只畫外框、不鋪底的外框(給 focus/cursor 這類疊在別的狀態上面的方框)。margin_x/margin_y 一定要跟同一個控制項其他狀態
## (normal/panel…)的 content_margin 填一樣的值——留 -1 給引擎自動算的話,狀態切換時最小尺寸會跟著變,見呼叫端註解。
static func _outline(color: Color, radius: int, margin_x: int, margin_y: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = color
	box.set_border_width_all(2)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box


## 捲軸:沒有底色、沒有上下箭頭(三角形),只留一條半透明的細滾輪(顏色跟著文字色)。
static func _style_scrollbars(theme: Theme, thumb_color: Color) -> void:
	var blank := StyleBoxEmpty.new()
	var arrow_free := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for bar_type in ["VScrollBar", "HScrollBar"]:
		var vertical: bool = bar_type == "VScrollBar"
		theme.set_stylebox("scroll", bar_type, blank)
		theme.set_stylebox("scroll_focus", bar_type, blank)
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var thumb := StyleBoxFlat.new()
			thumb.bg_color = Color(thumb_color, {"grabber": 0.28, "grabber_highlight": 0.45, "grabber_pressed": 0.6}[state])
			thumb.set_corner_radius_all(4)
			if vertical:
				thumb.content_margin_left = 4.0
				thumb.content_margin_right = 4.0
			else:
				thumb.content_margin_top = 4.0
				thumb.content_margin_bottom = 4.0
			theme.set_stylebox(state, bar_type, thumb)
		for icon_name in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			theme.set_icon(icon_name, bar_type, arrow_free)
