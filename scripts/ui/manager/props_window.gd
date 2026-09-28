class_name PropsWindow
extends FloatingWindow
## 道具管理視窗(系統匣「道具管理…」):物品欄 + 小道具管理面板。左邊是道具清單(從內建模板新增、刪除),右邊編輯選中的道具
## (名稱、縮圖與桌面貼圖、互動模式、預設交互反應、逾時、拖曳吸引、可持有、數值綁定、狀態切換綁定),底下「丟到桌面」。
## 所有修改立刻存檔(user://props/<道具>/prop.json),沒有「儲存」鈕;刪除是搬到備份資料夾(見 PropLibrary)。

var _manager: PropManager
var _list: ItemList
var _defs: Array[PropDef] = []
var _current: PropDef
var _form_root: Control
var _empty_label: Label
var _status: Label
var _template_option: OptionButton
var _updating := false

var _name_edit: LineEdit
var _thumb_label: Label
var _desktop_label: Label
var _toss_check: CheckBox
var _rub_check: CheckBox
var _reaction_option: OptionButton
var _timeout_spin: SpinBox
var _attract_check: CheckBox
var _hold_check: CheckBox
var _consume_check: CheckBox
var _light_check: CheckBox
var _light_preview: PropLightPreview
var _light_x: SpinBox
var _light_y: SpinBox
var _light_radius: SpinBox
var _light_energy: SpinBox
var _light_color: LineEdit
var _light_swatch: ColorRect
var _negative_check: CheckBox
var _positive_check: CheckBox
var _energy_spin: SpinBox
var _value_rows: VBoxContainer
var _lens_rows: VBoxContainer
var _toss_button: Button
var _use_anim_option: OptionButton
var _shakes_spin: SpinBox
var _effect_option: OptionButton
var _effect_after_option: OptionButton
var _shape_option: OptionButton
var _hold_place_option: OptionButton
var _sprite_label: Label
## 使用者要在精靈圖編輯器的道具區編輯這個道具的進階貼圖(參數 = 道具資料夾名稱)。
signal edit_sprite_requested(prop_id: String)


func setup(manager: PropManager) -> void:
	_manager = manager
	setup_floating("道具管理", Vector2i(900, 700), Vector2i(700, 460))
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
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
	_status.text = "改了就立刻存起來。圖片由你自己匯入;沒有圖片的道具在桌面上會用程式畫的替代圖示。"
	page.add_child(_status)
	reload()


