class_name AppSettingsTab
extends VBoxContainer
## 全局設定的內容(放在「全局設定」視窗裡,不屬於任何一隻桌寵):音效(靜音、說話音效、全部桌寵音量)、介面語系、效能(最高影格率)、視窗化編輯器的外觀(配色組、五個顏色、字體、字級)。
## 這些設定改了就立刻套用並存進 user://settings.cfg(見 AppSettings),沒有「儲存」按鈕。
## 外觀影響所有視窗化編輯器(桌寵管理、精靈圖編輯器、性格編輯器、測試者面板…),不影響桌寵的對話氣泡(那是每隻桌寵自己的「介面風格」)。

signal message(text: String)
## 音效設定:kind 是 "mute"(value bool)、"speak"(value bool)、"volume"(value 0.0–1.0);由開啟這個分頁的地方(DesktopShell)寫進共享狀態。
signal audio_setting_requested(kind: String, value: Variant)

const CUSTOM_ID := "custom"

var _mute_check: CheckBox
var _speak_check: CheckBox
var _volume_slider: HSlider
var _volume_label: Label
var _alarm_list: ItemList
var _alarm_delete: Button
var _language_option: OptionButton
var _fps_spin: SpinBox
var _autostart_check: CheckBox
var _lights_check: CheckBox
var _on_top_check: CheckBox
var _firefly_mode: OptionButton
var _firefly_start_hour: SpinBox
var _firefly_start_minute: SpinBox
var _firefly_end_hour: SpinBox
var _firefly_end_minute: SpinBox
var _firefly_count: SpinBox
var _firefly_real: SpinBox
var _firefly_speed: SpinBox
var _firefly_brightness: SpinBox
var _firefly_zone: OptionButton
var _firefly_glow_size: SpinBox
var _firefly_glow_strength: SpinBox
var _firefly_lights: CheckBox
var _firefly_status: Label
var _preset_option: OptionButton
var _color_buttons: Dictionary = {}
var _font_option: OptionButton
var _size_spin: SpinBox
var _sample: Label
var _title_check: CheckBox
var _title_auto_check: CheckBox
var _title_bg_picker: ColorPickerButton
var _title_text_picker: ColorPickerButton
var _updating := false


func _ready() -> void:
	name = "全局設定"
	add_theme_constant_override("separation", 8)
	_build_audio()
	add_child(HSeparator.new())
	_build_language()
	add_child(HSeparator.new())
	_build_performance()
	add_child(HSeparator.new())
	_build_startup()
	add_child(HSeparator.new())
	_build_fireflies()
	add_child(HSeparator.new())
	_build_appearance()
	_load_into_widgets()
	get_node("/root/DesktopShellState").audio_settings_changed.connect(_load_audio)


func _build_audio() -> void:
	add_child(ManagerUi.heading_with_info("音效", "全部桌寵共用的音效設定。音量是整個程式的總音量(說話聲與效果音一起調),靜音會讓所有桌寵都不出聲;每隻桌寵自己的靜音在測試者面板與桌寵管理裡。改了立刻生效,下次開機也會沿用。"))
	_mute_check = CheckBox.new()
	_mute_check.text = "靜音(全部桌寵)"
	_mute_check.toggled.connect(func(on: bool) -> void:
		if not _updating:
			audio_setting_requested.emit("mute", on)
			message.emit("已靜音。" if on else "已解除靜音。"))
	add_child(_mute_check)
	_speak_check = CheckBox.new()
	_speak_check.text = "說話音效(對話氣泡打字時的聲音)"
	_speak_check.toggled.connect(func(on: bool) -> void:
		if not _updating:
			audio_setting_requested.emit("speak", on)
			message.emit("說話音效已開啟。" if on else "說話音效已關閉。"))
	add_child(_speak_check)
	var volume_row := HBoxContainer.new()
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 100.0
	_volume_slider.step = 5.0
	_volume_slider.custom_minimum_size.x = 220.0
	_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume_slider.value_changed.connect(func(value: float) -> void:
		_volume_label.text = "%d%%" % int(value)
		if not _updating:
			audio_setting_requested.emit("volume", value / 100.0)
			message.emit(tr("全部桌寵的音量已設成 %d%%。") % int(value)))
	volume_row.add_child(_volume_slider)
	_volume_label = Label.new()
	_volume_label.custom_minimum_size.x = 48.0
	volume_row.add_child(_volume_label)
	add_child(ManagerUi.labeled("全部桌寵音量", volume_row))
	add_child(ManagerUi.heading_with_info("提醒音效庫", "自己匯入的音效檔(ogg / wav / mp3),不綁定特定桌寵——匯入一次,任何桌寵的右鍵選單「計時提醒音效」都選得到,跟內建的幾個音效並列。"))
	_alarm_list = ItemList.new()
	_alarm_list.custom_minimum_size.y = 80.0
	_alarm_list.item_selected.connect(func(_index: int) -> void: _alarm_delete.disabled = false)
	add_child(_alarm_list)
	var alarm_buttons := HBoxContainer.new()
	var alarm_import := ManagerUi.button("匯入音效…")
	alarm_import.pressed.connect(_browse_alarm_sound)
	alarm_buttons.add_child(alarm_import)
	_alarm_delete = ManagerUi.button("刪除選取的音效")
	_alarm_delete.disabled = true
	_alarm_delete.pressed.connect(_delete_selected_alarm_sound)
	alarm_buttons.add_child(_alarm_delete)
	add_child(alarm_buttons)
	_refresh_alarm_list()


