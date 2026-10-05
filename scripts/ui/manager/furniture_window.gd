class_name FurnitureWindow
extends FloatingWindow
## 家具庫視窗(系統匣「家具庫…」,第一批只有純裝飾:見 furniture_def.gd 檔頭)。左邊是家具清單(從內建模板新增、刪除),
## 右邊編輯選中的家具(名稱、觸發方式、縮放、標籤、容器內容物,見 FurnitureDef.container_items)。進階貼圖(normal / conditional / interacted 三個狀態)、
## 坐/躺位置(錨點)與光源都在精靈圖編輯器的家具區編輯(見 PackEditorWindow._build_furniture_panel)——那邊有畫布可以
## 直接對著貼圖拖曳,看得到實際位置,不像這裡只能打數字,2026-09-22 從這裡搬過去的。
## 2026-09-30 改成跟桌寵管理一樣的「儲存/儲存並關閉/不儲存並關閉」:欄位編輯只改記憶體裡的 FurnitureDef,
## 按浮動列的「儲存」才真的寫進 user://furniture/<家具>/furniture.json 並同步桌面上已放置的實例
## (FurnitureManager.refresh_def)。新增家具(從模板)、刪除家具(搬到備份)這兩個操作本身就是立即生效的
## 檔案系統操作,跟一般欄位編輯是不同類別,維持原本按下去就動作、不用等「儲存」。

var _manager: FurnitureManager
## 記憶體裡改過、還沒按「儲存」寫回磁碟的家具 id。Save 時逐一寫回、同步桌面實例。
var _dirty_ids: Dictionary = {}
var _dirty := false
var _status_bar: Label
var _confirm: ConfirmationDialog
var _bar_style: StyleBoxFlat
var _list: ItemList
var _defs: Array[FurnitureDef] = []
var _current: FurnitureDef
var _form_root: Control
var _empty_label: Label
var _status: Label
var _template_option: OptionButton
var _updating := false

var _name_edit: LineEdit
var _condition_option: OptionButton
var _time_row: Control
var _time_start_hour: SpinBox
var _time_start_minute: SpinBox
var _time_end_hour: SpinBox
var _time_end_minute: SpinBox
var _action_row: Control
var _action_edit: LineEdit
var _scale_spin: SpinBox
var _tags_list: ItemList
var _sprite_label: Label
var _delete_button: Button
var _place_button: Button
var _edit_mode_button: CheckButton
var _container_prop_option: OptionButton
var _container_capacity_spin: SpinBox
var _container_add: Button
var _container_list: ItemList
var _container_delete: Button
var _container_props: Array[PropDef] = []
var _placed_list: ItemList
var _placed_move_up: Button
var _placed_move_down: Button
var _placed_remove: Button
## 效果(見 FurnitureDef.aura_effects):目標/篩選的 OptionButton 選項統一用 metadata 編碼成
## "stat:<key>" 或 "value:local"/"value:global","不篩選" 用 "none"(只有篩選用得到這個選項)。
var _aura_list: ItemList
var _aura_target_option: OptionButton
var _aura_target_value_key: LineEdit
var _aura_target_number: SpinBox
var _aura_filter_option: OptionButton
var _aura_filter_value_key: LineEdit
var _aura_filter_op_option: OptionButton
var _aura_filter_number: SpinBox
var _aura_add: Button
var _aura_delete: Button
## 性格相關數值(stat)的下拉選單顯示文字;鍵是 FurnitureDef.AURA_STAT_KEYS 的元素。
const AURA_STAT_LABELS := {
	"vitality.energy": "精力", "vitality.mood": "心情",
	"vitality.fatigue_rate": "疲勞速率(每分鐘消耗精力的速度)", "vitality.rest_recovery_rate": "休息恢復速率",
	"vitality.tired_threshold": "疲勞閾值(精力低於這個值就算疲勞,調高 = 更容易疲勞/入睡)",
	"vitality.exhausted_threshold": "精疲力竭閾值",
	"vitality.mood_happy_threshold": "心情愉快閾值", "vitality.mood_angry_threshold": "心情生氣閾值",
	"vitality.mood_sad_threshold": "心情低落閾值",
	"sociability": "社交意願(影響主動邀約/跟隨機率)", "game_refuse_base": "拒絕遊戲的基礎機率",
}
## 使用者要在精靈圖編輯器的家具區編輯這件家具的進階貼圖(參數 = 家具資料夾名稱)。
signal edit_sprite_requested(furniture_id: String)


const FLOATING_BAR_HEIGHT := 46


func setup(manager: FurnitureManager) -> void:
	_manager = manager
	setup_floating("家具庫", Vector2i(760, 620), Vector2i(600, 420))
	_manager.placed_changed.connect(_refresh_placed_list)
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	# 底下留出浮動存檔列的位置(見 _build_floating_bar),不然分頁內容長的時候會被蓋住。
	margin.add_theme_constant_override("margin_bottom", FLOATING_BAR_HEIGHT + 6)
	background.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	margin.add_child(page)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	body.add_child(_build_list_column())
	body.add_child(_build_form_column())
	_status = Label.new()
	_status.theme_type_variation = AppSettings.MUTED_LABEL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "貼圖(平時的樣子、條件成立時的樣子、以後給桌寵使用時的樣子)在「編輯素材」的精靈圖編輯器裡準備:動作槽 normal / conditional / interacted。"
	page.add_child(_status)
	_build_floating_bar()
	_confirm = ConfirmationDialog.new()
	# 不設 always_on_top,見 manager_ui.gd 的 ask_name() 說明(跟置頂衝突,會把視窗卡死)。
	_confirm.title = "尚未儲存的變更"
	_confirm.dialog_text = "檢測到尚未儲存的變更,是否儲存後離開?"
	_confirm.ok_button_text = "儲存後離開"
	_confirm.cancel_button_text = "取消"
	_confirm.add_button("不儲存離開", true, "discard")
	_confirm.confirmed.connect(func() -> void: _request_save(_close_now))
	_confirm.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			_discard_and_close())
	add_child(_confirm)
	_reload_container_props()
	reload()