func _build_list_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 230.0
	column.add_child(ManagerUi.heading_with_info("物品欄", "所有小道具。從下面的模板新增一個,再在右邊改名字、匯入圖片、設定互動方式。"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	column.add_child(_list)
	var order_row := HBoxContainer.new()
	var up := ManagerUi.button("▲ 往前")
	up.tooltip_text = "調整這個道具在物品欄與道具欄裡的順序。"
	up.pressed.connect(func() -> void: move_current(-1))
	var down := ManagerUi.button("▼ 往後")
	down.tooltip_text = "調整這個道具在物品欄與道具欄裡的順序。"
	down.pressed.connect(func() -> void: move_current(1))
	order_row.add_child(up)
	order_row.add_child(down)
	column.add_child(order_row)
	_template_option = OptionButton.new()
	for template_id: String in PropLibrary.TEMPLATES:
		_template_option.add_item(str((PropLibrary.TEMPLATES[template_id] as Dictionary)["label"]))
		_template_option.set_item_metadata(_template_option.item_count - 1, template_id)
	column.add_child(ManagerUi.labeled("模板", _template_option))
	var add := ManagerUi.button("＋ 從模板新增")
	add.pressed.connect(func() -> void: add_from_template(str(_template_option.get_item_metadata(_template_option.selected))))
	column.add_child(add)
	var remove := ManagerUi.button("刪除這個道具")
	remove.pressed.connect(_on_delete_pressed)
	column.add_child(remove)
	var open_backup := ManagerUi.button("🗄 備份資料夾")
	open_backup.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(PropLibrary.backup_root())
		OS.shell_open(ProjectSettings.globalize_path(PropLibrary.backup_root())))
	column.add_child(open_backup)
	return column


func _build_form_column() -> Control:
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label = Label.new()
	_empty_label.text = "左邊還沒有道具:選一個模板按「從模板新增」。"
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(_empty_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	holder.add_child(scroll)
	_form_root = scroll
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)

	_name_edit = ManagerUi.line_edit("道具名稱")
	_name_edit.max_length = PropDef.MAX_NAME
	_name_edit.text_submitted.connect(func(_t: String) -> void: _apply_name())
	_name_edit.focus_exited.connect(_apply_name)
	form.add_child(ManagerUi.labeled("名稱", _name_edit))
	_thumb_label = Label.new()
	form.add_child(ManagerUi.heading_with_info("道具貼圖", "簡單版:只貼一張圖片就好(存在這個道具自己的資料夾裡),物品欄與桌面上都用它。進階版:在精靈圖編輯器的道具區替不同狀態(預設、被使用、拖曳中)各做一組動畫,有進階貼圖時桌面上的道具用它,物品欄縮圖沒有簡單版的圖就用預設狀態的第一幀。"))
	form.add_child(_image_row("道具圖片(簡單版)", _thumb_label, "thumbnail"))
	_desktop_label = Label.new()
	form.add_child(_image_row("桌面貼圖(可不填,沒填就用上面那張)", _desktop_label, "desktop"))
	var sprite_row := HBoxContainer.new()
	_sprite_label = Label.new()
	_sprite_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sprite_label.clip_text = true
	sprite_row.add_child(_sprite_label)
	var edit_sprite := ManagerUi.button("進階貼圖…")
	edit_sprite.tooltip_text = "開啟精靈圖編輯器的道具區:替預設、被使用、拖曳中做動畫。"
	edit_sprite.pressed.connect(func() -> void:
		if _current != null:
			edit_sprite_requested.emit(_current.id))
	sprite_row.add_child(edit_sprite)
	form.add_child(ManagerUi.labeled("進階貼圖", sprite_row))

	form.add_child(ManagerUi.heading_with_info("互動模式", "拾取:丟到桌面後,桌寵碰到就會拿走(只有一隻會拿到)。摩擦:直接拖到桌寵身上來回摩擦(例如毛巾擦一擦)。兩個可以同時勾選;都不勾就只是收藏,不參與互動。"))
	_toss_check = _check("拾取", func(on: bool) -> void: _edit(func() -> void: _current.toss = on))
	form.add_child(_toss_check)
	_rub_check = _check("摩擦", func(on: bool) -> void: _edit(func() -> void: _current.rub = on))
	form.add_child(_rub_check)
	_consume_check = _check("摩擦後一次性消耗(不勾 = 回到物品欄可重複使用)", func(on: bool) -> void: _edit(func() -> void: _current.consume_on_rub = on))
	form.add_child(_consume_check)
	_reaction_option = OptionButton.new()
	_reaction_option.add_item("拾取(播放 gather 動作後移除)")
	_reaction_option.add_item("無(單純消失)")
	_reaction_option.item_selected.connect(func(index: int) -> void: _edit(func() -> void: _current.default_reaction = "pickup" if index == 0 else "none"))
	form.add_child(ManagerUi.labeled("預設交互反應", _reaction_option))
	form.add_child(ManagerUi.hint_row("預設反應只是保底", "桌寵沒有寫「當拾取這個道具」的事件積木、這個道具也沒有設定下面的數值或狀態綁定時,才用這裡的預設反應。"))
	_timeout_spin = ManagerUi.spin(1.0, 0.0, PropDef.MAX_TIMEOUT)
	_timeout_spin.suffix = " 秒(預設 180;0 = 永不消失)"
	_timeout_spin.value_changed.connect(func(value: float) -> void: _edit(func() -> void: _current.timeout_seconds = clampf(value, 0.0, PropDef.MAX_TIMEOUT)))
	form.add_child(ManagerUi.labeled("落地後消失", _timeout_spin))
	_use_anim_option = OptionButton.new()
	for label in ["立刻消失", "左右搖晃", "上下搖晃", "向上淡出", "淡出"]:
		_use_anim_option.add_item(label)
	_use_anim_option.item_selected.connect(func(index: int) -> void: _edit(func() -> void: _current.use_anim = PropDef.USE_ANIMS[index]))
	form.add_child(ManagerUi.labeled("被使用時的表現", _use_anim_option))
	_shakes_spin = ManagerUi.spin(1.0, PropDef.MIN_SHAKES, PropDef.MAX_SHAKES)
	_shakes_spin.suffix = " 次(搖晃式才用)"
	_shakes_spin.value_changed.connect(func(value: float) -> void: _edit(func() -> void: _current.use_shakes = clampi(int(value), PropDef.MIN_SHAKES, PropDef.MAX_SHAKES)))
	form.add_child(ManagerUi.labeled("搖晃次數", _shakes_spin))
	_effect_option = OptionButton.new()
	_effect_option.add_item("無")
	for effect_label in PetEffects.CATALOG:
		_effect_option.add_item(effect_label)
	_effect_option.item_selected.connect(func(index: int) -> void: _edit(func() -> void: _current.effect = "" if index == 0 else PetEffects.resolve(PetEffects.CATALOG[index - 1])))
	form.add_child(ManagerUi.labeled("連帶觸發特效", _effect_option))
	_effect_after_option = OptionButton.new()
	_effect_after_option.add_item("無")
	for effect_label in PetEffects.CATALOG:
		_effect_after_option.add_item(effect_label)
	_effect_after_option.item_selected.connect(func(index: int) -> void: _edit(func() -> void: _current.effect_after = "" if index == 0 else PetEffects.resolve(PetEffects.CATALOG[index - 1])))
	form.add_child(ManagerUi.labeled("使用結束後的特效", _effect_after_option))
	form.add_child(ManagerUi.hint_row("使用結束後", "拾取:使用動畫播完之後才播;摩擦:桌寵不再被這個道具擦(道具移開、放開或用完)之後才播。例如洗滌用品擦完接著閃閃發光。"))
	_attract_check = _check("拖曳中吸引:拖著這個道具移動時,場上會被吸引的桌寵會追過來", func(on: bool) -> void: _edit(func() -> void: _current.attract_while_dragging = on))
	form.add_child(_attract_check)
	_hold_check = _check("可持有:被拾取後不消失,記成這隻桌寵正拿著的道具", func(on: bool) -> void: _edit(func() -> void: _current.holdable = on))
	form.add_child(_hold_check)
	_hold_place_option = OptionButton.new()
	_hold_place_option.add_item("拿在手上(素材包的持有錨點)")
	_hold_place_option.add_item("頂在頭上(判定框頭頂位置)")
	_hold_place_option.item_selected.connect(func(index: int) -> void: _edit(func() -> void: _current.hold_place = PropDef.HOLD_PLACES[index]))
	form.add_child(ManagerUi.labeled("持有時放在", _hold_place_option))
	_shape_option = OptionButton.new()
	_shape_option.add_item("方形(一般道具)")
	_shape_option.add_item("圓球(會彈跳滾動旋轉,桌寵會追著玩、拋、頂在頭上)")
	_shape_option.item_selected.connect(func(index: int) -> void: _edit(func() -> void: _current.shape = PropDef.SHAPES[index]))
	form.add_child(ManagerUi.labeled("碰撞形狀", _shape_option))
	form.add_child(ManagerUi.hint_row("圓球", "圓球不會被桌寵自動撿走;有興趣的桌寵(性格「玩球意願」)會追球、把球往上往旁邊拋、或頂在頭上再拋高。桌寵玩球時球不計自動消失;在球上按右鍵可以手動收回。使用者也參與(抓球、丟球)時桌寵會得到好感度回饋;心情不好或不愛玩的性格不會加入。"))

	form.add_child(ManagerUi.heading_with_info("是光源", "讓這個道具自己發光:在下面的預覽圖上按一下(或拖曳)標出光源的位置,再調光暈半徑、強度、顏色,預覽會馬上反映。光是程式畫的柔和光暈(沒有陰影),桌面上道具在哪、光就在哪;全局設定的「啟用光源」關掉時不會發光。想當家具用:互動模式都不勾、「落地後消失」設成 0。"))
	_light_check = _check("這個道具會發光", func(on: bool) -> void: _edit_light("enabled", on))
	form.add_child(_light_check)
	_light_preview = PropLightPreview.new()
	_light_preview.anchor_picked.connect(func(x: float, y: float) -> void:
		_edit_light("x", x)
		_edit_light("y", y)
		_updating = true
		_light_x.value = roundf(x * 100.0)
		_light_y.value = roundf(-y * 100.0)
		_updating = false)
	form.add_child(_light_preview)
	_light_x = ManagerUi.spin(1.0, -50.0, 50.0)
	_light_x.suffix = " %(左右,0 = 正中間)"
	_light_x.value_changed.connect(func(value: float) -> void: _edit_light("x", value / 100.0))
	form.add_child(ManagerUi.labeled("光源左右", _light_x))
	_light_y = ManagerUi.spin(1.0, 0.0, 100.0)
	_light_y.suffix = " %(離腳底的高度,100 = 頂端)"
	_light_y.value_changed.connect(func(value: float) -> void: _edit_light("y", -value / 100.0))
	form.add_child(ManagerUi.labeled("光源高度", _light_y))
	_light_radius = ManagerUi.spin(1.0, 20.0, 300.0)
	_light_radius.suffix = " 像素"
	_light_radius.value_changed.connect(func(value: float) -> void: _edit_light("radius", value))
	form.add_child(ManagerUi.labeled("光暈半徑", _light_radius))
	_light_energy = ManagerUi.spin(0.05, 0.1, 2.0)
	_light_energy.value_changed.connect(func(value: float) -> void: _edit_light("energy", value))
	form.add_child(ManagerUi.labeled("光暈強度", _light_energy))
	# 顏色用文字框輸入 #RRGGBB(旁邊一小塊色樣):ColorPickerButton 會在這個原生浮動視窗裡多開一個彈出視窗,無頭測試裡偶爾讓引擎當掉。
	var color_row := HBoxContainer.new()
	_light_color = LineEdit.new()
	_light_color.placeholder_text = "#ffe4a0"
	_light_color.max_length = 9
	_light_color.custom_minimum_size.x = 110.0
	_light_color.text_submitted.connect(func(_t: String) -> void: _apply_light_color())
	_light_color.focus_exited.connect(_apply_light_color)
	color_row.add_child(_light_color)
	_light_swatch = ColorRect.new()
	_light_swatch.custom_minimum_size = Vector2(28.0, 22.0)
	color_row.add_child(_light_swatch)
	form.add_child(ManagerUi.labeled("光暈顏色(#RRGGBB)", color_row))

	form.add_child(ManagerUi.heading_with_info("觸發時改變數值(免寫積木)", "道具被拾取或摩擦時,直接增減某個數值,例如小魚乾:局部 飽食度 +10。數值名稱要和桌寵的數值定義一樣。"))
	_value_rows = VBoxContainer.new()
	form.add_child(_value_rows)
	var add_value := ManagerUi.button("＋ 新增數值綁定")
	add_value.pressed.connect(func() -> void:
		_edit(func() -> void:
			if _current.value_bindings.size() < PropDef.MAX_BINDINGS:
				_current.value_bindings.append({"scope": "local", "key": "數值名稱", "delta": 1.0}))
		_rebuild_bindings())
	form.add_child(add_value)

	form.add_child(ManagerUi.heading_with_info("觸發時切換狀態鏡(免寫積木)", "道具被拾取或摩擦時,啟用或解除某個狀態鏡,例如聖誕帽:啟用「聖誕節模式」。狀態鏡名稱要和桌寵的狀態鏡一樣——用建立當下打的原文(通常是中文,使用者自建的狀態鏡沒有翻譯、不能打別的語言);內建的「開心/悠哉/緊張/生氣/悲傷/疲憊」六個例外,打英文(happy/relaxed/nervous/angry/sad/tired)也認得到。"))
	_lens_rows = VBoxContainer.new()
	form.add_child(_lens_rows)
	var add_lens := ManagerUi.button("＋ 新增狀態鏡綁定")
	add_lens.pressed.connect(func() -> void:
		_edit(func() -> void:
			if _current.lens_bindings.size() < PropDef.MAX_BINDINGS:
				_current.lens_bindings.append({"op": "enable", "lens": "狀態鏡名稱"}))
		_rebuild_bindings())
	form.add_child(add_lens)
	_negative_check = _check("觸發時解除所有目前生效的「負面」狀態鏡", func(on: bool) -> void: _edit(func() -> void: _current.disable_negative = on))
	form.add_child(_negative_check)
	_positive_check = _check("觸發時解除所有目前生效的「正面」狀態鏡", func(on: bool) -> void: _edit(func() -> void: _current.disable_positive = on))
	form.add_child(_positive_check)
	_energy_spin = ManagerUi.spin(1.0, 0.0, 100.0)
	_energy_spin.value_changed.connect(func(value: float) -> void: _edit(func() -> void: _current.restore_energy = value))
	form.add_child(ManagerUi.labeled("恢復精力(疲勞值)", _energy_spin))

	var bottom_row := HBoxContainer.new()
	_toss_button = ManagerUi.button("🎁 丟到桌面")
	_toss_button.pressed.connect(toss_current)
	bottom_row.add_child(_toss_button)
	var clear_button := ManagerUi.button("🧹 清空桌面上的道具")
	clear_button.pressed.connect(func() -> void: _say(tr("清掉了 %d 個桌面上的道具。") % clear_props()))
	bottom_row.add_child(clear_button)
	holder.add_child(bottom_row)
	return holder


func _check(text: String, on_toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check.toggled.connect(func(on: bool) -> void:
		if not _updating:
			on_toggled.call(on))
	return check


func _image_row(title_text: String, label: Label, slot: String) -> Control:
	var row := HBoxContainer.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	var choose := ManagerUi.button("選擇圖片…")
	choose.pressed.connect(func() -> void: _choose_image(slot))
	row.add_child(choose)
	var clear := ManagerUi.button("清除")
	clear.pressed.connect(func() -> void: clear_image(slot))
	row.add_child(clear)
	return ManagerUi.labeled(title_text, row)


# --- 清單 ---

## 重新讀物品欄;select_id 非空就選那一個(否則保留目前選的)。
func reload(select_id := "") -> void:
	var keep := select_id if select_id != "" else (_current.id if _current != null else "")
	_defs = PropLibrary.list()
	_list.clear()
	var select_index := -1
	for i in _defs.size():
		var def := _defs[i]
		_list.add_item(def.display_name, PropLibrary.texture_of(def, "thumbnail"))
		if def.id == keep:
			select_index = i
	if select_index < 0 and not _defs.is_empty():
		select_index = 0
	if select_index >= 0:
		_list.select(select_index)
		_show_prop(_defs[select_index])
	else:
		_show_prop(null)


func _on_selected(index: int) -> void:
	if index >= 0 and index < _defs.size():
		_show_prop(_defs[index])


## 目前選的道具在順序裡往前/往後移一格(道具欄與物品欄照這個順序)。
func move_current(delta: int) -> void:
	if _current != null and PropLibrary.move_in_order(_current.id, delta):
		reload(_current.id)


func add_from_template(template_id: String) -> PropDef:
	var def := PropLibrary.create_from_template(template_id)
	if def == null:
		_say("無法新增道具(資料夾寫不進去或已達上限)。")
		return null
	reload(def.id)
	_say(tr("已新增「%s」。") % def.display_name)
	return def


func _on_delete_pressed() -> void:
	if _current == null:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "刪除道具"
	dialog.dialog_text = tr("要刪除「%s」嗎?\n它的資料夾會搬到備份資料夾,不會直接消失。") % _current.display_name
	dialog.ok_button_text = "刪除"
	dialog.cancel_button_text = "取消"
	dialog.always_on_top = true
	dialog.theme = ManagerUi.make_theme()
	dialog.confirmed.connect(func() -> void:
		delete_current()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if DisplayServer.get_name() != "headless":
		dialog.popup_centered()


func delete_current() -> void:
	if _current == null:
		return
	var deleted_name := _current.display_name
	var error := PropLibrary.delete_def(_current.id)
	if error != "":
		_say(error)
		return
	_current = null
	reload()
	_say(tr("已把「%s」搬到備份資料夾。") % deleted_name)


# --- 表單 ---

func _show_prop(def: PropDef) -> void:
	_current = def
	_updating = true
	_empty_label.visible = def == null
	_form_root.visible = def != null
	_toss_button.disabled = def == null
	if def != null:
		_name_edit.text = def.display_name
		_thumb_label.text = def.thumbnail if def.thumbnail != "" else "(沒有,桌面上用替代圖示)"
		_desktop_label.text = def.desktop_texture if def.desktop_texture != "" else "(沿用縮圖)"
		_toss_check.button_pressed = def.toss
		_rub_check.button_pressed = def.rub
		_consume_check.button_pressed = def.consume_on_rub
		_reaction_option.select(0 if def.default_reaction == "pickup" else 1)
		_timeout_spin.value = def.timeout_seconds
		_use_anim_option.select(maxi(PropDef.USE_ANIMS.find(def.use_anim), 0))
		_shakes_spin.value = def.use_shakes
		_effect_option.select(0 if def.effect == "" else 1 + _catalog_index(def.effect))
		_effect_after_option.select(0 if def.effect_after == "" else 1 + _catalog_index(def.effect_after))
		_sprite_label.text = tr("已設定(%d 個狀態有圖)") % _sprite_state_count(def) if PropLibrary.has_sprite(def) else tr("(沒有,用上面簡單版的圖)")
		_attract_check.button_pressed = def.attract_while_dragging
		_hold_check.button_pressed = def.holdable
		_hold_place_option.select(maxi(PropDef.HOLD_PLACES.find(def.hold_place), 0))
		_shape_option.select(maxi(PropDef.SHAPES.find(def.shape), 0))
		_negative_check.button_pressed = def.disable_negative
		_show_light(def)
		_positive_check.button_pressed = def.disable_positive
		_energy_spin.value = def.restore_energy
		_rebuild_bindings()
	_updating = false


## 進階貼圖裡有圖的狀態數(預設、被使用、拖曳中)。
func _sprite_state_count(def: PropDef) -> int:
	var frames := PropLibrary.load_sprite(def)
	if frames == null:
		return 0
	var count := 0
	for state in PropLibrary.SPRITE_STATES:
		if frames.has_animation(StringName(state + "_0")):
			count += 1
	return count


## 特效名稱(中文或英文代號)在 CATALOG 裡的位置(找不到 0)。
func _catalog_index(effect_name: String) -> int:
	var key := PetEffects.resolve(effect_name)
	for i in PetEffects.CATALOG.size():
		if PetEffects.resolve(PetEffects.CATALOG[i]) == key:
			return i
	return 0


## 改完一個欄位:套用、存檔;存失敗顯示原因。
## 光源欄位:改一個值、存檔、預覽跟著更新。
func _edit_light(key: String, value: Variant) -> void:
	if _current == null or _updating:
		return
	_edit(func() -> void: _current.light = PropDef.clean_light(_current.light.merged({key: value}, true)))
	_light_preview.set_state(_current.light, PropLibrary.texture_of(_current))


## 顏色文字框:格式不對就還原成目前的顏色,對了才存。
func _apply_light_color() -> void:
	if _current == null or _updating:
		return
	var text := _light_color.text.strip_edges()
	if text != "" and not text.begins_with("#"):
		text = "#" + text
	if Color.html_is_valid(text):
		_edit_light("color", text)
		_light_swatch.color = Color(text)
	_light_color.text = str(PropDef.clean_light(_current.light)["color"])


func _show_light(def: PropDef) -> void:
	var light := PropDef.clean_light(def.light)
	_light_check.button_pressed = bool(light["enabled"])
	_light_x.value = roundf(float(light["x"]) * 100.0)
	_light_y.value = roundf(-float(light["y"]) * 100.0)
	_light_radius.value = float(light["radius"])
	_light_energy.value = float(light["energy"])
	_light_color.text = str(light["color"])
	_light_swatch.color = Color(str(light["color"]))
	_light_preview.set_state(light, PropLibrary.texture_of(def))


func _edit(apply: Callable) -> void:
	if _current == null or _updating:
		return
	apply.call()
	var error := PropLibrary.save_def(_current)
	if error != "":
		_say(error)


func _apply_name() -> void:
	if _current == null or _updating:
		return
	var wanted := PropDef.clean_name(_name_edit.text)
	if wanted == _current.display_name:
		return
	if wanted == "":
		_say("名稱不能是空的。")
		_name_edit.text = _current.display_name
		return
	if PropLibrary.name_taken(wanted, _current.id):
		_say(tr("已經有一個叫「%s」的道具了。") % wanted)
		_name_edit.text = _current.display_name
		return
	_edit(func() -> void: _current.display_name = wanted)
	reload(_current.id)
	_say(tr("已改名為「%s」。") % wanted)


func _rebuild_bindings() -> void:
	for child in _value_rows.get_children():
		child.queue_free()
	for child in _lens_rows.get_children():
		child.queue_free()
	if _current == null:
		return
	for index in _current.value_bindings.size():
		_value_rows.add_child(_value_row(index))
	for index in _current.lens_bindings.size():
		_lens_rows.add_child(_lens_row(index))


func _value_row(index: int) -> Control:
	var binding: Dictionary = _current.value_bindings[index]
	var row := HBoxContainer.new()
	var scope := OptionButton.new()
	scope.add_item("局部")
	scope.add_item("全域")
	scope.select(1 if str(binding["scope"]) == "global" else 0)
	scope.item_selected.connect(func(i: int) -> void: _edit(func() -> void: _current.value_bindings[index]["scope"] = "global" if i == 1 else "local"))
	row.add_child(scope)
	var key := ManagerUi.line_edit("數值名稱")
	key.text = str(binding["key"])
	key.max_length = PropDef.MAX_KEY
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.text_changed.connect(func(text: String) -> void: _edit(func() -> void: _current.value_bindings[index]["key"] = text.strip_edges()))
	row.add_child(key)
	var delta := ManagerUi.spin(0.5)
	delta.prefix = "增減 "
	delta.value = float(binding["delta"])
	delta.value_changed.connect(func(value: float) -> void: _edit(func() -> void: _current.value_bindings[index]["delta"] = value))
	row.add_child(delta)
	var remove := ManagerUi.button("✕")
	remove.pressed.connect(func() -> void:
		_edit(func() -> void: _current.value_bindings.remove_at(index))
		_rebuild_bindings())
	row.add_child(remove)
	return row


func _lens_row(index: int) -> Control:
	var binding: Dictionary = _current.lens_bindings[index]
	var row := HBoxContainer.new()
	var op := OptionButton.new()
	op.add_item("啟用")
	op.add_item("解除")
	op.select(1 if str(binding["op"]) == "disable" else 0)
	op.item_selected.connect(func(i: int) -> void: _edit(func() -> void: _current.lens_bindings[index]["op"] = "disable" if i == 1 else "enable"))
	row.add_child(op)
	var lens := ManagerUi.line_edit("狀態鏡名稱")
	lens.text = str(binding["lens"])
	lens.max_length = PropDef.MAX_KEY
	lens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lens.text_changed.connect(func(text: String) -> void: _edit(func() -> void: _current.lens_bindings[index]["lens"] = text.strip_edges()))
	row.add_child(lens)
	var remove := ManagerUi.button("✕")
	remove.pressed.connect(func() -> void:
		_edit(func() -> void: _current.lens_bindings.remove_at(index))
		_rebuild_bindings())
	row.add_child(remove)
	return row


# --- 圖片 ---

func _choose_image(slot: String) -> void:
	if _current == null:
		return
	FloatingWindow.native_file_dialog(tr("選擇圖片"), "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp;圖片"]),
			func(paths: PackedStringArray) -> void: import_image(slot, paths[0]), get_window().get_window_id())


## 匯入圖片(slot = thumbnail / desktop);失敗顯示原因、原本的圖不動。
func import_image(slot: String, source_path: String) -> String:
	if _current == null:
		return "沒有選中的道具。"
	var error := PropLibrary.import_image(_current, slot, source_path)
	if error != "":
		_say(error)
		return error
	PropLibrary.save_def(_current)
	reload(_current.id)
	_say("圖片已匯入。")
	return ""


func clear_image(slot: String) -> void:
	if _current == null:
		return
	if slot == "thumbnail":
		_current.thumbnail = ""
	else:
		_current.desktop_texture = ""
	PropLibrary.save_def(_current)
	reload(_current.id)


# --- 丟到桌面 ---

## 清空桌面上丟出來的道具,回傳清掉幾個。
func clear_props() -> int:
	return _manager.clear_all() if _manager != null else 0


## 把選中的道具丟到桌面(從行動區上方隨機位置掉下來)。
func toss_current() -> PropItem:
	if _current == null or _manager == null:
		return null
	_say(tr("已丟出「%s」。") % _current.display_name)
	return _manager.spawn(_current)


func _say(text: String) -> void:
	if _status != null:
		_status.text = text