func _refresh_alarm_list() -> void:
	if _alarm_list == null:
		return
	_alarm_list.clear()
	for file_name: String in AlarmSounds.list():
		_alarm_list.add_item(AlarmSounds.display_name(file_name))
		_alarm_list.set_item_metadata(_alarm_list.item_count - 1, file_name)
	_alarm_delete.disabled = true


func _browse_alarm_sound() -> void:
	FloatingWindow.native_file_dialog("選擇提醒音效", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.ogg,*.wav,*.mp3;音效檔"]),
			func(paths: PackedStringArray) -> void: _import_alarm_sound(paths[0]), get_window().get_window_id())


func _import_alarm_sound(path: String) -> void:
	var result := AlarmSounds.import_file(path)
	message.emit(str(result["message"]))
	if result["ok"]:
		_refresh_alarm_list()


func _delete_selected_alarm_sound() -> void:
	var selected := _alarm_list.get_selected_items()
	if selected.is_empty():
		return
	var file_name := str(_alarm_list.get_item_metadata(selected[0]))
	if AlarmSounds.delete(file_name):
		message.emit(tr("已刪除「%s」(已經選這個音效當計時提醒的桌寵會退回內建預設)。") % AlarmSounds.display_name(file_name))
		_refresh_alarm_list()


func _build_language() -> void:
	add_child(ManagerUi.heading_with_info("介面語系", "程式介面(選單、視窗、按鈕)使用的語言。介面文字的原文是繁體中文;其他語系要有翻譯(translations/ui_strings.csv)才會生效,沒翻的字串顯示原文。桌寵對話的多語系則要去積木編輯器的「翻譯檢視」修改。"))
	_language_option = OptionButton.new()
	var languages := AppSettings.available_languages()
	for code: String in languages:
		_language_option.add_item(str(languages[code]))
		_language_option.set_item_metadata(_language_option.item_count - 1, code)
	_language_option.item_selected.connect(func(index: int) -> void:
		if _updating:
			return
		var code := str(_language_option.get_item_metadata(index))
		AppSettings.set_language(code)
		var names := AppSettings.available_languages()
		message.emit(tr("介面語系已設成 %s(沒有翻譯的字串會顯示原文)。") % names[code] if code != AppSettings.DEFAULT_LANGUAGE else "介面語系已設成繁體中文。"))
	add_child(ManagerUi.labeled("介面語系", _language_option))


func _load_audio() -> void:
	var state := get_node("/root/DesktopShellState")
	var was_updating := _updating
	_updating = true
	_mute_check.button_pressed = state.audio_muted
	_speak_check.button_pressed = state.speak_sound_enabled
	_volume_slider.value = roundf(clampf(state.audio_volume, 0.0, 1.0) * 20.0) * 5.0
	_volume_label.text = "%d%%" % int(_volume_slider.value)
	_updating = was_updating