## 浮動列底色跟邊線跟著編輯器配色走(不是寫死的深色),使用者在「全局設定」改配色時要能即時跟著換。
func _restyle_bar() -> void:
	if _bar_style == null:
		return
	var colors: Dictionary = AppSettings.appearance()["colors"]
	_bar_style.bg_color = (colors["bg"] as Color).lerp(colors["text"], 0.06)
	_bar_style.border_color = AppSettings.ink(0.18)


func refresh_theme() -> void:
	super.refresh_theme()
	_restyle_bar()


## 儲存 / 儲存並關閉 / 不儲存並關閉 + 狀態文字:釘在視窗底部的浮動面板,跟桌寵管理視窗同一套做法
## (見 ManagerWindow._build_floating_bar)。
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
	_status_bar = Label.new()
	_status_bar.theme_type_variation = AppSettings.MUTED_LABEL
	_status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_bar.clip_text = true
	_status_bar.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_status_bar)
	var save := ManagerUi.button("儲存")
	save.pressed.connect(func() -> void: _request_save())
	var save_close := ManagerUi.button("儲存並關閉")
	save_close.pressed.connect(func() -> void: _request_save(_close_now))
	var discard := ManagerUi.button("不儲存並關閉")
	discard.pressed.connect(_discard_and_close)
	for button in [save, save_close, discard]:
		row.add_child(button)
	add_child(bar)


func _mark_dirty(id: String) -> void:
	_dirty = true
	_dirty_ids[id] = true
	_status_bar.text = "有尚未儲存的變更。"


func _request_save(after := Callable()) -> void:
	_save_all()
	if after.is_valid():
		after.call()


## 把記憶體裡改過的家具逐一寫回磁碟,並同步桌面上已放置的同一件家具實例。
func _save_all() -> void:
	var failed := false
	for id: String in _dirty_ids.keys():
		var def := _def_by_id(id)
		if def == null:
			continue
		if FurnitureLibrary.save_def(def) != "":
			failed = true
		if _manager != null:
			_manager.refresh_def(id)
	_dirty_ids.clear()
	_dirty = false
	_status_bar.text = "存檔失敗,請檢查磁碟空間或權限。" if failed else "已儲存。"


func _def_by_id(id: String) -> FurnitureDef:
	for def in _defs:
		if def.id == id:
			return def
	return null


## 真正關閉視窗前的共用收尾:關掉編輯模式,不留著一直能拖桌面上的家具卻沒地方能把模式關掉。
func _close_now() -> void:
	if _manager != null:
		_manager.set_edit_mode(false)
	queue_free()


## 不儲存離開:記憶體裡的修改本來就沒寫進磁碟(見檔頭說明),直接關掉視窗、丟掉這份記憶體副本就好。
func _discard_and_close() -> void:
	_dirty_ids.clear()
	_dirty = false
	_close_now()


