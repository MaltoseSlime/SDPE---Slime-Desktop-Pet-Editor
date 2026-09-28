class_name ValueEditorTab
extends HSplitContainer
## 數值管理分頁(企劃書第六章「數值屬性定義與自訂圖示」+「Status 菜單白名單」):
## 左邊列出這隻桌寵的局部數值與全域數值,右邊編輯內部名稱、顯示名稱、預設/上下限/步進、小圖示,
## 以及是否在 Status 面板顯示(預設隱藏)、排序權重、文字/進度條、前後綴。改動即時生效(共用同一份定義資源),
## 存檔由管理視窗的「儲存」按鈕(或關閉視窗時)寫進 user://profiles/。

signal changed
signal message(text: String)

const DISPLAY_MODES: Array[String] = ["純文字", "進度條", "量表(漸層色+三角形標記,需要上下限)"]

var _pet: Node
var _state: Node
var _entries: Array[PetValueDef] = []
var _list: ItemList
var _form: VBoxContainer
var _loading := false

var _scope_label: Label
var _key_edit: LineEdit
var _display_edit: LineEdit
var _default_spin: SpinBox
var _min_spin: SpinBox
var _max_spin: SpinBox
var _no_min_check: CheckBox
var _no_max_check: CheckBox
var _step_spin: SpinBox
var _current_spin: SpinBox
var _icon_edit: LineEdit
var _show_check: CheckBox
var _weight_spin: SpinBox
var _mode_option: OptionButton
var _gauge_reverse_check: CheckBox
var _prefix_edit: LineEdit
var _suffix_edit: LineEdit


func _ready() -> void:
	name = "數值"
	_state = get_node("/root/DesktopShellState")
	_build_list_side()
	_build_form_side()


func set_pet(pet: Node) -> void:
	_pet = pet
	_rebuild_list()


func _build_list_side() -> void:
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 230.0
	add_child(side)
	side.add_child(ManagerUi.heading("數值列表"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	side.add_child(_list)
	var row1 := HBoxContainer.new()
	var add_local := ManagerUi.button("新增局部")
	add_local.pressed.connect(_add_value.bind(false))
	var add_global := ManagerUi.button("新增全域")
	add_global.pressed.connect(_add_value.bind(true))
	row1.add_child(add_local)
	row1.add_child(add_global)
	side.add_child(row1)
	var delete := ManagerUi.button("刪除選取的數值")
	delete.pressed.connect(_delete_selected)
	side.add_child(delete)


func _build_form_side() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)

	_form.add_child(ManagerUi.heading("基本設定"))
	_scope_label = Label.new()
	_form.add_child(ManagerUi.labeled("作用域", _scope_label))
	_key_edit = ManagerUi.line_edit("內部名稱(積木與對話插值用)")
	_key_edit.text_submitted.connect(func(_t: String) -> void: _commit_key())
	_key_edit.focus_exited.connect(_commit_key)
	_form.add_child(ManagerUi.labeled("內部名稱", _key_edit))
	_display_edit = ManagerUi.line_edit("空白就顯示內部名稱")
	_display_edit.text_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("顯示名稱", _display_edit))
	_default_spin = ManagerUi.spin(0.1)
	_default_spin.value_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("初始預設值", _default_spin))
	_min_spin = ManagerUi.spin(0.1)
	_min_spin.value_changed.connect(_on_field_changed)
	_no_min_check = CheckBox.new()
	_no_min_check.text = "無下限"
	_no_min_check.toggled.connect(_on_field_changed)
	var min_row := ManagerUi.labeled("最小值", _min_spin)
	min_row.add_child(_no_min_check)
	_form.add_child(min_row)
	_max_spin = ManagerUi.spin(0.1)
	_max_spin.value_changed.connect(_on_field_changed)
	_no_max_check = CheckBox.new()
	_no_max_check.text = "無上限"
	_no_max_check.toggled.connect(_on_field_changed)
	var max_row := ManagerUi.labeled("最大值", _max_spin)
	max_row.add_child(_no_max_check)
	_form.add_child(max_row)
	_step_spin = ManagerUi.spin(0.001, 0.001, 1000.0)
	_step_spin.value_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("步進量", _step_spin))
	_current_spin = ManagerUi.spin(0.1)
	_current_spin.value_changed.connect(_on_current_changed)
	_form.add_child(ManagerUi.labeled("目前值(測試用)", _current_spin))

	_form.add_child(HSeparator.new())
	_form.add_child(ManagerUi.heading("Status 面板"))
	_show_check = CheckBox.new()
	_show_check.text = "在 Status 面板中顯示(預設隱藏)"
	_show_check.toggled.connect(_on_field_changed)
	_form.add_child(_show_check)
	_weight_spin = ManagerUi.spin(1.0)
	_weight_spin.value_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("排序權重(小的在上)", _weight_spin))
	_mode_option = OptionButton.new()
	for mode_name in DISPLAY_MODES:
		_mode_option.add_item(mode_name)
	_mode_option.item_selected.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("顯示模式", _mode_option))
	_gauge_reverse_check = CheckBox.new()
	_gauge_reverse_check.text = "量表反向(數值高是不好的,例如疲勞:高=紅、低=綠)"
	_gauge_reverse_check.toggled.connect(_on_field_changed)
	_form.add_child(_gauge_reverse_check)
	_prefix_edit = ManagerUi.line_edit("例如 ×")
	_prefix_edit.text_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("前綴", _prefix_edit))
	_suffix_edit = ManagerUi.line_edit("例如 G 或 %")
	_suffix_edit.text_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("後綴", _suffix_edit))
	_icon_edit = ManagerUi.line_edit("小圖示(選填,PNG,最大 256×256)")
	_icon_edit.editable = false
	var icon_row := ManagerUi.labeled("小圖示", _icon_edit)
	var browse := ManagerUi.button("選擇…")
	browse.pressed.connect(_browse_icon)
	var clear_icon := ManagerUi.button("清除")
	clear_icon.pressed.connect(_set_icon.bind(""))
	icon_row.add_child(browse)
	icon_row.add_child(clear_icon)
	_form.add_child(icon_row)
	_form.visible = false