func _build_performance() -> void:
	add_child(ManagerUi.heading_with_info("效能", "最高影格率:程式每秒最多更新畫面幾次。越低越省電、越省 CPU/GPU;越高動畫與拖曳越順。桌寵的動畫本身通常只有 8~14 fps,調高對畫面的幫助有限,電腦比較吃力時可以調低。改了立刻生效,下次開機也會沿用。"))
	_fps_spin = ManagerUi.spin(1.0, AppSettings.MIN_MAX_FPS, AppSettings.MAX_MAX_FPS)
	_fps_spin.allow_greater = false
	_fps_spin.allow_lesser = false
	_fps_spin.suffix = " fps"
	_fps_spin.value_changed.connect(func(value: float) -> void:
		if _updating:
			return
		AppSettings.set_max_fps(int(value))
		message.emit(tr("最高影格率已設成 %d fps。") % int(value)))
	add_child(ManagerUi.labeled("最高影格率", _fps_spin))
	_lights_check = CheckBox.new()
	_lights_check.text = "啟用光源(角色身上的發光效果;關掉可以省效能)"
	_lights_check.toggled.connect(func(on: bool) -> void:
		if _updating:
			return
		AppSettings.set_lights_enabled(on)
		get_tree().call_group("pet_lights", "refresh_setting")
		get_tree().call_group("fireflies", "refresh_setting")
		message.emit("光源已開啟。" if on else "光源已關閉。"))
	add_child(_lights_check)
	_on_top_check = CheckBox.new()
	_on_top_check.text = "浮動視窗保持在最上層(取消後可能被其他程式蓋住;蓋住時用系統匣的「浮動視窗重設」拉回來)"
	_on_top_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_on_top_check.toggled.connect(func(on: bool) -> void:
		if _updating:
			return
		AppSettings.set_floating_on_top(on)
		get_tree().call_group("floating_windows", "refresh_on_top")
		message.emit("浮動視窗會保持在最上層。" if on else "浮動視窗不再保持最上層。"))
	add_child(_on_top_check)


## 開機自動啟動(Windows 登入時,不用系統管理員權限):寫進登錄檔的開機清單,預設關閉。只在匯出後的 exe 有意義(見 AutoStart)。
func _build_startup() -> void:
	add_child(ManagerUi.heading_with_info("開機", "電腦開機、登入 Windows 之後自動打開這個程式。寫在「目前使用者」的開機清單裡,不需要系統管理員權限,關掉這個選項或在系統的「啟動應用程式」設定裡關掉都可以取消。只支援 Windows;在還沒匯出成 exe 的開發專案裡開這個開關,開機時打開的會是 Godot 編輯器本身,不是遊戲。"))
	_autostart_check = CheckBox.new()
	_autostart_check.text = "開機時自動啟動(預設關閉)"
	_autostart_check.disabled = not AutoStart.supported()
	if not AutoStart.supported():
		_autostart_check.tooltip_text = "這台系統不支援(只有 Windows 才有)。"
	_autostart_check.toggled.connect(func(on: bool) -> void:
		if _updating:
			return
		var error := AutoStart.set_enabled(on)
		if error != "":
			_updating = true
			_autostart_check.button_pressed = AutoStart.is_enabled()
			_updating = false
			message.emit(tr("設定失敗:%s") % error)
			return
		message.emit("開機時會自動啟動。" if on else "已取消開機自動啟動。"))
	add_child(_autostart_check)


