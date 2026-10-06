class_name ManagerWindow
extends FloatingWindow
## 桌寵管理視窗:數值、狀態鏡、性格、介面與自動行為、交互行為、記憶(程式層級的設定在「全局設定」視窗)。視窗管理(置頂、標題列位置、可拖曳的自畫標題列、✕)見 FloatingWindow。
## 改動即時生效;「儲存」寫進 user://profiles/。關閉(叉叉)時如果有未儲存的變更會問:儲存後離開/不儲存離開/取消。
## 「不儲存離開」會把所有改動還原成開啟視窗時(或上次儲存時)的樣子。

signal saved

const FLOATING_BAR_HEIGHT := 46

var _pet_option: OptionButton
var _pets: Array[Node] = []
var _value_tab: ValueEditorTab
var _lens_tab: LensEditorTab
var _style_tab: StyleEditorTab
var _interaction_tab: InteractionTab
var _memory_tab: MemoryTab
var _personality_tab: PersonalityTab
var _status_label: Label
var _bar_style: StyleBoxFlat
var _dirty := false
var _snapshots: Dictionary = {}
var _global_snapshot: Dictionary = {}
var _confirm: ConfirmationDialog
var _apply_guard: ConfirmationDialog


func setup() -> void:
	setup_floating(tr("桌寵管理"), Vector2i(1000, 700), Vector2i(860, 520))
	_build()
	_populate_pets()
	_take_snapshots()


## 角色庫「外觀編輯」旁邊新增的「桌寵管理」按鈕用:只編輯這一隻(角色庫自動生成、不在桌面上的隱藏臨時實例,
## 見 Pet.ghost_edit),不掃 "pets" 群組、不給切換桌寵的下拉選單(只有一隻可選沒有意義,乾脆藏起來)。
func setup_for_single_pet(pet: Node, title: String) -> void:
	setup_floating(title, Vector2i(1000, 700), Vector2i(860, 520))
	_build()
	_pet_option.visible = false
	_pets = [pet]
	_on_pet_selected(0)
	_take_snapshots()


func _build() -> void:
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	# 底下留出浮動按鈕列的位置(按鈕列本身是釘在視窗底部的浮動面板,見 _build_floating_bar)。
	margin.add_theme_constant_override("margin_bottom", FLOATING_BAR_HEIGHT + 6)
	background.add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)

	var top := HBoxContainer.new()
	var pet_label := Label.new()
	pet_label.text = tr("桌寵:")
	top.add_child(pet_label)
	_pet_option = OptionButton.new()
	_pet_option.custom_minimum_size.x = 220.0
	_pet_option.item_selected.connect(_on_pet_selected)
	top.add_child(_pet_option)
	root.add_child(top)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	_value_tab = ValueEditorTab.new()
	_lens_tab = LensEditorTab.new()
	_style_tab = StyleEditorTab.new()
	_interaction_tab = InteractionTab.new()
	_memory_tab = MemoryTab.new()
	_personality_tab = PersonalityTab.new()
	# 2026-10-06 順序調整:性格放最前面(初次製作的使用者先看到可以設定性格),數值/狀態鏡移到交互行為右邊。
	tabs.add_child(_personality_tab)
	tabs.add_child(_style_tab)
	tabs.add_child(_interaction_tab)
	tabs.add_child(_value_tab)
	tabs.add_child(_lens_tab)
	# 記憶分頁內容很長:包一層捲動區塊(分頁標題用捲動區塊的名字,要和分頁自己設的名字一樣)。
	var memory_scroll := ScrollContainer.new()
	memory_scroll.name = "記憶"
	memory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_memory_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	memory_scroll.add_child(_memory_tab)
	tabs.add_child(memory_scroll)
	for tab in [_value_tab, _lens_tab, _personality_tab, _style_tab, _interaction_tab, _memory_tab]:
		tab.changed.connect(_mark_dirty)
		tab.message.connect(_show_message)
	# 交互行為分頁的「基本反應對話」讀的是性格分頁的資料:切過去性格分頁改了東西、再切回來,重新載入才看得到最新內容。
	# 記憶分頁也放了一份性格檔匯入按鈕(2026-09-30 使用者要求),同樣道理:切回性格分頁要重新整理下拉選單才看得到新匯入的項目。
	tabs.tab_changed.connect(func(_i: int) -> void:
		_interaction_tab._reload()
		_personality_tab._reload_options())

	_build_floating_bar()

	_confirm = ConfirmationDialog.new()
	# 不設 always_on_top,見 manager_ui.gd 的 ask_name() 說明(跟置頂衝突,會把視窗卡死)。
	_confirm.title = tr("尚未儲存的變更")
	_confirm.dialog_text = "檢測到尚未儲存的變更,是否儲存後離開?"
	_confirm.ok_button_text = "儲存後離開"
	_confirm.cancel_button_text = "取消"
	_confirm.add_button("不儲存離開", true, "discard")
	_confirm.confirmed.connect(func() -> void: _request_save(queue_free))
	_confirm.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			_discard_and_close())
	add_child(_confirm)


