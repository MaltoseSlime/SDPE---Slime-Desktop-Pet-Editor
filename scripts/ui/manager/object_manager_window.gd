class_name ObjectManagerWindow
extends FloatingWindow
## 「交互物件管理」視窗(系統匣/懸浮球「交互物件管理…」):桌寵會去互動的東西集中在這裡,一個視窗兩個頁籤——
## 「家具庫」(FurnitureLibraryTab)與「道具庫」(PropLibraryTab)。2026-10-13 使用者要求把原本各自獨立的
## 「家具庫」「道具管理」兩個視窗合併成這個(做法比照桌寵管理:一個視窗多個頁籤)。
## 兩個頁籤的存檔方式照舊不一樣:道具庫改了立刻存;家具庫的欄位要按底下浮動列的「儲存」才寫進磁碟,
## 所以關視窗前的「尚未儲存的變更」確認只跟家具庫有關(見 FurnitureLibraryTab._request_close)。

signal edit_prop_sprite_requested(prop_id: String)
signal edit_furniture_sprite_requested(furniture_id: String)

var furniture_tab: FurnitureLibraryTab
var prop_tab: PropLibraryTab
var _tabs: TabContainer


func setup(prop_manager: PropManager, furniture_manager: FurnitureManager) -> void:
	setup_floating(tr("交互物件管理"), Vector2i(800, 700), Vector2i(780, 460))
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	background.add_child(margin)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_tabs)
	furniture_tab = FurnitureLibraryTab.new()
	_tabs.add_child(furniture_tab)
	furniture_tab.setup(furniture_manager)
	prop_tab = PropLibraryTab.new()
	_tabs.add_child(prop_tab)
	prop_tab.setup(prop_manager)
	furniture_tab.edit_sprite_requested.connect(func(id: String) -> void: edit_furniture_sprite_requested.emit(id))
	prop_tab.edit_sprite_requested.connect(func(id: String) -> void: edit_prop_sprite_requested.emit(id))
	furniture_tab.close_confirmed.connect(queue_free)
	# 家具容器的內容物從道具庫挑:在道具庫新增/改名/刪除之後切回家具庫,下拉選單要是最新的。
	_tabs.tab_changed.connect(func(index: int) -> void:
		if _tabs.get_tab_control(index) == furniture_tab:
			furniture_tab._reload_container_props())


## 切到指定的頁籤:"furniture"(家具庫)或 "props"(道具庫)。
func show_tab(which: String) -> void:
	_tabs.current_tab = _tabs.get_tab_idx_from_control(prop_tab if which == "props" else furniture_tab)


func current_tab_key() -> String:
	return "props" if _tabs.get_current_tab_control() == prop_tab else "furniture"


func refresh_theme() -> void:
	super.refresh_theme()
	if furniture_tab != null:
		furniture_tab.refresh_theme()


## 叉叉:家具庫有未儲存的變更就先問(儲存後離開/不儲存離開/取消),沒有就直接關;兩種情況都會順便關掉家具編輯模式。
func _request_close() -> void:
	furniture_tab._request_close()