func _build_list_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 210.0
	column.add_child(ManagerUi.heading_with_info("家具庫", "純裝飾的家具:滑鼠完全穿透,不會擋住桌面。從下面的模板新增一個,再在右邊改名字、設定觸發方式,「編輯素材」放圖進去。桌寵坐下/躺下/使用家具是之後才會做的功能,這批還不能互動。"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	column.add_child(_list)
	_template_option = OptionButton.new()
	for template_id: String in FurnitureLibrary.TEMPLATES:
		_template_option.add_item(str((FurnitureLibrary.TEMPLATES[template_id] as Dictionary)["label"]))
		_template_option.set_item_metadata(_template_option.item_count - 1, template_id)
	column.add_child(ManagerUi.labeled("模板", _template_option))
	var add_button := ManagerUi.button("＋ 新增家具")
	add_button.pressed.connect(_on_add_pressed)
	column.add_child(add_button)
	_delete_button = ManagerUi.button("刪除(搬到備份)")
	_delete_button.pressed.connect(_on_delete_pressed)
	column.add_child(_delete_button)
	column.add_child(HSeparator.new())
	column.add_child(ManagerUi.heading_with_info("編輯桌面上的家具", "開啟「家具編輯模式」才能把家具放到桌面、搬動已經放好的、右鍵移除(定義還在家具庫裡,之後可以再放一次);平常家具是純裝飾,滑鼠完全穿透。編輯模式開著時桌面上會多一塊「家具欄」,把裡面的圖示拖出來就是放置。下面的清單是目前桌面上的家具,由上到下 = 由底到面(清單愈下面的蓋住愈上面的),用 ▲▼ 調整。"))
	_edit_mode_button = CheckButton.new()
	_edit_mode_button.text = "家具編輯模式"
	_edit_mode_button.toggled.connect(_on_edit_mode_toggled)
	column.add_child(_edit_mode_button)
	_placed_list = ItemList.new()
	_placed_list.custom_minimum_size.y = 110.0
	_placed_list.item_selected.connect(func(_i: int) -> void: _sync_placed_buttons())
	column.add_child(_placed_list)
	var placed_buttons := HBoxContainer.new()
	_placed_move_up = ManagerUi.button("▲")
	_placed_move_up.tooltip_text = "往上一層(蓋住原本在它上面的家具;只影響家具彼此,不影響桌寵或介面)。"
	_placed_move_up.pressed.connect(func() -> void: _move_placed(true))
	placed_buttons.add_child(_placed_move_up)
	_placed_move_down = ManagerUi.button("▼")
	_placed_move_down.tooltip_text = "往下一層(被原本在它上面的家具蓋住)。"
	_placed_move_down.pressed.connect(func() -> void: _move_placed(false))
	placed_buttons.add_child(_placed_move_down)
	_placed_remove = ManagerUi.button("從桌面移除")
	_placed_remove.pressed.connect(_on_placed_remove_pressed)
	placed_buttons.add_child(_placed_remove)
	column.add_child(placed_buttons)
	_refresh_placed_list()
	return column


func _build_form_column() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form_root = VBoxContainer.new()
	_form_root.add_theme_constant_override("separation", 6)
	_form_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form_root)
	_empty_label = Label.new()
	_empty_label.text = "選一件家具,或先新增一個。"
	_empty_label.theme_type_variation = AppSettings.MUTED_LABEL
	_form_root.add_child(_empty_label)
	_name_edit = ManagerUi.line_edit("家具名稱")
	_name_edit.text_submitted.connect(func(_t: String) -> void: _rename())
	_name_edit.focus_exited.connect(_rename)
	_form_root.add_child(ManagerUi.labeled("名稱", _name_edit))
	_condition_option = OptionButton.new()
	for kind: String in FurnitureCondition.TYPES:
		_condition_option.add_item(FurnitureCondition.label_of(kind))
		_condition_option.set_item_metadata(_condition_option.item_count - 1, kind)
	_condition_option.item_selected.connect(func(_i: int) -> void: _edit_condition())
	_form_root.add_child(ManagerUi.hint_row("觸發方式", "「一直啟用」= 只有 normal 這個狀態,平時就是它。「指定時間段」「有桌寵正在做某個動作」「有桌寵正在使用這件家具」「所有座位都被佔滿」= 平時播 normal,條件成立時切到 conditional(例如檯燈的燈亮起來、迪斯可燈開始轉、有人坐著時指示燈亮、滿座時亮起慶祝燈效)。這批的條件種類還不多,之後會照積木能用的條件慢慢補。"))
	_form_root.add_child(ManagerUi.labeled("觸發方式", _condition_option))
	_time_start_hour = ManagerUi.spin(1.0, 0.0, 23.0)
	_time_start_minute = ManagerUi.spin(1.0, 0.0, 59.0)
	_time_end_hour = ManagerUi.spin(1.0, 0.0, 23.0)
	_time_end_minute = ManagerUi.spin(1.0, 0.0, 59.0)
	for spin: SpinBox in [_time_start_hour, _time_start_minute, _time_end_hour, _time_end_minute]:
		spin.value_changed.connect(func(_v: float) -> void: _edit_condition())
		# 只要放得下兩位數字就好,不然視窗窄一點(表單欄位跟著視窗寬度縮)時,四個數字框擠在同一列會被裁掉。
		spin.custom_minimum_size.x = 58.0
		# ManagerUi.spin() 預設 allow_greater/allow_lesser = true:min/max 只管上下箭頭,直接打字或
		# 滑鼠拖曳還是能超出範圍(2026-09-30 使用者實機回報,分鐘欄位打得出 65 這種不存在的數字)。
		# 時間欄位本來就該是硬性範圍(0~23 時、0~59 分),這裡蓋回 false 讓打字也照樣夾在範圍內。
		spin.allow_greater = false
		spin.allow_lesser = false
	# 從/到分兩列(各自跟其他欄位一樣是「130px 標籤 + 內容」的排版),不要擠在同一列,不然視窗窄的時候會被裁掉。
	_time_row = VBoxContainer.new()
	for pair: Array in [["從", _time_start_hour, _time_start_minute], ["到", _time_end_hour, _time_end_minute]]:
		var pair_box := HBoxContainer.new()
		pair_box.add_child(pair[1])
		var colon := Label.new()
		colon.text = ":"
		pair_box.add_child(colon)
		pair_box.add_child(pair[2])
		_time_row.add_child(ManagerUi.labeled(str(pair[0]), pair_box))
	_form_root.add_child(_time_row)
	_action_edit = ManagerUi.line_edit("例如 dance")
	_action_edit.text_submitted.connect(func(_t: String) -> void: _edit_condition())
	_action_edit.focus_exited.connect(_edit_condition)
	_action_row = ManagerUi.labeled("動作代號", _action_edit)
	_form_root.add_child(_action_row)
	_scale_spin = ManagerUi.spin(0.05, FurnitureDef.SCALE_RANGE.x, FurnitureDef.SCALE_RANGE.y)
	_scale_spin.value_changed.connect(func(_v: float) -> void: _edit_scale())
	_form_root.add_child(ManagerUi.labeled("縮放倍率", _scale_spin))
	_form_root.add_child(ManagerUi.heading_with_info("家具標籤", tr("固定清單(不能自訂),給網頁端積木編輯器的事件判定篩選用,例如「家具標籤是椅子」;一件家具可以選好幾個,最多 %d 個,不知道選什麼可以先跳過。") % FurnitureDef.MAX_TAGS))
	_tags_list = ItemList.new()
	_tags_list.custom_minimum_size.y = 110.0
	_tags_list.select_mode = ItemList.SELECT_MULTI
	for tag: String in FurnitureDef.TAGS_CATALOG:
		_tags_list.add_item(tag)
	_tags_list.multi_selected.connect(func(_i: int, _s: bool) -> void: _edit_tags())
	_form_root.add_child(_tags_list)
	_form_root.add_child(ManagerUi.heading_with_info("容器內容物", tr("設定好道具跟補滿數量,這件家具就會變成容器:桌寵會自主走過去拿裡面的道具(前提是牠喜歡這個道具、容器還有庫存、桌面上同一種道具還沒到上限),使用者也可以雙擊容器打開查看內容物、按按鈕補滿。沒有設定任何內容物就是普通家具,不會有這個行為;桌寵觸發使用或使用者打開查看時,家具會播「使用中」那個動作槽(interacted,在「編輯素材…」裡準備)。最多 %d 種道具,同一種只能設定一筆(重複新增會改上限,不會變成兩筆)。") % FurnitureDef.MAX_CONTAINER_ITEMS))
	_container_list = ItemList.new()
	_container_list.custom_minimum_size.y = 84.0
	_container_list.item_selected.connect(func(_i: int) -> void: _sync_container_buttons())
	_form_root.add_child(_container_list)
	var container_row := HBoxContainer.new()
	_container_prop_option = OptionButton.new()
	container_row.add_child(_container_prop_option)
	_container_capacity_spin = ManagerUi.spin(1.0, FurnitureDef.CONTAINER_CAPACITY_RANGE.x, FurnitureDef.CONTAINER_CAPACITY_RANGE.y)
	container_row.add_child(ManagerUi.labeled("補滿數量", _container_capacity_spin))
	_container_add = ManagerUi.button("＋ 新增/更新")
	_container_add.pressed.connect(_on_container_add_pressed)
	container_row.add_child(_container_add)
	_form_root.add_child(container_row)
	_container_delete = ManagerUi.button("刪除這項")
	_container_delete.pressed.connect(_on_container_delete_pressed)
	_form_root.add_child(_container_delete)
	_build_aura_section(_form_root)
	_sprite_label = Label.new()
	_sprite_label.theme_type_variation = AppSettings.MUTED_LABEL
	_form_root.add_child(_sprite_label)
	var sprite_button := ManagerUi.button("編輯素材…")
	sprite_button.tooltip_text = "開精靈圖編輯器的家具區,準備 normal(平時)、conditional(條件成立時)、interacted(以後給桌寵用時)三個動作槽的圖;坐/躺位置(錨點)與光源也在那邊編輯,可以直接在畫布上對著貼圖拖曳,看得到實際位置。"
	sprite_button.pressed.connect(func() -> void:
		if _current != null:
			edit_sprite_requested.emit(_current.id))
	_form_root.add_child(sprite_button)
	_place_button = ManagerUi.button("放上桌面")
	_place_button.pressed.connect(_on_place_pressed)
	_form_root.add_child(_place_button)
	return scroll


func reload() -> void:
	var fresh := FurnitureLibrary.list()
	# 還沒存檔的家具不要被剛從磁碟讀回來的舊版本蓋掉(新增/刪除家具都會呼叫 reload(),但那是「別的家具」
	# 的操作,不該連帶弄丟使用者正在改、還沒按「儲存」的另一件家具)。
	if not _dirty_ids.is_empty():
		for i in fresh.size():
			if _dirty_ids.has(fresh[i].id):
				var kept := _def_by_id(fresh[i].id)
				if kept != null:
					fresh[i] = kept
	_defs = fresh
	_updating = true
	_list.clear()
	for def in _defs:
		_list.add_item(def.display_name)
	_updating = false
	if _current != null:
		var keep := _defs.filter(func(d: FurnitureDef) -> bool: return d.id == _current.id)
		if not keep.is_empty():
			_select(keep[0], false)
			return
	_select(_defs[0] if not _defs.is_empty() else null, false)


func _on_selected(index: int) -> void:
	if index >= 0 and index < _defs.size():
		_select(_defs[index], true)


func _select(def: FurnitureDef, focus_list: bool) -> void:
	_current = def
	_form_root.visible = def != null
	_empty_label.visible = def == null
	if def == null:
		return
	_updating = true
	_name_edit.text = def.display_name
	for i in _condition_option.item_count:
		if str(_condition_option.get_item_metadata(i)) == str(def.condition.get("type", "always")):
			_condition_option.select(i)
	_time_start_hour.value = int(def.condition.get("start", 0)) / 60
	_time_start_minute.value = int(def.condition.get("start", 0)) % 60
	_time_end_hour.value = int(def.condition.get("end", 0)) / 60
	_time_end_minute.value = int(def.condition.get("end", 0)) % 60
	_action_edit.text = str(def.condition.get("action", "dance"))
	_scale_spin.value = def.scale_multiplier
	_tags_list.deselect_all()
	for tag in def.tags:
		var index := FurnitureDef.TAGS_CATALOG.find(tag)
		if index >= 0:
			_tags_list.select(index, false)
	_updating = false
	_sync_condition_visibility()
	_refresh_container_list()
	_refresh_aura_list()
	_sprite_label.text = tr("有進階貼圖(normal%s%s)") % [
			"、conditional" if FurnitureLibrary.load_sprite(def) != null and (FurnitureLibrary.load_sprite(def) as SpriteFrames).has_animation(&"conditional_0") else "",
			"、interacted" if FurnitureLibrary.load_sprite(def) != null and (FurnitureLibrary.load_sprite(def) as SpriteFrames).has_animation(&"interacted_0") else ""] \
			if FurnitureLibrary.has_sprite(def) else "還沒有素材,按「編輯素材…」放圖進去。"
	if focus_list:
		for i in _defs.size():
			if _defs[i] == def:
				_list.select(i)


func _sync_condition_visibility() -> void:
	var kind := str(_current.condition.get("type", "always")) if _current != null else "always"
	_time_row.visible = kind == "time_range"
	_action_row.visible = kind == "pet_action"


func _rename() -> void:
	if _updating or _current == null:
		return
	var wanted := FurnitureDef.clean_name(_name_edit.text)
	if wanted == "" or wanted == _current.display_name:
		_name_edit.text = _current.display_name
		return
	_current.display_name = wanted
	_mark_dirty(_current.id)
	# 改列表顯示用的名字就好,不能呼叫 reload()——那會整份從磁碟重讀,把這次(還沒存檔的)改名蓋掉。
	for i in _defs.size():
		if _defs[i] == _current:
			_list.set_item_text(i, wanted)
			break


func _edit_condition() -> void:
	if _updating or _current == null:
		return
	var kind := str(_condition_option.get_item_metadata(_condition_option.selected))
	var raw := {"type": kind}
	if kind == "time_range":
		raw["start"] = int(_time_start_hour.value) * 60 + int(_time_start_minute.value)
		raw["end"] = int(_time_end_hour.value) * 60 + int(_time_end_minute.value)
	elif kind == "pet_action":
		raw["action"] = _action_edit.text
	_current.condition = FurnitureCondition.clean(raw)
	_sync_condition_visibility()
	_mark_dirty(_current.id)


func _edit_scale() -> void:
	if _updating or _current == null:
		return
	_current.scale_multiplier = clampf(_scale_spin.value, FurnitureDef.SCALE_RANGE.x, FurnitureDef.SCALE_RANGE.y)
	_mark_dirty(_current.id)


## 超過 MAX_TAGS 個就擋下最後一次選取(清單本身沒有內建的多選數量上限)。
func _edit_tags() -> void:
	if _updating or _current == null:
		return
	var picked: Array[String] = []
	for i in _tags_list.get_selected_items():
		picked.append(str(FurnitureDef.TAGS_CATALOG[i]))
	if picked.size() > FurnitureDef.MAX_TAGS:
		_status.text = tr("家具標籤最多選 %d 個。") % FurnitureDef.MAX_TAGS
		_updating = true
		_tags_list.deselect_all()
		for tag in _current.tags:
			var index := FurnitureDef.TAGS_CATALOG.find(tag)
			if index >= 0:
				_tags_list.select(index, false)
		_updating = false
		return
	_current.tags = FurnitureDef.clean_tags(picked)
	_mark_dirty(_current.id)


## 選單共用:value/stat 兩種 kind 的選項統一塞進一顆 OptionButton,metadata 編碼成 "stat:<key>" 或
## "value:local"/"value:global"(可選加一顆 "none" 當「不篩選」);AURA_STAT_LABELS 沒有的 key 用原始字串頂替。
func _add_key_options(option: OptionButton, include_none: bool) -> void:
	option.clear()
	if include_none:
		option.add_item(tr("不篩選"))
		option.set_item_metadata(0, "none")
	for key: String in FurnitureDef.AURA_STAT_KEYS:
		option.add_item(tr(str(AURA_STAT_LABELS.get(key, key))))
		option.set_item_metadata(option.item_count - 1, "stat:%s" % key)
	option.add_item(tr("使用者自訂數值(局部)"))
	option.set_item_metadata(option.item_count - 1, "value:local")
	option.add_item(tr("使用者自訂數值(全域)"))
	option.set_item_metadata(option.item_count - 1, "value:global")


func _build_aura_section(parent: Control) -> void:
	parent.add_child(ManagerUi.heading_with_info("效果", tr("這件家具「條件成立」的期間(見上面的觸發方式),對行動區裡所有桌寵套用的持續效果,例如小夜燈讓低精力的桌寵更容易入睡(目標選「疲勞閾值」調高、篩選選「精力」小於某個數)。套用的是「覆蓋成指定值」,家具關閉、被收走、桌寵離開篩選範圍,或這筆效果被刪掉時都會自動還原回桌寵原本的值,不會留著回不去。可以調整使用者自訂的局部/全域數值,也可以調整桌寵內建、性格會用到的參數(清單裡列出的那些)。最多 %d 筆。") % FurnitureDef.MAX_AURA_EFFECTS))
	_aura_list = ItemList.new()
	_aura_list.custom_minimum_size.y = 84.0
	_aura_list.item_selected.connect(_on_aura_selected)
	parent.add_child(_aura_list)
	parent.add_child(ManagerUi.labeled("效果目標", _build_aura_target_row()))
	_aura_target_number = ManagerUi.spin(1.0, FurnitureDef.AURA_VALUE_RANGE.x, FurnitureDef.AURA_VALUE_RANGE.y)
	parent.add_child(ManagerUi.labeled("套用時的數值", _aura_target_number))
	parent.add_child(ManagerUi.labeled("篩選條件(選填)", _build_aura_filter_row()))
	_aura_add = ManagerUi.button("＋ 新增/更新這筆效果")
	_aura_add.pressed.connect(_on_aura_add_pressed)
	parent.add_child(_aura_add)
	_aura_delete = ManagerUi.button("刪除這筆效果")
	_aura_delete.pressed.connect(_on_aura_delete_pressed)
	parent.add_child(_aura_delete)


func _build_aura_target_row() -> Control:
	var row := HBoxContainer.new()
	_aura_target_option = OptionButton.new()
	_add_key_options(_aura_target_option, false)
	_aura_target_option.item_selected.connect(func(_i: int) -> void: _sync_aura_field_visibility())
	row.add_child(_aura_target_option)
	_aura_target_value_key = ManagerUi.line_edit("自訂數值的 key")
	row.add_child(_aura_target_value_key)
	return row


func _build_aura_filter_row() -> Control:
	var row := HBoxContainer.new()
	_aura_filter_option = OptionButton.new()
	_add_key_options(_aura_filter_option, true)
	_aura_filter_option.item_selected.connect(func(_i: int) -> void: _sync_aura_field_visibility())
	row.add_child(_aura_filter_option)
	_aura_filter_value_key = ManagerUi.line_edit("自訂數值的 key")
	row.add_child(_aura_filter_value_key)
	_aura_filter_op_option = OptionButton.new()
	for op: String in FurnitureDef.AURA_FILTER_OPS:
		_aura_filter_op_option.add_item(op)
	row.add_child(_aura_filter_op_option)
	_aura_filter_number = ManagerUi.spin(1.0, FurnitureDef.AURA_VALUE_RANGE.x, FurnitureDef.AURA_VALUE_RANGE.y)
	row.add_child(_aura_filter_number)
	return row


## 自訂數值的 key 輸入框只有在選到「使用者自訂數值」那兩個選項時才顯示,stat 模式用不到(直接從下拉選單讀 key)。
func _sync_aura_field_visibility() -> void:
	if is_instance_valid(_aura_target_value_key) and _aura_target_option.selected >= 0:
		_aura_target_value_key.visible = str(_aura_target_option.get_item_metadata(_aura_target_option.selected)).begins_with("value:")
	if is_instance_valid(_aura_filter_value_key) and _aura_filter_option.selected >= 0:
		var filter_meta := str(_aura_filter_option.get_item_metadata(_aura_filter_option.selected))
		_aura_filter_value_key.visible = filter_meta.begins_with("value:")
		var has_filter := filter_meta != "none"
		_aura_filter_op_option.visible = has_filter
		_aura_filter_number.visible = has_filter


## metadata("stat:<key>"/"value:local"/"value:global")拆成 {kind, stat_key, scope}。
func _split_key_metadata(meta: String) -> Dictionary:
	var parts := meta.split(":", true, 1)
	if parts[0] == "value":
		return {"kind": "value", "scope": parts[1] if parts.size() > 1 else "local", "stat_key": ""}
	return {"kind": "stat", "scope": "local", "stat_key": parts[1] if parts.size() > 1 else ""}


func _aura_effect_summary(effect: Dictionary) -> String:
	var target_kind := str(effect.get("target_kind", "value"))
	var target_label: String = AURA_STAT_LABELS.get(str(effect.get("target_key", "")), str(effect.get("target_key", ""))) if target_kind == "stat" else tr("自訂數值「%s」(%s)") % [effect.get("target_key", ""), tr("局部") if str(effect.get("scope", "local")) == "local" else tr("全域")]
	var text := tr("%s → %s") % [target_label, str(effect.get("value", 0.0))]
	var filter_kind := str(effect.get("filter_kind", ""))
	if filter_kind != "":
		var filter_label: String = AURA_STAT_LABELS.get(str(effect.get("filter_key", "")), str(effect.get("filter_key", ""))) if filter_kind == "stat" else tr("自訂數值「%s」") % effect.get("filter_key", "")
		text += tr("(當 %s %s %s 時)") % [filter_label, effect.get("filter_op", "<"), effect.get("filter_value", 0.0)]
	return text


func _refresh_aura_list() -> void:
	if not is_instance_valid(_aura_list):
		return
	_aura_list.clear()
	if _current != null:
		for effect: Dictionary in _current.aura_effects:
			_aura_list.add_item(_aura_effect_summary(effect))
	_sync_aura_buttons()
	_sync_aura_field_visibility()


## 選取既有一筆效果時,把目標/篩選欄位填回去,方便改完按「新增/更新」直接覆蓋這一筆(不用重新全部填一次)。
func _on_aura_selected(index: int) -> void:
	if _current == null or index < 0 or index >= _current.aura_effects.size():
		_sync_aura_buttons()
		return
	var effect: Dictionary = _current.aura_effects[index]
	var target_kind := str(effect.get("target_kind", "value"))
	var target_meta := "value:%s" % str(effect.get("scope", "local")) if target_kind == "value" else "stat:%s" % str(effect.get("target_key", ""))
	for i in _aura_target_option.item_count:
		if str(_aura_target_option.get_item_metadata(i)) == target_meta:
			_aura_target_option.select(i)
			break
	_aura_target_value_key.text = str(effect.get("target_key", "")) if target_kind == "value" else ""
	_aura_target_number.value = float(effect.get("value", 0.0))
	var filter_kind := str(effect.get("filter_kind", ""))
	var filter_meta := "none" if filter_kind == "" else ("value:%s" % str(effect.get("filter_scope", "local")) if filter_kind == "value" else "stat:%s" % str(effect.get("filter_key", "")))
	for i in _aura_filter_option.item_count:
		if str(_aura_filter_option.get_item_metadata(i)) == filter_meta:
			_aura_filter_option.select(i)
			break
	_aura_filter_value_key.text = str(effect.get("filter_key", "")) if filter_kind == "value" else ""
	for i in _aura_filter_op_option.item_count:
		if _aura_filter_op_option.get_item_text(i) == str(effect.get("filter_op", "<")):
			_aura_filter_op_option.select(i)
			break
	_aura_filter_number.value = float(effect.get("filter_value", 0.0))
	_sync_aura_field_visibility()
	_sync_aura_buttons()


func _sync_aura_buttons() -> void:
	_aura_delete.disabled = _aura_list.get_selected_items().is_empty()
	_aura_add.disabled = _current != null and _current.aura_effects.size() >= FurnitureDef.MAX_AURA_EFFECTS and _aura_list.get_selected_items().is_empty()


## 新增一筆效果(最多 MAX_AURA_EFFECTS 筆,滿了且沒有選取既有項目時 _aura_add 會被停用擋下);
## 按「儲存」後才會同步桌面上已經放置的同一件家具實例(FurnitureItem.apply_def() 會先還原舊效果)。
func _on_aura_add_pressed() -> void:
	if _current == null or _aura_target_option.selected < 0:
		return
	var target_meta := _split_key_metadata(str(_aura_target_option.get_item_metadata(_aura_target_option.selected)))
	var target_key := str(_aura_target_value_key.text).strip_edges() if target_meta["kind"] == "value" else str(target_meta["stat_key"])
	var raw := {
		"target_kind": target_meta["kind"], "target_key": target_key, "scope": target_meta["scope"],
		"value": _aura_target_number.value,
	}
	if _aura_filter_option.selected >= 0:
		var filter_meta_raw := str(_aura_filter_option.get_item_metadata(_aura_filter_option.selected))
		if filter_meta_raw != "none":
			var filter_meta := _split_key_metadata(filter_meta_raw)
			raw["filter_kind"] = filter_meta["kind"]
			raw["filter_key"] = str(_aura_filter_value_key.text).strip_edges() if filter_meta["kind"] == "value" else str(filter_meta["stat_key"])
			raw["filter_scope"] = filter_meta["scope"]
			raw["filter_op"] = str(_aura_filter_op_option.get_item_text(_aura_filter_op_option.selected))
			raw["filter_value"] = _aura_filter_number.value
	var items := _current.aura_effects.duplicate(true)
	var selected := _aura_list.get_selected_items()
	if not selected.is_empty() and selected[0] < items.size():
		items[selected[0]] = raw
	elif items.size() < FurnitureDef.MAX_AURA_EFFECTS:
		items.append(raw)
	else:
		_status.text = tr("效果最多只能設 %d 筆。") % FurnitureDef.MAX_AURA_EFFECTS
		return
	_current.aura_effects = FurnitureDef.clean_aura_effects(items)
	_mark_dirty(_current.id)
	_refresh_aura_list()


func _on_aura_delete_pressed() -> void:
	var selected := _aura_list.get_selected_items()
	if selected.is_empty() or _current == null:
		return
	var items := _current.aura_effects.duplicate(true)
	items.remove_at(selected[0])
	_current.aura_effects = FurnitureDef.clean_aura_effects(items)
	_mark_dirty(_current.id)
	_refresh_aura_list()


func _reload_container_props() -> void:
	_container_props = PropLibrary.list()
	_container_prop_option.clear()
	for def in _container_props:
		_container_prop_option.add_item(def.display_name)


func _refresh_container_list() -> void:
	if not is_instance_valid(_container_list):
		return
	_container_list.clear()
	if _current != null:
		for entry: Dictionary in _current.container_items:
			var def := PropLibrary.load_def(str(entry["id"]))
			var label := def.display_name if def != null else tr("(找不到:%s)") % str(entry["id"])
			_container_list.add_item("%s × %d" % [label, int(entry["capacity"])])
	_sync_container_buttons()


func _sync_container_buttons() -> void:
	_container_delete.disabled = _container_list.get_selected_items().is_empty()


## 新增一種容器道具,或(同一種已經設定過)改它的補滿數量;按「儲存」後才會同步桌面上已經放置的同一件
## 家具實例(見 FurnitureManager.refresh_def → FurnitureItem._sync_container_items,不會弄丟目前剩餘的庫存)。
func _on_container_add_pressed() -> void:
	if _current == null or _container_prop_option.selected < 0 or _container_prop_option.selected >= _container_props.size():
		return
	var def := _container_props[_container_prop_option.selected]
	var items := _current.container_items.duplicate(true)
	var found := false
	for entry: Dictionary in items:
		if str(entry["id"]) == def.id:
			entry["capacity"] = int(_container_capacity_spin.value)
			found = true
			break
	if not found:
		items.append({"id": def.id, "capacity": int(_container_capacity_spin.value)})
	_current.container_items = FurnitureDef.clean_container_items(items)
	_mark_dirty(_current.id)
	_refresh_container_list()


func _on_container_delete_pressed() -> void:
	var selected := _container_list.get_selected_items()
	if selected.is_empty() or _current == null:
		return
	var items := _current.container_items.duplicate(true)
	items.remove_at(selected[0])
	_current.container_items = FurnitureDef.clean_container_items(items)
	_mark_dirty(_current.id)
	_refresh_container_list()


func _on_add_pressed() -> void:
	if _template_option.item_count == 0:
		return
	var template_id := str(_template_option.get_item_metadata(_template_option.selected))
	var def := FurnitureLibrary.create_from_template(template_id)
	if def == null:
		_status.text = "新增失敗。"
		return
	reload()
	# 2026-10-04 修掉一個潛藏的存檔漏洞:reload() 會把 _defs 整份換成剛剛從磁碟重讀出來的「另一份」物件
	# (跟上面 create_from_template() 回傳的 def 不是同一個參考),如果這裡直接拿 def 當 _current,之後
	# _save_all() 透過 _def_by_id() 找到的卻是 _defs 裡那份沒被编輯過的舊物件──新增後馬上編輯(容器內容物、
	# 效果…)按儲存會悄悄存回編輯前的樣子。改成選 reload() 之後、_defs 裡 id 相同的那一份,讓 _current 跟
	# _defs 共用同一個物件參考,編輯才真的會被存到。
	_select(_def_by_id(def.id), true)
	_status.text = tr("已新增「%s」,記得按「編輯素材…」放圖進去。") % def.display_name


func _on_delete_pressed() -> void:
	if _current == null:
		return
	var name := _current.display_name
	var error := FurnitureLibrary.delete_def(_current.id)
	if error != "":
		_status.text = tr("刪除失敗:%s") % error
		return
	# 刪掉的這件如果還有沒存的修改,那份記憶體副本一起丟掉,免得 _dirty 卡在 true(明明已經沒東西可存了)。
	_dirty_ids.erase(_current.id)
	_dirty = not _dirty_ids.is_empty()
	_current = null
	reload()
	_status.text = tr("已把「%s」搬到備份。") % name


func _on_place_pressed() -> void:
	if _current == null or _manager == null:
		return
	# 這裡改的欄位(觸發方式、標籤、容器內容物…)要按「儲存」才會真的寫進磁碟;放上桌面前先存檔,
	# 不然接下來的「重讀一次」會直接把這些還沒存檔的修改蓋掉。
	if _dirty_ids.has(_current.id):
		_save_all()
	# 精靈圖編輯器的家具區改的是它自己讀進來的另一份 FurnitureDef(不是這個視窗的 _current),
	# 存檔只會寫進 furniture.json,不會回頭更新這裡快取的物件;放上桌面前重讀一次才不會用到舊資料
	# (光源、錨點、above_light 這些在那邊編的欄位都算,2026-09-22 修正)。
	var fresh := FurnitureLibrary.load_def(_current.id)
	if fresh != null:
		_current = fresh
	var item := _manager.spawn(_current)
	_status.text = tr("已放上桌面。") if item != null else "這件家具還沒有素材(normal 狀態),先按「編輯素材…」放圖進去。"


func _on_edit_mode_toggled(on: bool) -> void:
	if _manager != null:
		_manager.set_edit_mode(on)
	_status.text = "家具編輯模式開啟:桌面左上角多了「家具欄」,拖裡面的家具到桌面上放置;已經放好的可以直接拖動、右鍵收回。" if on \
			else "家具編輯模式已關閉,家具恢復純裝飾(滑鼠完全穿透)。"


## 桌面上的家具變動(放置/移除/調順序,包含使用者直接在桌面上操作)時同步這個清單,保留原本選取的那一列。
func _refresh_placed_list() -> void:
	if _manager == null or not is_instance_valid(_placed_list):
		return
	var selected := _placed_list.get_selected_items()
	var keep_index := selected[0] if not selected.is_empty() else -1
	_placed_list.clear()
	for item in _manager.items:
		if is_instance_valid(item) and item.def != null:
			_placed_list.add_item(item.def.display_name)
	if keep_index >= 0 and keep_index < _placed_list.item_count:
		_placed_list.select(keep_index)
	_sync_placed_buttons()


func _sync_placed_buttons() -> void:
	var selected := _placed_list.get_selected_items()
	var has_selection := not selected.is_empty()
	_placed_move_up.disabled = not has_selection or selected[0] >= _placed_list.item_count - 1
	_placed_move_down.disabled = not has_selection or selected[0] <= 0
	_placed_remove.disabled = not has_selection


func _move_placed(up: bool) -> void:
	var selected := _placed_list.get_selected_items()
	if selected.is_empty() or _manager == null:
		return
	var index := selected[0]
	if index < 0 or index >= _manager.items.size():
		return
	var item := _manager.items[index]
	_manager.move_layer(item, up)
	_refresh_placed_list()
	var new_index := _manager.items.find(item)
	if new_index >= 0:
		_placed_list.select(new_index)
	_sync_placed_buttons()


func _on_placed_remove_pressed() -> void:
	var selected := _placed_list.get_selected_items()
	if selected.is_empty() or _manager == null:
		return
	var index := selected[0]
	if index < 0 or index >= _manager.items.size():
		return
	_manager.remove(_manager.items[index])


## 有未儲存的變更就跳出確認視窗(儲存後離開/不儲存離開/取消),跟桌寵管理視窗一致;
## 沒有變更就直接關(順便關掉編輯模式,不留著一直能拖桌面上的家具卻沒地方能把模式關掉)。
func _request_close() -> void:
	if _dirty:
		FloatingWindow.popup_child_dialog(self, get_window(), _confirm)
		return
	_close_now()