# --- 列表 ---

func _rebuild_list(select: PetValueDef = null) -> void:
	_entries.clear()
	_list.clear()
	if _pet == null:
		_form.visible = false
		return
	for def: PetValueDef in _pet.value_defs:
		_entries.append(def)
	for def: PetValueDef in _state.global_value_defs:
		_entries.append(def)
	for def in _entries:
		_list.add_item(_item_text(def))
	var index := _entries.find(select) if select != null else -1
	if index < 0 and not _entries.is_empty():
		index = 0
	if index >= 0:
		_list.select(index)
		_on_item_selected(index)
	else:
		_form.visible = false


func _item_text(def: PetValueDef) -> String:
	return "[%s] %s" % ["全域" if def.is_global else "局部", def.label()]


func _selected() -> PetValueDef:
	var picked := _list.get_selected_items()
	if picked.is_empty() or picked[0] >= _entries.size():
		return null
	return _entries[picked[0]]


func _on_item_selected(index: int) -> void:
	_load_form(_entries[index])


func _load_form(def: PetValueDef) -> void:
	_loading = true
	_form.visible = true
	_scope_label.text = "全域(所有桌寵共用)" if def.is_global else "局部(只屬於這隻桌寵)"
	_key_edit.text = def.key
	_display_edit.text = def.display_name
	_default_spin.value = def.default_value
	_no_min_check.button_pressed = def.min_value < -1.0e8
	_min_spin.value = 0.0 if def.min_value < -1.0e8 else def.min_value
	_min_spin.editable = not _no_min_check.button_pressed
	_no_max_check.button_pressed = not def.has_max()
	_max_spin.value = 100.0 if not def.has_max() else def.max_value
	_max_spin.editable = not _no_max_check.button_pressed
	_step_spin.value = def.step
	_current_spin.value = ValueGateway.get_value(_pet, def.key)
	_show_check.button_pressed = def.show_in_status
	_weight_spin.value = def.sort_weight
	_mode_option.select(int(def.display_mode))
	_gauge_reverse_check.button_pressed = def.gauge_reverse
	_prefix_edit.text = def.prefix
	_suffix_edit.text = def.suffix
	_icon_edit.text = def.icon_path
	_loading = false