## 夜間螢火蟲:出現時間(自動 / 自己指定幾點到幾點 / 總是 / 關閉)、數量、飄動速度、亮度、真光數量、要不要畫光暈。改了立刻套用並存檔。
func _build_fireflies() -> void:
	add_child(ManagerUi.heading_with_info("夜間螢火蟲", "行動區裡飄動的背景裝飾(不會和桌寵、道具互動)。「自動」= 本機時間 18:00 之後出現、隔天 06:00 收起;也可以自己指定幾點到幾點、總是出現或完全關閉。多數螢火蟲只是忽隱忽現的白色小點(假光,幾乎不耗效能),少數「真光」還會有一圈柔和的光暈;不勾「啟用光源」就全部只畫小點。螢火蟲所在的小塊區域滑鼠點不到桌面(很小,飄走就恢復)。"))
	_firefly_mode = OptionButton.new()
	var labels := {"auto": "自動(本機時間 18:00 之後)", "schedule": "自己指定時段", "always": "總是出現", "off": "總是關閉"}
	for mode: String in AppSettings.FIREFLY_MODES:
		_firefly_mode.add_item(str(labels[mode]))
		_firefly_mode.set_item_metadata(_firefly_mode.item_count - 1, mode)
	_firefly_mode.item_selected.connect(func(_i: int) -> void: _save_fireflies())
	add_child(ManagerUi.labeled("出現時間", _firefly_mode))
	var window_row := HBoxContainer.new()
	_firefly_start_hour = _firefly_time_spin(23.0)
	_firefly_start_minute = _firefly_time_spin(59.0)
	_firefly_end_hour = _firefly_time_spin(23.0)
	_firefly_end_minute = _firefly_time_spin(59.0)
	for pair: Array in [["從", _firefly_start_hour, _firefly_start_minute], ["到", _firefly_end_hour, _firefly_end_minute]]:
		var word := Label.new()
		word.text = str(pair[0])
		window_row.add_child(word)
		window_row.add_child(pair[1])
		var colon := Label.new()
		colon.text = ":"
		window_row.add_child(colon)
		window_row.add_child(pair[2])
	add_child(ManagerUi.labeled("指定時段", window_row))
	_firefly_count = ManagerUi.spin(1.0, 1.0, float(AppSettings.FIREFLY_MAX_COUNT))
	_firefly_count.value_changed.connect(func(_v: float) -> void: _save_fireflies())
	add_child(ManagerUi.labeled("螢火蟲數量", _firefly_count))
	_firefly_real = ManagerUi.spin(1.0, 0.0, float(AppSettings.FIREFLY_MAX_REAL))
	_firefly_real.value_changed.connect(func(_v: float) -> void: _save_fireflies())
	add_child(ManagerUi.labeled("其中真光(有光暈)", _firefly_real))
	_firefly_speed = ManagerUi.spin(0.1, 0.3, 3.0)
	_firefly_speed.value_changed.connect(func(_v: float) -> void: _save_fireflies())
	add_child(ManagerUi.labeled("飄動速度(倍)", _firefly_speed))
	_firefly_brightness = ManagerUi.spin(0.1, 0.3, 3.0)
	_firefly_brightness.value_changed.connect(func(_v: float) -> void: _save_fireflies())
	add_child(ManagerUi.labeled("整體亮度(倍)", _firefly_brightness))
	_firefly_zone = OptionButton.new()
	var zone_labels := {"all": "全域(整個行動區)", "top": "集中在上方", "middle": "集中在中間", "bottom": "集中在下方"}
	for zone: String in AppSettings.FIREFLY_ZONES:
		_firefly_zone.add_item(str(zone_labels[zone]))
		_firefly_zone.set_item_metadata(_firefly_zone.item_count - 1, zone)
	_firefly_zone.item_selected.connect(func(_i: int) -> void: _save_fireflies())
	add_child(ManagerUi.labeled("集中出現位置", _firefly_zone))
	_firefly_glow_size = ManagerUi.spin(0.1, 0.3, 3.0)
	_firefly_glow_size.value_changed.connect(func(_v: float) -> void: _save_fireflies())
	add_child(ManagerUi.labeled("真光光暈大小(倍)", _firefly_glow_size))
	_firefly_glow_strength = ManagerUi.spin(0.1, 0.3, 3.0)
	_firefly_glow_strength.value_changed.connect(func(_v: float) -> void: _save_fireflies())
	add_child(ManagerUi.labeled("真光光暈濃度(倍)", _firefly_glow_strength))
	_firefly_lights = CheckBox.new()
	_firefly_lights.text = "啟用光源(真光畫光暈;不勾就只畫粒子假光。上面「效能」的總光源開關關著時也一樣只畫粒子)"
	_firefly_lights.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_firefly_lights.toggled.connect(func(_on: bool) -> void: _save_fireflies())
	add_child(_firefly_lights)
	_firefly_status = Label.new()
	_firefly_status.theme_type_variation = AppSettings.MUTED_LABEL
	add_child(_firefly_status)


func _firefly_time_spin(maximum: float) -> SpinBox:
	var spin := ManagerUi.spin(1.0, 0.0, maximum)
	spin.custom_minimum_size.x = 64.0
	spin.value_changed.connect(func(_v: float) -> void: _save_fireflies())
	return spin


