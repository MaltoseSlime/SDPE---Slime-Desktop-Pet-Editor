class_name ReservedValuesWindow
extends FloatingWindow
## 列出系統內建、名稱固定被讀取的數值(見 ReservedPetValues),給使用者在數值管理分頁查詢用,避免自己的
## 數值取同樣的名字卻不知道會被引擎自動讀取。目前只有「好感度」一筆,之後 ReservedPetValues.ENTRIES
## 增加會自動跟著列出來,不用改這個檔案。

var _list: VBoxContainer


func setup() -> void:
	setup_floating(tr("系統保留數值"), Vector2i(480, 320), Vector2i(360, 220))
	_build()


func _build() -> void:
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	background.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)
	var intro := Label.new()
	intro.text = tr("這些數值名稱已經被引擎用來驅動內建行為,幫自己的數值取名時請避開(或清楚知道會疊加這個效果)。")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.theme_type_variation = AppSettings.MUTED_LABEL
	page.add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	for entry: Dictionary in ReservedPetValues.ENTRIES:
		_list.add_child(_row(entry))


func _row(entry: Dictionary) -> Control:
	var title := "%s (%s)" % [str(entry.get("key", "")), str(entry.get("en", ""))]
	return ManagerUi.heading_with_info(title, str(entry.get("effect", "")))


func row_count() -> int:
	return _list.get_child_count()