## 儲存 / 儲存並關閉 / 不儲存並關閉 + 狀態文字:釘在視窗底部的浮動面板(視窗不夠高、分頁內容很長時,按鈕還是看得到)。
## 底部按鈕列的底色與邊線跟著編輯器配色(不再是固定深色)。
func _restyle_bar() -> void:
	var colors: Dictionary = AppSettings.appearance()["colors"]
	_bar_style.bg_color = (colors["bg"] as Color).lerp(colors["text"], 0.06)
	_bar_style.border_color = AppSettings.ink(0.18)


func refresh_theme() -> void:
	super.refresh_theme()
	_restyle_bar()


func _build_floating_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "FloatingButtons"
	bar.custom_minimum_size.y = FLOATING_BAR_HEIGHT
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -FLOATING_BAR_HEIGHT
	var style := StyleBoxFlat.new()
	_bar_style = style
	_restyle_bar()
	style.border_width_top = 1
	style.set_content_margin_all(6.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	bar.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	_status_label = Label.new()
	_status_label.theme_type_variation = AppSettings.MUTED_LABEL
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_status_label)
	var save := ManagerUi.button("儲存")
	save.pressed.connect(func() -> void: _request_save())
	var save_close := ManagerUi.button("儲存並關閉")
	save_close.pressed.connect(func() -> void: _request_save(queue_free))
	var discard := ManagerUi.button("不儲存並關閉")
	discard.pressed.connect(_discard_and_close)
	for button in [save, save_close, discard]:
		row.add_child(button)
	add_child(bar)


func _populate_pets() -> void:
	_pets.clear()
	_pet_option.clear()
	for pet in get_tree().get_nodes_in_group("pets"):
		_pets.append(pet)
		_pet_option.add_item(pet.get_label())
	if _pets.is_empty():
		_show_message("場上目前沒有桌寵。")
		return
	_pet_option.select(0)
	_on_pet_selected(0)


func _on_pet_selected(index: int) -> void:
	_value_tab.set_pet(_pets[index])
	_lens_tab.set_pet(_pets[index])
	_style_tab.set_pet(_pets[index])
	_interaction_tab.set_pet(_pets[index])
	_memory_tab.set_pet(_pets[index])
	_personality_tab.set_pet(_pets[index])


func _mark_dirty() -> void:
	_dirty = true
	_status_label.text = tr("有尚未儲存的變更。")


func _show_message(text: String) -> void:
	_status_label.text = text


## 記下目前(開啟視窗時或剛儲存)的設定,「不儲存離開」時還原用。
func _take_snapshots() -> void:
	_snapshots.clear()
	for pet in _pets:
		_snapshots[pet] = PetProfile.snapshot_pet(pet)
	_global_snapshot = PetProfile.snapshot_globals()


## 按「儲存」的入口:性格分頁選了性格卻還沒按「套用」時先問(套用並儲存 / 不套用直接儲存 / 取消),免得存了才發現設定沒生效。after 是存完之後要做的事(例如關視窗)。
func _request_save(after := Callable()) -> void:
	if not _personality_tab.has_pending_apply():
		_save()
		if after.is_valid():
			after.call()
		return
	if is_instance_valid(_apply_guard):
		return
	_apply_guard = ConfirmationDialog.new()
	# 不設 always_on_top,見 manager_ui.gd 的 ask_name() 說明(跟置頂衝突,會把視窗卡死)。
	_apply_guard.title = tr("性格還沒套用")
	_apply_guard.dialog_text = "「性格」分頁選了性格,但還沒按「套用」,存下去桌寵不會有變化。\n要先套用再儲存嗎?"
	_apply_guard.ok_button_text = "套用並儲存"
	_apply_guard.cancel_button_text = "取消"
	_apply_guard.add_button("不套用,直接儲存", true, "skip")
	_apply_guard.min_size = Vector2i(460, 170)
	_apply_guard.confirmed.connect(func() -> void:
		_personality_tab._apply()
		_save()
		if after.is_valid():
			after.call())
	_apply_guard.custom_action.connect(func(action: StringName) -> void:
		if action == &"skip":
			_apply_guard.hide()
			_save()
			if after.is_valid():
				after.call()
			_apply_guard.queue_free())
	_apply_guard.confirmed.connect(_apply_guard.queue_free)
	_apply_guard.canceled.connect(_apply_guard.queue_free)
	add_child(_apply_guard)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), _apply_guard)


func _save() -> void:
	var failed := PetProfile.save_globals() != OK
	for pet in _pets:
		if is_instance_valid(pet) and PetProfile.save_pet(pet) != OK:
			failed = true
	_dirty = false
	_take_snapshots()
	_status_label.text = tr("儲存失敗,請檢查磁碟空間或權限。") if failed else tr("已儲存。")
	saved.emit()


## 叉叉:沒有未儲存的變更就直接關;有的話問要不要存。
func _request_close() -> void:
	if not _dirty:
		queue_free()
		return
	FloatingWindow.popup_child_dialog(self, get_window(), _confirm)


## 不儲存離開:把每隻桌寵與全域數值還原成上次快照,再關閉。
func _discard_and_close() -> void:
	PetProfile.restore_globals(_global_snapshot)
	for pet in _snapshots:
		if is_instance_valid(pet):
			PetProfile.restore_pet(pet, _snapshots[pet])
	_dirty = false
	queue_free()