## 把畫面上的值存成螢火蟲設定並通知場上的螢火蟲圖層。
func _save_fireflies() -> void:
	if _updating:
		return
	var values := {
		"mode": str(_firefly_mode.get_item_metadata(_firefly_mode.selected)),
		"start": int(_firefly_start_hour.value) * 60 + int(_firefly_start_minute.value), "end": int(_firefly_end_hour.value) * 60 + int(_firefly_end_minute.value),
		"count": int(_firefly_count.value), "real": int(_firefly_real.value), "speed": _firefly_speed.value, "brightness": _firefly_brightness.value, "lights": _firefly_lights.button_pressed,
		"zone": str(_firefly_zone.get_item_metadata(_firefly_zone.selected)), "glow_size": _firefly_glow_size.value, "glow_strength": _firefly_glow_strength.value,
	}
	AppSettings.set_fireflies(values)
	_sync_firefly_widgets()
	get_tree().call_group("fireflies", "refresh_setting")
	message.emit("螢火蟲設定已更新。")


func _load_fireflies() -> void:
	var was_updating := _updating
	_updating = true
	var config := AppSettings.fireflies()
	for i in _firefly_mode.item_count:
		if str(_firefly_mode.get_item_metadata(i)) == str(config["mode"]):
			_firefly_mode.select(i)
	_firefly_start_hour.value = int(config["start"]) / 60
	_firefly_start_minute.value = int(config["start"]) % 60
	_firefly_end_hour.value = int(config["end"]) / 60
	_firefly_end_minute.value = int(config["end"]) % 60
	_firefly_count.value = int(config["count"])
	_firefly_real.value = int(config["real"])
	_firefly_speed.value = float(config["speed"])
	_firefly_brightness.value = float(config["brightness"])
	_firefly_lights.button_pressed = bool(config["lights"])
	_firefly_glow_size.value = float(config["glow_size"])
	_firefly_glow_strength.value = float(config["glow_strength"])
	for i in _firefly_zone.item_count:
		if str(_firefly_zone.get_item_metadata(i)) == str(config["zone"]):
			_firefly_zone.select(i)
	_updating = was_updating
	_sync_firefly_widgets()


## 只有「自己指定時段」才能改起訖時間;真光數量不超過總數;順便顯示現在會不會出現。
func _sync_firefly_widgets() -> void:
	var config := AppSettings.fireflies()
	var custom := str(config["mode"]) == "schedule"
	for spin: SpinBox in [_firefly_start_hour, _firefly_start_minute, _firefly_end_hour, _firefly_end_minute]:
		spin.editable = custom
	_firefly_real.max_value = float(int(config["count"]))
	var minute := AppSettings.minute_of_day_now()
	_firefly_status.text = tr("現在是 %02d:%02d,螢火蟲%s。") % [minute / 60, minute % 60, tr("會出現") if AppSettings.firefly_active(config, minute) else tr("不會出現")]

