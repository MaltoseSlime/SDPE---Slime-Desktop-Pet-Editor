class_name FurnitureBar
extends Node2D
## 家具編輯模式開著時,行動區左上角的一塊小面板,形式跟道具欄(見 HoverBall)一樣:列出家具庫裡的家具,
## 把圖示拖進場內就放一件(FurnitureManager.spawn_dragged 接手拖曳)。編輯模式關掉時完全不畫、不算穿透形狀。
## 固定在左上角,先不做「拖標題列移動面板」那組(道具欄有的進階功能),之後有需要再加。

const SLOT := Vector2(64.0, 72.0)
const PANEL_COLUMNS := 4
const PANEL_ROWS := 2
const PANEL_HEADER := 30.0
const PANEL_PAD := 8.0
const MARGIN := 16.0
const REFRESH_INTERVAL := 3.0

var _area: Node
var _manager: FurnitureManager
var _defs: Array[FurnitureDef] = []
var _icons: Dictionary = {}
var _refresh_left := 0.0
var _scroll_col := 0
var _mouse := Vector2.ZERO
var _hover_id := ""
var _rects: Dictionary = {}
var _was_open := false
var _shell_state: Node


func setup(action_area: Node, manager: FurnitureManager) -> void:
	_area = action_area
	_manager = manager
	_shell_state = get_node("/root/DesktopShellState")
	add_to_group("Cutout")
	z_index = 30
	refresh_defs()


