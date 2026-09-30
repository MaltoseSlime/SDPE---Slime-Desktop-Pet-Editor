class_name HoverBall
extends Node2D
## 懸浮球:放在行動區角落的小圓鈕,平時低透明度,滑鼠移過去才現身並展開選單(各懸浮視窗的入口 + 道具欄開關 + 清空桌面道具)。
## 道具欄:一塊放在行動區裡的小面板,只列出「已經存在的道具」,把道具圖示拖進場內就丟出一個(由 PropManager 接手拖曳);
## 可以隨時用右上角 ✕ 關掉,再從懸浮球叫出來。球可以用滑鼠拖到別的角落(位置與道具欄開關存在 user://settings.cfg 的 [hover_ball])。
## 全部用程式畫,是「Cutout」群組成員(提供自己的形狀給穿透多邊形);滑鼠位置用作業系統的滑鼠座標判斷(游標在穿透區時視窗收不到事件)。

signal action_requested(action: String)
## 在球本體上按右鍵:保底的右鍵暫時穿透觸發(backlog 第24點)——懸浮球位置固定、隨時看得到,不用去找行動區
## 邊框(邊框隱藏時第14點已經修過,這裡是額外的保底,不做成可關的開關,固定生效)。
signal right_click_requested

const SETTINGS_PATH := "user://settings.cfg"
const BALL_RADIUS := 20.0
const IDLE_ALPHA := 0.28
const MENU_WIDTH := 150.0
const MENU_ROW := 30.0
const COLLAPSE_DELAY := 0.5
const SLOT := Vector2(64.0, 72.0)
const PANEL_COLUMNS := 4
const PANEL_ROWS := 2
const PANEL_HEADER := 30.0
const PANEL_PAD := 8.0
const DRAG_START_DISTANCE := 6.0
## 拖曳中(按住球或面板標題列時)穿透形狀往外放大這麼多像素:視窗形狀的更新比畫面晚一影格,快速位移時新畫出來的部分不會被舊形狀裁掉(破圖);平時形狀貼著元件、不放大。
const DRAG_CUTOUT_GROW := 120.0
const MENU_ITEMS: Array[Array] = [
	["inventory", "道具欄"],
	["library", "角色庫…"],
	["manager", "桌寵管理…"],
	["props", "道具管理…"],
	["furniture", "家具庫…"],
	["settings", "全局設定…"],
	["tester", "測試者面板…"],
	["pack_editor", "精靈圖編輯器…"],
	["clear_props", "清掃桌面道具"],
]

var _area: Node
var _manager: PropManager
## 球心在行動區裡的位置(0~1 的比例,行動區大小改了球還在同一個角落)。
var _fraction := Vector2(0.94, 0.9)
var _expanded := false
var _leave_timer := 0.0
var _inventory_open := false
var _defs: Array[PropDef] = []
var _icons: Dictionary = {}
var _refresh_left := 0.0
var _scroll_col := 0
var _mouse := Vector2.ZERO   # 畫布座標
var _hover_id := ""
var _pressing_ball := false
var _dragging_ball := false
var _press_position := Vector2.ZERO
## 道具欄面板可以用滑鼠拖標題列移動:custom 位置(左上角,行動區比例 0~1);沒拖過就跟著球排版。
var _panel_fraction: Variant = null
var _dragging_panel := false
var _panel_grab := Vector2.ZERO
var _rects: Dictionary = {}   # id → Rect2(畫布座標),每次排版重算
## 上一次排版時的行動區範圍:平時球與面板不會動,只有行動區改大小、選單展開/收合、拖曳、道具欄變動時才重排(_layout),不再每影格重算。
var _last_area := Rect2()
var _shell_state: Node