func _build_appearance() -> void:
	add_child(ManagerUi.heading_with_info("編輯器外觀", "所有視窗化編輯器(桌寵管理、精靈圖編輯器、性格編輯器、測試者面板…)共用的配色、字體與字級,改了立刻套用到開著的視窗。不影響桌寵的對話氣泡(那是每隻桌寵自己的「介面風格」分頁)。"))
	_preset_option = OptionButton.new()
	for id: String in AppSettings.PRESETS:
		_preset_option.add_item(str((AppSettings.PRESETS[id] as Dictionary)["name"]))
		_preset_option.set_item_metadata(_preset_option.item_count - 1, id)
	_preset_option.add_item("自訂")
	_preset_option.set_item_metadata(_preset_option.item_count - 1, CUSTOM_ID)
	_preset_option.item_selected.connect(_on_preset_selected)
	add_child(ManagerUi.labeled("配色組", _preset_option))
	for key in AppSettings.COLOR_KEYS:
		var picker := ColorPickerButton.new()
		picker.edit_alpha = false
		picker.custom_minimum_size = Vector2(120, 28)
		picker.color_changed.connect(func(_color: Color) -> void: _on_color_edited())
		_color_buttons[key] = picker
		add_child(ManagerUi.labeled(str(AppSettings.COLOR_LABELS[key]), picker))
	_font_option = OptionButton.new()
	for font_name in UiFonts.FONT_NAMES:
		_font_option.add_item(font_name)
	_font_option.item_selected.connect(func(_i: int) -> void: _apply_appearance(_current_preset_id()))
	add_child(ManagerUi.labeled("編輯器字體", _font_option))
	_size_spin = ManagerUi.spin(1.0, 11.0, 28.0)
	_size_spin.allow_greater = false
	_size_spin.allow_lesser = false
	_size_spin.value_changed.connect(func(_v: float) -> void: _apply_appearance(_current_preset_id()))
	add_child(ManagerUi.labeled("字級", _size_spin))
	_sample = Label.new()
	_sample.text = "字型預覽:全局設定 — 數值、狀態鏡與性格\nABC abc 123 你好,這是一段範例文字。"
	_sample.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(ManagerUi.labeled("預覽", _sample))
	_title_check = CheckBox.new()
	_title_check.text = "使用自訂標題列(可以調色;取消勾選就用系統標題列。之後新開的視窗生效)"
	_title_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_check.toggled.connect(func(on: bool) -> void:
		if _updating:
			return
		AppSettings.set_themed_title_bar(on)
		_sync_title_widgets()
		message.emit(tr("標題列%s(之後新開的視窗生效)。") % ("改用自訂標題列" if on else "改用系統標題列")))
	add_child(_title_check)
	_title_auto_check = CheckBox.new()
	_title_auto_check.text = "標題列顏色自動跟著配色組"
	_title_auto_check.toggled.connect(func(on: bool) -> void:
		if _updating:
			return
		if not on:
			# 從目前自動算出來的顏色開始改,不會突然變色。
			var current := AppSettings.title_bar_colors()
			AppSettings.set_title_bar_custom(current["bg"], current["text"])
		AppSettings.set_title_bar_auto(on)
		_load_title_colors()
		_sync_title_widgets()
		get_tree().call_group("floating_windows", "refresh_theme")
		message.emit(tr("標題列顏色%s。") % ("自動跟著配色組" if on else "改成自己選的顏色")))
	add_child(_title_auto_check)
	_title_bg_picker = ColorPickerButton.new()
	_title_bg_picker.edit_alpha = false
	_title_bg_picker.custom_minimum_size = Vector2(120, 28)
	_title_bg_picker.color_changed.connect(func(_color: Color) -> void: _on_title_color_edited())
	add_child(ManagerUi.labeled("標題列底色", _title_bg_picker))
	_title_text_picker = ColorPickerButton.new()
	_title_text_picker.edit_alpha = false
	_title_text_picker.custom_minimum_size = Vector2(120, 28)
	_title_text_picker.color_changed.connect(func(_color: Color) -> void: _on_title_color_edited())
	add_child(ManagerUi.labeled("標題列文字", _title_text_picker))
	var copy_colors := ManagerUi.button("複製目前配色代碼")
	copy_colors.tooltip_text = "把目前的六個顏色複製成文字(bg=#… 一行一個),做好新配色組之後貼給開發者加進預設。"
	copy_colors.pressed.connect(func() -> void:
		var lines: PackedStringArray = []
		for key in AppSettings.COLOR_KEYS:
			lines.append("%s=%s" % [key, (_color_buttons[key] as ColorPickerButton).color.to_html(false)])
		# 標題列顏色:自動時是強調色與依亮度選的黑/白,自己選時是選的顏色;都以「目前生效」的為準
		var title_colors := AppSettings.title_bar_colors()
		lines.append("title_bg=%s" % (title_colors["bg"] as Color).to_html(false))
		lines.append("title_text=%s" % (title_colors["text"] as Color).to_html(false))
		DisplayServer.clipboard_set("\n".join(lines))
		message.emit(tr("已複製目前的配色代碼,可以直接貼上。")))
	add_child(copy_colors)
	var reset := ManagerUi.button("還原預設外觀")
	reset.pressed.connect(func() -> void:
		AppSettings.reset_appearance()
		_load_into_widgets()
		get_tree().call_group("floating_windows", "refresh_theme")
		message.emit(tr("已還原預設外觀(筆記本配色、黑體、%d 號字)。") % AppSettings.DEFAULT_FONT_SIZE))
	add_child(reset)


func _current_preset_id() -> String:
	return str(_preset_option.get_item_metadata(_preset_option.selected))


