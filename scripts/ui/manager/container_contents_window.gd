class_name ContainerContentsWindow
extends FloatingWindow
## 使用者雙擊一件容器家具打開的「查看內容物」視窗(見 FurnitureManager.container_open_requested)。
## 列出這件家具容器裡設定的每種道具、目前還剩幾個/補滿上限,按「全部補滿」立刻補到上限。
## 桌寵自主拿取(見 Pet._tick_container_seek)跟這裡補充共用同一份即時庫存(FurnitureItem.container_remaining),
## 開著視窗時桌寵把東西拿走,數字會在下一次 _refresh() 反映出來,不用重開視窗。

var _item: FurnitureItem
var _list: ItemList
var _refill_button: Button
var _status: Label


func setup(item: FurnitureItem) -> void:
	_item = item
	var name_text := item.def.display_name if item.def != null else ""
	setup_floating(tr("容器內容物 — %s") % name_text, Vector2i(360, 320), Vector2i(300, 240))
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
	page.add_child(ManagerUi.heading_with_info(name_text, "桌寵會自主走過來拿(要喜歡這個道具、容器還有庫存、桌面上同一種道具還沒到上限)。這裡可以查看目前每種道具還剩幾個,按「全部補滿」立刻補到上限。"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_list)
	_refill_button = ManagerUi.button("全部補滿")
	_refill_button.pressed.connect(_on_refill_pressed)
	page.add_child(_refill_button)
	_status = Label.new()
	_status.theme_type_variation = AppSettings.MUTED_LABEL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_status)
	if is_instance_valid(_item):
		_item.play_interacted()
	_refresh()
	var sync := Timer.new()
	sync.wait_time = 1.0
	sync.autostart = true
	sync.timeout.connect(_refresh)
	add_child(sync)


func _refresh() -> void:
	if not is_instance_valid(_item) or _item.def == null:
		_status.text = tr("這件家具已經不在桌面上了。")
		_list.clear()
		_refill_button.disabled = true
		return
	_list.clear()
	for entry: Dictionary in _item.def.container_items:
		var id := str(entry["id"])
		var capacity := int(entry["capacity"])
		var remaining := _item.container_remaining_of(id)
		var def := PropLibrary.load_def(id)
		var label := def.display_name if def != null else tr("(找不到道具:%s)") % id
		_list.add_item("%s:%d / %d" % [label, remaining, capacity])
	_refill_button.disabled = false


func _on_refill_pressed() -> void:
	if not is_instance_valid(_item):
		return
	_item.container_refill()
	_item.play_interacted()
	_status.text = tr("已補滿。")
	_refresh()