func setup(action_area: Node, manager: PropManager) -> void:
	_area = action_area
	_manager = manager
	_shell_state = get_node("/root/DesktopShellState")
	_shell_state.passthrough_started.connect(func() -> void: set_inventory_open(false))   # 右鍵穿透時道具欄直接收起來
	# 2026-09-30 使用者實機回報:調整行動區邊框時球會被留在框外點不到。_process() 本來就會每影格比對
	# _area_rect() 跟 _last_area 補排版,但拖邊框是連續動作,直接接 boundary_changed 訊號可以在邊框「這一下」
	# 變動的當下立刻排版,不等下一影格,也不用依賴 _area 物件剛好有這個訊號(沒有就照舊靠 _process() 補)。
	# 同一天使用者又回報「球沒有跟著走」:_layout() 只更新 _rects(點擊判定用的資料),不會自己畫面重繪——
	# 平時靠 _process() 的 previous != _expanded / _dragging_ball 才會補一次 queue_redraw(),但那兩個條件
	# 都跟「邊框被拖」無關,所以球的點擊範圍其實已經跟上了,畫面上卻還停在舊位置沒有真的重畫,才會看起來
	# 「沒有跟著走」。這裡直接補一次 queue_redraw(),邊框變動的當下就把球畫到新位置。
	if "boundary_changed" in _area.get_signal_list().map(func(s: Dictionary) -> String: return str(s["name"])):
		_area.boundary_changed.connect(func(_rect: Rect2) -> void: _layout(); queue_redraw())
	add_to_group("Cutout")
	z_index = 30
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_fraction = Vector2(clampf(float(config.get_value("hover_ball", "x", _fraction.x)), 0.02, 0.98), clampf(float(config.get_value("hover_ball", "y", _fraction.y)), 0.05, 0.98))
		_inventory_open = bool(config.get_value("hover_ball", "inventory_open", false))
		if config.has_section_key("hover_ball", "panel_x"):
			_panel_fraction = Vector2(clampf(float(config.get_value("hover_ball", "panel_x", 0.5)), 0.0, 1.0), clampf(float(config.get_value("hover_ball", "panel_y", 0.5)), 0.0, 1.0))
	_layout()


func _save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("hover_ball", "x", _fraction.x)
	config.set_value("hover_ball", "y", _fraction.y)
	config.set_value("hover_ball", "inventory_open", _inventory_open)
	if _panel_fraction is Vector2:
		config.set_value("hover_ball", "panel_x", (_panel_fraction as Vector2).x)
		config.set_value("hover_ball", "panel_y", (_panel_fraction as Vector2).y)
	config.save(SETTINGS_PATH)


func is_inventory_open() -> bool:
	return _inventory_open


func is_expanded() -> bool:
	return _expanded


func set_inventory_open(open: bool) -> void:
	_inventory_open = open
	if open:
		refresh_inventory()
	_save()
	_layout()
	queue_redraw()


## 球心位置:先照比例算,再用實際半徑(BALL_RADIUS)夾回行動區內,免得行動區被縮得很小時 _fraction 的
## 2%~98% 邊界margin(比例)小於球的實際半徑,讓球的一部分畫到框外、變成點不到(2026-09-30 使用者實機回報)。
func ball_center() -> Vector2:
	var rect := _area_rect()
	var raw := rect.position + rect.size * _fraction
	if rect.size.x <= BALL_RADIUS * 2.0 or rect.size.y <= BALL_RADIUS * 2.0:
		return rect.get_center()   # 行動區比球本身還小,直接置中,夾不出合理範圍。
	return Vector2(
		clampf(raw.x, rect.position.x + BALL_RADIUS, rect.end.x - BALL_RADIUS),
		clampf(raw.y, rect.position.y + BALL_RADIUS, rect.end.y - BALL_RADIUS))