func _area_rect() -> Rect2:
	if _area != null and "boundary_rect" in _area:
		var rect: Rect2 = _area.boundary_rect
		return Rect2(_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


## 重新載入家具庫要列的家具;圖示快取依素材資料夾修改時間。
func refresh_defs() -> void:
	_defs = FurnitureLibrary.list()
	var alive := {}
	for def in _defs:
		alive[def.id] = true
		var path := FurnitureLibrary.folder_of(def.id).path_join(def.thumbnail) if def.thumbnail != "" else ""
		var sprite_icon := def.thumbnail == "" and FurnitureLibrary.has_sprite(def)
		var stamp := "%s|%d" % [def.thumbnail, FileAccess.get_modified_time(path)] if path != "" else ("sprite|%d" % FurnitureLibrary._folder_stamp(FurnitureLibrary.sprite_folder(def.id)) if sprite_icon else "none")
		var cached: Dictionary = _icons.get(def.id, {})
		if str(cached.get("stamp", "!")) != stamp:
			_icons[def.id] = {"stamp": stamp, "texture": FurnitureLibrary.texture_of(def) if path != "" or sprite_icon else null}
	for id: String in _icons.keys():
		if not alive.has(id):
			_icons.erase(id)
	_scroll_col = clampi(_scroll_col, 0, _max_scroll_col())
	_layout()
	queue_redraw()


## 家具依「先往下填滿一直欄、再換下一欄」排列,只顯示 PANEL_COLUMNS 欄,超出的用滾輪水平捲動(每次一欄)。
func _max_scroll_col() -> int:
	return maxi(ceili(float(_defs.size()) / PANEL_ROWS) - PANEL_COLUMNS, 0)


func _is_open() -> bool:
	return _manager != null and _manager.edit_mode


func _layout() -> void:
	_rects.clear()
	if not _is_open():
		return
	var area := _area_rect()
	var panel_size := Vector2(PANEL_PAD * 2.0 + SLOT.x * PANEL_COLUMNS, PANEL_HEADER + PANEL_PAD + SLOT.y * PANEL_ROWS)
	var panel := Rect2(area.position + Vector2(MARGIN, MARGIN), panel_size)
	_rects["panel"] = panel
	var first := _scroll_col * PANEL_ROWS
	for i in mini(PANEL_COLUMNS * PANEL_ROWS, maxi(_defs.size() - first, 0)):
		var col := i / PANEL_ROWS
		var row := i % PANEL_ROWS
		_rects["slot:%d" % (first + i)] = Rect2(panel.position + Vector2(PANEL_PAD + col * SLOT.x, PANEL_HEADER + row * SLOT.y), SLOT)


func _process(delta: float) -> void:
	if _manager == null:
		return
	var open := _is_open()
	if open != _was_open:
		_was_open = open
		refresh_defs()   # 剛打開:順便重新整理一次(離開編輯模式時 _layout() 自己清空,不用另外處理)
		if not open:
			_layout()
			queue_redraw()
	if not open:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_INTERVAL
		refresh_defs()


func get_cutout_polygons() -> Array:
	if not _is_open() or not _rects.has("panel"):
		return []
	return [DialogueBubble._rect_polygon((_rects["panel"] as Rect2).grow(4.0))]


func _input(event: InputEvent) -> void:
	if not _is_open():
		return
	if event is InputEventMouse:
		_mouse = get_viewport().get_canvas_transform().affine_inverse() * event.position
	if _shell_state != null and _shell_state.is_passthrough_frozen:
		return
	if event is InputEventMouseMotion:
		var previous := _hover_id
		_hover_id = _id_at(_mouse)
		if previous != _hover_id:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var id := _id_at(_mouse)
			if id.begins_with("slot:"):
				var index := int(id.trim_prefix("slot:"))
				if index >= 0 and index < _defs.size() and _manager != null:
					_manager.spawn_dragged(_defs[index], _mouse)
					get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			if _rect_has("panel", _mouse):
				scroll(-1)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			if _rect_has("panel", _mouse):
				scroll(1)
				get_viewport().set_input_as_handled()


func scroll(columns: int) -> void:
	_scroll_col = clampi(_scroll_col + columns, 0, _max_scroll_col())
	_layout()
	queue_redraw()


func _rect_has(id: String, point: Vector2) -> bool:
	return _rects.has(id) and (_rects[id] as Rect2).has_point(point)


func _id_at(point: Vector2) -> String:
	for id: String in _rects:
		if id.begins_with("slot:") and (_rects[id] as Rect2).has_point(point):
			return id
	return ""


func _draw() -> void:
	if not _is_open() or not _rects.has("panel"):
		return
	var look := AppSettings.appearance()
	var colors: Dictionary = look["colors"]
	var bg: Color = colors["bg"]
	var panel_color: Color = colors["panel"]
	var text_color: Color = colors["text"]
	var accent: Color = colors["accent"]
	var muted: Color = colors["muted"]
	var font := UiFonts.get_font(str(look["font"]))
	var panel: Rect2 = _rects["panel"]
	var local_panel := Rect2(panel.position - global_position, panel.size)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bg, 0.96)
	style.border_color = accent
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	draw_style_box(style, local_panel)
	draw_string(font, local_panel.position + Vector2(PANEL_PAD + 2.0, PANEL_HEADER * 0.7), tr("家具欄(編輯模式)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)
	if _defs.is_empty():
		draw_string(font, local_panel.position + Vector2(PANEL_PAD, PANEL_HEADER + 26.0), tr("還沒有家具"), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 16.0, 14, muted)
		draw_string(font, local_panel.position + Vector2(PANEL_PAD, PANEL_HEADER + 48.0), tr("到「家具庫」新增"), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 16.0, 12, muted)
	for id: String in _rects:
		if not id.begins_with("slot:"):
			continue
		var index := int(id.trim_prefix("slot:"))
		var def := _defs[index]
		var slot: Rect2 = _rects[id]
		var local_slot := Rect2(slot.position - global_position, slot.size).grow(-3.0)
		draw_rect(local_slot, Color(panel_color, 0.9) if _hover_id != id else accent)
		_draw_icon(font, def, local_slot, text_color)
	if _max_scroll_col() > 0:
		draw_string(font, local_panel.position + Vector2(panel.size.x - 90.0, PANEL_HEADER * 0.7), "◀ %d/%d ▶" % [_scroll_col + 1, _max_scroll_col() + 1], HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 11, muted)


func _draw_icon(font: Font, def: FurnitureDef, slot: Rect2, text_color: Color) -> void:
	var icon_box := Rect2(slot.position + Vector2(8.0, 4.0), Vector2(slot.size.x - 16.0, slot.size.x - 16.0))
	var texture: Texture2D = (_icons.get(def.id, {}) as Dictionary).get("texture")
	if texture != null:
		var texture_size := texture.get_size()
		var factor := minf(icon_box.size.x / maxf(texture_size.x, 1.0), icon_box.size.y / maxf(texture_size.y, 1.0))
		var draw_size := texture_size * factor
		draw_texture_rect(texture, Rect2(icon_box.get_center() - draw_size * 0.5, draw_size), false)
	else:
		var hue := float(absi(def.display_name.hash()) % 360) / 360.0
		var style := StyleBoxFlat.new()
		style.bg_color = Color.from_hsv(hue, 0.45, 0.95)
		style.set_corner_radius_all(6)
		draw_style_box(style, icon_box)
		var letter := def.display_name.left(1)
		draw_string(font, icon_box.position + Vector2(icon_box.size.x * 0.5 - 9.0, icon_box.size.y * 0.7), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.1, 0.1, 0.12))
	draw_string(font, slot.position + Vector2(2.0, slot.size.y - 6.0), def.display_name, HORIZONTAL_ALIGNMENT_CENTER, slot.size.x - 4.0, 11, text_color)