# --- 編輯 ---

## 表單任一欄位改變:整份寫回選取的定義(除了內部名稱,那個要驗證,見 _commit_key)。
func _on_field_changed(_value: Variant = null) -> void:
	var def := _selected()
	if _loading or def == null:
		return
	def.display_name = _display_edit.text
	def.min_value = -1.0e9 if _no_min_check.button_pressed else _min_spin.value
	def.max_value = 1.0e9 if _no_max_check.button_pressed else maxf(_max_spin.value, def.min_value)
	_min_spin.editable = not _no_min_check.button_pressed
	_max_spin.editable = not _no_max_check.button_pressed
	def.default_value = def.clamp_value(_default_spin.value)
	def.step = maxf(_step_spin.value, 0.001)
	def.show_in_status = _show_check.button_pressed
	def.sort_weight = int(_weight_spin.value)
	def.display_mode = _mode_option.selected if _mode_option.selected >= 0 and _mode_option.selected < DISPLAY_MODES.size() else PetValueDef.DisplayMode.TEXT
	def.gauge_reverse = _gauge_reverse_check.button_pressed
	def.prefix = _prefix_edit.text
	def.suffix = _suffix_edit.text
	_list.set_item_text(_entries.find(def), _item_text(def))
	# 上下限改了,已存的目前值也要重新夾限。
	ValueGateway.set_value(_pet, def.key, ValueGateway.get_value(_pet, def.key))
	changed.emit()


## 內部名稱要唯一(局部與全域之間也不能重複,免得查找時有歧義);改名時把已存的值一起搬過去。
func _commit_key() -> void:
	var def := _selected()
	if _loading or def == null:
		return
	var new_key := _key_edit.text.strip_edges()
	if new_key == def.key:
		return
	if new_key == "":
		message.emit("內部名稱不能是空的,已還原。")
		_key_edit.text = def.key
		return
	for other in _entries:
		if other != def and other.key == new_key:
			message.emit(tr("已經有叫「%s」的數值,請換一個名稱,已還原。") % new_key)
			_key_edit.text = def.key
			return
	var store: Dictionary = _state.global_values if def.is_global else _pet.local_values
	if store.has(def.key):
		store[new_key] = store[def.key]
		store.erase(def.key)
	def.key = new_key
	_list.set_item_text(_entries.find(def), _item_text(def))
	changed.emit()


func _on_current_changed(value: float) -> void:
	var def := _selected()
	if _loading or def == null:
		return
	ValueGateway.set_value(_pet, def.key, value)


func _add_value(is_global: bool) -> void:
	if _pet == null:
		return
	var def := PetValueDef.new()
	def.is_global = is_global
	var index := 1
	while _key_taken(tr("新數值%d") % index):
		index += 1
	def.key = tr("新數值%d") % index
	def.min_value = 0.0
	def.max_value = 100.0
	if is_global:
		_state.global_value_defs.append(def)
	else:
		_pet.value_defs.append(def)
	ValueGateway.init_defaults(_pet)
	_rebuild_list(def)
	changed.emit()


func _key_taken(key: String) -> bool:
	for def in _entries:
		if def.key == key:
			return true
	return false


func _delete_selected() -> void:
	var def := _selected()
	if def == null:
		return
	var store: Dictionary = _state.global_values if def.is_global else _pet.local_values
	store.erase(def.key)
	if def.is_global:
		_state.global_value_defs.erase(def)
	else:
		_pet.value_defs.erase(def)
	_rebuild_list()
	changed.emit()


# --- 圖示 ---

func _browse_icon() -> void:
	FloatingWindow.native_file_dialog("選擇小圖示", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.png,*.webp,*.jpg;圖片"]),
			func(paths: PackedStringArray) -> void: _set_icon(paths[0]), get_window().get_window_id())


func _set_icon(path: String) -> void:
	var def := _selected()
	if def == null:
		return
	if def.set_icon_path(path):
		_icon_edit.text = def.icon_path
		changed.emit()
	else:
		message.emit("無法載入這張圖示(檔案毀損、找不到,或超過 256×256),已保留原本的圖示。")