func _area_rect() -> Rect2:
	if _area != null and "boundary_rect" in _area:
		var rect: Rect2 = _area.boundary_rect
		return Rect2(_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


## 重新載入道具欄要列的道具(已經存在的);圖示快取依圖片檔名與修改時間。
func refresh_inventory() -> void:
	_defs = PropLibrary.list()
	var alive := {}
	for def in _defs:
		alive[def.id] = true
		var file_name := def.desktop_texture if def.desktop_texture != "" else def.thumbnail
		var path := PropLibrary.folder_of(def.id).path_join(file_name) if file_name != "" else ""
		var sprite_icon := file_name == "" and PropLibrary.has_sprite(def)   # 沒有簡單版的圖,用進階貼圖預設狀態的第一幀
		var stamp := "%s|%d" % [file_name, FileAccess.get_modified_time(path)] if path != "" else ("sprite|%d" % PropLibrary._folder_stamp(PropLibrary.sprite_folder(def.id)) if sprite_icon else "")
		var cached: Dictionary = _icons.get(def.id, {})
		if str(cached.get("stamp", "!")) != stamp:
			_icons[def.id] = {"stamp": stamp, "texture": PropLibrary.texture_of(def, "thumbnail") if path != "" or sprite_icon else null}
	for id: String in _icons.keys():
		if not alive.has(id):
			_icons.erase(id)
	_scroll_col = clampi(_scroll_col, 0, _max_scroll_col())
	if _inventory_open:
		_layout()
	queue_redraw()


## 道具依「先往下填滿一直欄、再換下一欄」排列,只顯示 PANEL_COLUMNS 欄,超出的用滾輪水平捲動(每次一欄)。
func _max_scroll_col() -> int:
	return maxi(ceili(float(_defs.size()) / PANEL_ROWS) - PANEL_COLUMNS, 0)


# --- 排版 ---

## 算出球、選單各列、道具欄面板與各格的矩形。選單往行動區裡面長(球在下半就往上、在右半就靠右對齊)。
func _layout() -> void:
	_rects.clear()
	var area := _area_rect()
	_last_area = area
	var center := ball_center()
	_rects["ball"] = Rect2(center - Vector2.ONE * BALL_RADIUS, Vector2.ONE * BALL_RADIUS * 2.0)
	var grow_up := center.y > area.get_center().y
	var align_right := center.x > area.get_center().x
	var menu_x := center.x + BALL_RADIUS - MENU_WIDTH if align_right else center.x - BALL_RADIUS
	var menu_height := MENU_ROW * MENU_ITEMS.size()
	var menu_y := center.y - BALL_RADIUS - 6.0 - menu_height if grow_up else center.y + BALL_RADIUS + 6.0
	if _expanded:
		_rects["menu"] = Rect2(menu_x, menu_y, MENU_WIDTH, menu_height)
		for i in MENU_ITEMS.size():
			_rects["item:" + str(MENU_ITEMS[i][0])] = Rect2(menu_x, menu_y + MENU_ROW * i, MENU_WIDTH, MENU_ROW)
	if _inventory_open:
		var panel_size := Vector2(PANEL_PAD * 2.0 + SLOT.x * PANEL_COLUMNS, PANEL_HEADER + PANEL_PAD + SLOT.y * PANEL_ROWS)
		var panel_x := center.x - BALL_RADIUS - 10.0 - panel_size.x if align_right else center.x + BALL_RADIUS + 10.0
		var panel_y := center.y + BALL_RADIUS - panel_size.y if grow_up else center.y - BALL_RADIUS
		var panel := Rect2(panel_x, panel_y, panel_size.x, panel_size.y)
		if _panel_fraction is Vector2:
			panel.position = area.position + (area.size - panel_size).max(Vector2.ZERO) * (_panel_fraction as Vector2)
		panel.position.x = clampf(panel.position.x, area.position.x, maxf(area.end.x - panel.size.x, area.position.x))
		panel.position.y = clampf(panel.position.y, area.position.y, maxf(area.end.y - panel.size.y, area.position.y))
		_rects["panel"] = panel
		_rects["close"] = Rect2(panel.end.x - 26.0, panel.position.y + 4.0, 22.0, 22.0)
		_rects["panel_header"] = Rect2(panel.position, Vector2(panel.size.x - 30.0, PANEL_HEADER))
		var first := _scroll_col * PANEL_ROWS
		for i in mini(PANEL_COLUMNS * PANEL_ROWS, maxi(_defs.size() - first, 0)):
			var col := i / PANEL_ROWS
			var row := i % PANEL_ROWS
			_rects["slot:%d" % (first + i)] = Rect2(panel.position + Vector2(PANEL_PAD + col * SLOT.x, PANEL_HEADER + row * SLOT.y), SLOT)


func _process(delta: float) -> void:
	if _area == null or _shell_state.is_passthrough_frozen:
		return   # 右鍵穿透期間不能操作(也不會拖動),什麼都不用算
	var os_mouse := Vector2(DisplayServer.mouse_get_position()) - Vector2(get_window().position)
	var over_ball := _rect_has("ball", os_mouse) or (_expanded and _rect_has("menu", os_mouse))
	var previous := _expanded
	if over_ball and not _dragging_ball:
		_expanded = true
		_leave_timer = COLLAPSE_DELAY
	elif _expanded:
		_leave_timer -= delta
		if _leave_timer <= 0.0:
			_expanded = false
	if _inventory_open:
		_refresh_left -= delta
		if _refresh_left <= 0.0:
			_refresh_left = 3.0
			refresh_inventory()
	if previous != _expanded or _area_rect() != _last_area:
		_layout()   # 平時沒有變化就不重排(拖曳中由 _on_motion 排版)
	if previous != _expanded or _dragging_ball:
		queue_redraw()


func _rect_has(id: String, point: Vector2) -> bool:
	return _rects.has(id) and (_rects[id] as Rect2).grow(2.0).has_point(point)


## 正在被抓著(或剛按下、快要拖)的元件:穿透形狀放大,見 DRAG_CUTOUT_GROW。
func _is_grabbed(id: String) -> bool:
	return (id == "ball" and (_pressing_ball or _dragging_ball)) or (id == "panel" and _dragging_panel)


func get_cutout_polygons() -> Array:
	var polygons: Array = []
	if _inventory_open:
		# 道具欄開著時整個行動區都收滑鼠:道具欄可以隨便拖、位置變了視窗形狀也不用跟著更新(不會破圖)。要點到底下的桌面請按右鍵穿透(那時道具欄會自己收起來)。
		polygons.append(DialogueBubble._rect_polygon(_area_rect()))
	for id in ["ball", "menu"] if _inventory_open else ["ball", "menu", "panel"]:
		if _rects.has(id):
			var rect: Rect2 = _rects[id]
			polygons.append(DialogueBubble._rect_polygon(rect.grow(DRAG_CUTOUT_GROW if _is_grabbed(id) or (id == "menu" and _dragging_ball) else 4.0)))
	return polygons


# --- 輸入 ---

func _input(event: InputEvent) -> void:
	if _area == null:
		return
	if event is InputEventMouse:
		_mouse = get_viewport().get_canvas_transform().affine_inverse() * event.position
	if _shell_state.is_passthrough_frozen:
		return
	if event is InputEventMouseMotion:
		_on_motion()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press()
		else:
			_on_release()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _on_right_click():
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and _inventory_open and _rect_has("panel", _mouse) and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			scroll_inventory(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			scroll_inventory(1)
			get_viewport().set_input_as_handled()


## 道具欄水平捲動 columns 欄(負數往左)。
func scroll_inventory(columns: int) -> void:
	_scroll_col = clampi(_scroll_col + columns, 0, _max_scroll_col())
	_layout()
	queue_redraw()


func _on_motion() -> void:
	var previous := _hover_id
	_hover_id = _id_at(_mouse)
	if _pressing_ball and not _dragging_ball and _mouse.distance_to(_press_position) > DRAG_START_DISTANCE:
		_dragging_ball = true
	if _dragging_panel:
		var panel_area := _area_rect()
		var panel_size: Vector2 = (_rects["panel"] as Rect2).size
		var free := (panel_area.size - panel_size).max(Vector2.ONE)
		var top_left := _mouse - _panel_grab
		_panel_fraction = Vector2(clampf((top_left.x - panel_area.position.x) / free.x, 0.0, 1.0), clampf((top_left.y - panel_area.position.y) / free.y, 0.0, 1.0))
		_layout()
	if _dragging_ball:
		var area := _area_rect()
		_fraction = Vector2(clampf((_mouse.x - area.position.x) / maxf(area.size.x, 1.0), 0.02, 0.98), clampf((_mouse.y - area.position.y) / maxf(area.size.y, 1.0), 0.05, 0.98))
		_layout()
	if previous != _hover_id:
		queue_redraw()


## 這個座標下的元件 id(item:xxx / slot:N / close / ball / panel / menu),沒有回空字串。
## 2026-09-30 使用者實機回報:選單/道具欄明明沒顯示,舊位置卻還點得到——_rects 理論上每次 _layout() 都會
## 清空重建,但 _process()(切換展開/收合)跟 _input()(滑鼠點擊)是分開跑的兩條路徑,收合前後有一個很窄的
## 時序縫隙讓點擊撞到殘留的舊 rect。這裡不管 _rects 字典裡還留著什麼,直接照目前真正的狀態(_expanded /
## _inventory_open)把不該存在的那幾種 id 擋掉,不依賴「_rects 一定跟狀態同步」這個假設。
func _id_at(point: Vector2) -> String:
	for id: String in _rects:
		if id.begins_with("item:"):
			if not _expanded:
				continue
		elif id.begins_with("slot:") or id == "close" or id == "panel_header":
			if not _inventory_open:
				continue
		else:
			continue
		if (_rects[id] as Rect2).has_point(point):
			return id
	for id in ["ball", "panel", "menu"]:
		if id == "panel" and not _inventory_open:
			continue
		if id == "menu" and not _expanded:
			continue
		if _rects.has(id) and (_rects[id] as Rect2).has_point(point):
			return id
	return ""


## 球本體上按右鍵:保底的右鍵暫時穿透(見 right_click_requested 檔頭)。回傳有沒有真的觸發(給呼叫端決定要不要吃掉事件)。
func _on_right_click() -> bool:
	if _id_at(_mouse) != "ball":
		return false
	right_click_requested.emit()
	return true


func _on_press() -> void:
	var id := _id_at(_mouse)
	if id == "":
		return
	get_viewport().set_input_as_handled()
	if id == "ball":
		_pressing_ball = true
		_dragging_ball = false
		_press_position = _mouse
	elif id == "close":
		set_inventory_open(false)
	elif id == "panel_header":
		_dragging_panel = true
		_panel_grab = _mouse - (_rects["panel"] as Rect2).position
	elif id.begins_with("slot:"):
		var index := int(id.trim_prefix("slot:"))
		if index >= 0 and index < _defs.size():
			_manager.spawn_dragged(_defs[index], _mouse)
	elif id.begins_with("item:"):
		_run_action(id.trim_prefix("item:"))


func _on_release() -> void:
	if _dragging_panel:
		_dragging_panel = false
		_save()
		get_viewport().set_input_as_handled()
		return
	if _pressing_ball:
		if _dragging_ball:
			_save()
		else:
			_expanded = not _expanded   # 點一下球 = 展開/收起(手機、觸控筆沒有 hover 也能用)
			_leave_timer = COLLAPSE_DELAY * 4.0
		_pressing_ball = false
		_dragging_ball = false
		get_viewport().set_input_as_handled()


func _run_action(action: String) -> void:
	if action == "inventory":
		set_inventory_open(not _inventory_open)
		return
	_expanded = false
	if action == "clear_props":
		_manager.clear_all()
	action_requested.emit(action)


# --- 繪製 ---

func _draw() -> void:
	if _area == null or _rects.is_empty():
		return
	var look := AppSettings.appearance()
	var colors: Dictionary = look["colors"]
	var bg: Color = colors["bg"]
	var panel_color: Color = colors["panel"]
	var text_color: Color = colors["text"]
	var accent: Color = colors["accent"]
	var muted: Color = colors["muted"]
	var font := UiFonts.get_font(str(look["font"]))
	var alpha := 0.95 if (_expanded or _dragging_ball) else IDLE_ALPHA
	var center := ball_center() - global_position
	draw_circle(center, BALL_RADIUS, Color(accent, alpha))
	draw_arc(center, BALL_RADIUS, 0.0, TAU, 32, Color(text_color, alpha * 0.9), 2.0, true)
	for i in 3:
		draw_circle(center + Vector2(0.0, (i - 1) * 7.0), 2.6, Color(text_color, alpha))
	if _expanded and _rects.has("menu"):
		var menu: Rect2 = _rects["menu"]
		_box(Rect2(menu.position - global_position, menu.size), Color(bg, 0.96), accent)
		for entry in MENU_ITEMS:
			var id := "item:" + str(entry[0])
			var row: Rect2 = _rects[id]
			var local_row := Rect2(row.position - global_position, row.size)
			if _hover_id == id:
				draw_rect(local_row.grow(-2.0), accent)
			var label := tr(str(entry[1]))
			if str(entry[0]) == "inventory":
				label = ("✔ " if _inventory_open else "") + label
			draw_string(font, local_row.position + Vector2(12.0, MENU_ROW * 0.68), label, HORIZONTAL_ALIGNMENT_LEFT, MENU_WIDTH - 16.0, 15, text_color)
	if _inventory_open and _rects.has("panel"):
		var panel: Rect2 = _rects["panel"]
		var local_panel := Rect2(panel.position - global_position, panel.size)
		_box(local_panel, Color(bg, 0.96), accent)
		draw_string(font, local_panel.position + Vector2(PANEL_PAD + 2.0, PANEL_HEADER * 0.7), tr("道具欄"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, text_color)
		var close: Rect2 = _rects["close"]
		var local_close := Rect2(close.position - global_position, close.size)
		if _hover_id == "close":
			draw_rect(local_close, Color(0.77, 0.17, 0.11, 0.9))
		draw_string(font, local_close.position + Vector2(5.0, 16.0), "✕", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)
		if _defs.is_empty():
			draw_string(font, local_panel.position + Vector2(PANEL_PAD, PANEL_HEADER + 26.0), tr("還沒有道具"), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 16.0, 14, muted)
			draw_string(font, local_panel.position + Vector2(PANEL_PAD, PANEL_HEADER + 48.0), tr("到「道具管理」新增"), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 16.0, 12, muted)
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


func _box(rect: Rect2, fill: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	draw_style_box(style, rect)


func _draw_icon(font: Font, def: PropDef, slot: Rect2, text_color: Color) -> void:
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