func _load_into_widgets() -> void:
	_updating = true
	_load_audio()
	for i in _language_option.item_count:
		if str(_language_option.get_item_metadata(i)) == AppSettings.language():
			_language_option.select(i)
	_fps_spin.value = AppSettings.max_fps()
	_autostart_check.button_pressed = AutoStart.is_enabled()
	_lights_check.button_pressed = AppSettings.lights_enabled()
	_load_fireflies()
	_on_top_check.button_pressed = AppSettings.floating_on_top()
	var look := AppSettings.appearance()
	for i in _preset_option.item_count:
		if str(_preset_option.get_item_metadata(i)) == str(look["preset"]):
			_preset_option.select(i)
	for key in AppSettings.COLOR_KEYS:
		(_color_buttons[key] as ColorPickerButton).color = (look["colors"] as Dictionary)[key]
	var font_index := UiFonts.FONT_NAMES.find(str(look["font"]))
	_font_option.select(maxi(font_index, 0))
	_size_spin.value = float(look["font_size"])
	_title_check.button_pressed = AppSettings.themed_title_bar()
	_title_auto_check.button_pressed = AppSettings.title_bar_auto()
	_load_title_colors()
	_sync_title_widgets()
	_update_sample()
	_updating = false


## 標題列的兩個色票顯示目前生效的顏色(自動時是算出來的、不能改)。
func _load_title_colors() -> void:
	var was_updating := _updating
	_updating = true
	var colors := AppSettings.title_bar_colors()
	_title_bg_picker.color = colors["bg"]
	_title_text_picker.color = colors["text"]
	_updating = was_updating


## 自訂標題列關掉時,顏色選項整組停用;顏色自動時色票停用。
func _sync_title_widgets() -> void:
	_title_auto_check.disabled = not _title_check.button_pressed
	var editable := _title_check.button_pressed and not _title_auto_check.button_pressed
	_title_bg_picker.disabled = not editable
	_title_text_picker.disabled = not editable


## 使用者改了標題列顏色:存起來、開著的視窗立刻套用。
func _on_title_color_edited() -> void:
	if _updating:
		return
	AppSettings.set_title_bar_custom(_title_bg_picker.color, _title_text_picker.color)
	get_tree().call_group("floating_windows", "refresh_theme")
	message.emit("標題列顏色已更新並存起來。")


func _on_preset_selected(_index: int) -> void:
	if _updating:
		return
	var id := _current_preset_id()
	if id != CUSTOM_ID:
		_updating = true
		var colors: Dictionary = (AppSettings.PRESETS[id] as Dictionary)["colors"]
		for key in AppSettings.COLOR_KEYS:
			(_color_buttons[key] as ColorPickerButton).color = Color.html(str(colors[key])) if colors.has(key) else AppSettings.default_muted((_color_buttons["text"] as ColorPickerButton).color, (_color_buttons["bg"] as ColorPickerButton).color)
		# 選配色組 = 連標題列顏色一起換成這組的(先前自己選過標題列顏色、關掉「自動」的,也改回自動)
		AppSettings.set_title_bar_auto(true)
		_title_auto_check.button_pressed = true
		_sync_title_widgets()
		_updating = false
	_apply_appearance(id)


## 使用者改了某個顏色:配色組自動變成「自訂」。
func _on_color_edited() -> void:
	if _updating:
		return
	_updating = true
	for i in _preset_option.item_count:
		if str(_preset_option.get_item_metadata(i)) == CUSTOM_ID:
			_preset_option.select(i)
	_updating = false
	_apply_appearance(CUSTOM_ID)


func _apply_appearance(preset_id: String) -> void:
	if _updating:
		return
	var colors := {}
	for key in AppSettings.COLOR_KEYS:
		colors[key] = (_color_buttons[key] as ColorPickerButton).color
	AppSettings.save_appearance(preset_id, colors, str(UiFonts.FONT_NAMES[_font_option.selected]), int(_size_spin.value))
	_update_sample()
	_load_title_colors()
	get_tree().call_group("floating_windows", "refresh_theme")
	message.emit("外觀已更新並存起來(所有編輯器視窗立刻套用)。")


func _update_sample() -> void:
	_sample.add_theme_font_override("font", UiFonts.get_font(str(UiFonts.FONT_NAMES[_font_option.selected])))
	_sample.add_theme_font_size_override("font_size", int(_size_spin.value))
