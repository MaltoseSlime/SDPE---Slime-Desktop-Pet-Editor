class_name LayerListView
extends ItemList
## 精靈圖編輯器「圖層」清單(2026-10-16):一般的 ItemList,每一列最右邊多畫一個鎖頭,點一下鎖上、再點一下打開(比照繪圖軟體的圖層鎖定)。
## 點鎖頭不會選取那一列;滑鼠停在鎖頭上的提示說明用法。名字太長的列截斷在鎖頭前面(2026-10-17)。

signal lock_toggled(row: int)

const LOCK_WIDTH := 26.0

## 每一列的鎖定狀態:true / false;null = 這一列沒有鎖頭(本體)。由編輯器在重排清單時一起填。
var locks: Array = []
var _full_texts: Array[String] = []


## 圖層鎖住時把改得到它的欄位停用,滑鼠停留提示加上「先解除鎖定」。解除鎖定只還原提示,能不能用交給編輯器平常的重整(它每次都會重算)。
static func mark_locked(control: Control, locked: bool) -> void:
	if not control.has_meta("lock_tip_base"):
		control.set_meta("lock_tip_base", control.tooltip_text)
	var base := str(control.get_meta("lock_tip_base"))
	if not locked:
		control.tooltip_text = base
		return
	var hint := PackLayers.lock_hint()
	control.tooltip_text = hint if base == "" else "%s\n\n%s" % [hint, control.tr(base)]
	if control is BaseButton:
		(control as BaseButton).disabled = true
	elif control is LineEdit:
		(control as LineEdit).editable = false
	elif control is SpinBox:
		(control as SpinBox).editable = false


## 編輯器先 add_item 再呼叫這個;這時記下每一列完整的文字,太長的截斷在鎖頭前面(加「…」,完整文字放滑鼠停留提示)。
func set_locks(list: Array) -> void:
	locks = list
	_full_texts.clear()
	for row in item_count:
		_full_texts.append(get_item_text(row))
	_fit_texts()
	queue_redraw()


## 這一列沒截斷的文字。
func full_text(row: int) -> String:
	return _full_texts[row] if row >= 0 and row < _full_texts.size() else get_item_text(row)


func _ready() -> void:
	get_v_scroll_bar().visibility_changed.connect(_fit_texts)   # 捲軸出現、消失,鎖頭跟著移,可用寬度也跟著變


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		_fit_texts()


func _fit_texts() -> void:
	if _full_texts.size() != item_count:
		return
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var panel := get_theme_stylebox("panel")
	var room := size.x - panel.get_margin(SIDE_LEFT) - panel.get_margin(SIDE_RIGHT) - LOCK_WIDTH - float(get_theme_constant("h_separation"))
	if get_v_scroll_bar().visible:
		room -= get_v_scroll_bar().size.x
	for row in item_count:
		var text := _full_texts[row]
		if row < locks.size() and locks[row] is bool:
			text = _ellipsize(text, font, font_size, room)
		if get_item_text(row) != text:
			set_item_text(row, text)


static func _ellipsize(text: String, font: Font, font_size: int, room: float) -> String:
	if room <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= room:
		return text
	var low := 0
	var high := text.length()
	while low < high:   # 找最多能留幾個字(加上「…」還放得下)
		var middle := (low + high + 1) / 2
		if font.get_string_size(text.left(middle) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= room:
			low = middle
		else:
			high = middle - 1
	return text.left(low) + "…"


## 這一列鎖頭的範圍(清單自己的座標,已扣掉捲動)。
func lock_rect(row: int) -> Rect2:
	var rect := get_item_rect(row, true)
	rect.position.y -= get_v_scroll_bar().value
	var right := size.x - get_theme_stylebox("panel").get_margin(SIDE_RIGHT)
	if get_v_scroll_bar().visible:
		right -= get_v_scroll_bar().size.x
	return Rect2(right - LOCK_WIDTH, rect.position.y, LOCK_WIDTH, rect.size.y)


func lock_row_at(at: Vector2) -> int:
	force_update_list_size()   # 列的位置平常畫的時候才算;點擊、停留時先確定是最新的
	for row in mini(locks.size(), item_count):
		if locks[row] is bool and lock_rect(row).has_point(at):
			return row
	return -1


func _draw() -> void:
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var color := get_theme_color("font_color")
	for row in mini(locks.size(), item_count):
		if not locks[row] is bool:
			continue
		var rect := lock_rect(row)
		if rect.end.y < 0.0 or rect.position.y > size.y:
			continue
		var locked := bool(locks[row])
		var baseline := rect.position.y + (rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		draw_string(font, Vector2(rect.position.x, baseline), "🔒" if locked else "🔓", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, Color(color, 1.0 if locked else 0.35))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover_tooltip((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var row := lock_row_at((event as InputEventMouseButton).position)
		if row >= 0:
			accept_event()   # 點鎖頭只切換鎖定,不選取那一列
			if (event as InputEventMouseButton).pressed:
				lock_toggled.emit(row)


## ItemList 的提示是逐列的(沒設就顯示列的文字),所以滑鼠停在鎖頭上時才把那一列的提示換成鎖頭說明。
func _update_hover_tooltip(at: Vector2) -> void:
	var lock_row := lock_row_at(at)
	for row in mini(locks.size(), item_count):
		# 鎖頭上 = 鎖頭說明;文字被截斷的列 = 完整文字;其他留空(ItemList 會顯示列的文字)
		var wanted := lock_tooltip(row) if row == lock_row else (full_text(row) if full_text(row) != get_item_text(row) else "")
		if get_item_tooltip(row) != wanted:
			set_item_tooltip(row, wanted)


func lock_tooltip(row: int) -> String:
	if row < 0 or row >= locks.size() or not locks[row] is bool:
		return ""
	return tr("已鎖定:這個圖層不能修改,調軸心、同步到其他動作也不會帶動它。點一下解除鎖定。") if bool(locks[row]) else tr("點一下鎖定這個圖層:鎖上後不能修改(位置、設定、圖片、裁切),調軸心、同步到其他動作也不會帶動它。")
