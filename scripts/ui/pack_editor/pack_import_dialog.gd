class_name PackImportDialog
extends ConfirmationDialog
## 素材包編輯器的匯入對話框:匯入圖片(單張或多張)與匯入精靈圖共用。
## 問使用者:動作名稱、動作已存在時「覆蓋(取代原有的幀)」還是「新增(接在原有的幀後面)」;精靈圖還要設格線並預覽切片。
## 按確定後發出 import_confirmed(params):{action, mode("replace" / "append"), grid(只有精靈圖)}。

signal import_confirmed(params: Dictionary)

const PREVIEW_SIZE := Vector2(480, 300)

var _existing: Array[String] = []
var _is_sheet := false
var _sheet_image: Image
var _sheet_size := Vector2i.ZERO
var _name_edit: LineEdit
var _mode_row: HBoxContainer
var _mode_option: OptionButton
var _exists_label: Label
var _grid_box: VBoxContainer
var _method_option: OptionButton
var _cols_spin: SpinBox
var _rows_spin: SpinBox
var _cell_w_spin: SpinBox
var _cell_h_spin: SpinBox
var _margin_spin: SpinBox
var _spacing_spin: SpinBox
var _skip_empty: CheckBox
var _count_label: Label
var _preview: SheetPreview
var _rects: Array[Rect2i] = []


## 匯入圖片:file_names 只是列出來給使用者看,existing 是素材包裡已有的動作名稱。
func setup_images(file_names: Array, existing: Array[String], suggested_name: String) -> void:
	_existing = existing
	_is_sheet = false
	title = "匯入圖片"
	_build(tr("要匯入 %d 張圖片:%s%s\n每張圖是這個動作的一幀(只選一張圖 = 單幀動作)。") % [file_names.size(), ", ".join(file_names.slice(0, 4)), "…" if file_names.size() > 4 else ""], suggested_name)


## 匯入精靈圖:image 是讀進來的精靈圖(預覽格線用)。
func setup_sheet(image: Image, file_name: String, existing: Array[String], suggested_name: String) -> void:
	_existing = existing
	_is_sheet = true
	_sheet_image = image
	_sheet_size = Vector2i(image.get_width(), image.get_height())
	title = "匯入精靈圖"
	_build(tr("精靈圖:%s(%d × %d)\n設好格線,下方預覽會標出每個切片;切片只是引用精靈圖的區域,不會另外產生圖檔。") % [file_name, _sheet_size.x, _sheet_size.y], suggested_name)
	_refresh_grid()


func _build(intro: String, suggested_name: String) -> void:
	ok_button_text = "匯入"
	cancel_button_text = "取消"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var intro_label := Label.new()
	intro_label.text = intro
	intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_label.custom_minimum_size.x = PREVIEW_SIZE.x
	box.add_child(intro_label)
	_name_edit = ManagerUi.line_edit("動作名稱,例如 walk、idle、sit")
	_name_edit.text = suggested_name
	_name_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	box.add_child(ManagerUi.labeled("動作名稱", _name_edit))
	_mode_row = HBoxContainer.new()
	_exists_label = Label.new()
	_exists_label.text = tr("這個動作已存在:")
	_mode_option = OptionButton.new()
	_mode_option.add_item(tr("新增(接在原有的幀後面)"))
	_mode_option.add_item(tr("覆蓋(取代原有的幀)"))
	_mode_option.tooltip_text = tr("覆蓋不會刪掉舊的圖片檔,只是這個動作改用新的幀;覆蓋後這個動作原有的軸心/圖片偏移設定會清掉。可以用撤回還原。")
	_mode_row.add_child(_exists_label)
	_mode_row.add_child(_mode_option)
	box.add_child(_mode_row)
	if _is_sheet:
		_build_grid(box)
	get_ok_button().disabled = true
	confirmed.connect(_on_confirmed)
	_refresh()


func _build_grid(box: VBoxContainer) -> void:
	_grid_box = VBoxContainer.new()
	box.add_child(_grid_box)
	_method_option = OptionButton.new()
	_method_option.add_item(tr("用欄數與列數切"))
	_method_option.add_item(tr("用每格大小切"))
	_method_option.item_selected.connect(func(_i: int) -> void: _refresh_grid())
	_grid_box.add_child(ManagerUi.labeled("格線方式", _method_option))
	_cols_spin = _grid_spin(1, 64, 4)
	_rows_spin = _grid_spin(1, 64, 1)
	_cell_w_spin = _grid_spin(1, 4096, 32)
	_cell_h_spin = _grid_spin(1, 4096, 32)
	_margin_spin = _grid_spin(0, 512, 0)
	_spacing_spin = _grid_spin(0, 512, 0)
	_grid_box.add_child(ManagerUi.labeled("欄數", _cols_spin))
	_grid_box.add_child(ManagerUi.labeled("列數", _rows_spin))
	_grid_box.add_child(ManagerUi.labeled("每格寬", _cell_w_spin))
	_grid_box.add_child(ManagerUi.labeled("每格高", _cell_h_spin))
	_grid_box.add_child(ManagerUi.labeled("外圍邊距", _margin_spin))
	_grid_box.add_child(ManagerUi.labeled("格與格間距", _spacing_spin))
	_skip_empty = CheckBox.new()
	_skip_empty.text = tr("略過全透明的格子(尾端沒畫的空格)")
	_skip_empty.button_pressed = true
	_skip_empty.toggled.connect(func(_on: bool) -> void: _refresh_grid())
	_grid_box.add_child(_skip_empty)
	_preview = SheetPreview.new()
	_preview.custom_minimum_size = PREVIEW_SIZE
	_preview.set_sheet(ImageTexture.create_from_image(_sheet_image), _sheet_size)
	_grid_box.add_child(_preview)
	_count_label = Label.new()
	_grid_box.add_child(_count_label)


func _grid_spin(min_value: int, max_value: int, start: int) -> SpinBox:
	var spin := ManagerUi.spin(1.0, float(min_value), float(max_value))
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.value = start
	spin.value_changed.connect(func(_v: float) -> void: _refresh_grid())
	return spin


## 目前設定的格線(見 PackEditorModel.sheet_rects)。
func current_grid() -> Dictionary:
	var by_cell := _method_option.selected == 1
	var grid := {"margin": Vector2i(int(_margin_spin.value), int(_margin_spin.value)), "spacing": Vector2i(int(_spacing_spin.value), int(_spacing_spin.value)), "skip_empty": _skip_empty.button_pressed}
	if by_cell:
		grid["cell"] = Vector2i(int(_cell_w_spin.value), int(_cell_h_spin.value))
	else:
		grid["cols"] = int(_cols_spin.value)
		grid["rows"] = int(_rows_spin.value)
	return grid


func _refresh_grid() -> void:
	var by_cell := _method_option.selected == 1
	for spin: SpinBox in [_cols_spin, _rows_spin]:
		spin.get_parent().visible = not by_cell
	for spin: SpinBox in [_cell_w_spin, _cell_h_spin]:
		spin.get_parent().visible = by_cell
	_rects = PackEditorModel.sheet_rects(_sheet_size, current_grid(), _sheet_image)
	_preview.set_rects(_rects)
	_count_label.text = tr("會切出 %d 個切片") % _rects.size() if not _rects.is_empty() else tr("用這組格線切不出任何切片(檢查欄列數、邊距與間距)")
	_refresh()


func _refresh() -> void:
	var clean_name := SpritePackLoader.clean_action_name(_name_edit.text)
	_mode_row.visible = _existing.has(clean_name) and clean_name != ""
	var sheet_ok := not _is_sheet or not _rects.is_empty()
	get_ok_button().disabled = clean_name == "" or not sheet_ok


func _on_confirmed() -> void:
	var params := {
		"action": SpritePackLoader.clean_action_name(_name_edit.text),
		"mode": "replace" if _mode_option.selected == 1 else "append",
	}
	if _is_sheet:
		params["grid"] = current_grid()
	import_confirmed.emit(params)


## 精靈圖預覽:把整張圖縮放到預覽框裡,疊上每個切片的框與序號。
class SheetPreview extends Control:
	var _texture: Texture2D
	var _image_size := Vector2i.ONE
	var _rects: Array[Rect2i] = []

	func set_sheet(texture: Texture2D, image_size: Vector2i) -> void:
		_texture = texture
		_image_size = Vector2i(maxi(image_size.x, 1), maxi(image_size.y, 1))
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		queue_redraw()

	func set_rects(rects: Array[Rect2i]) -> void:
		_rects = rects
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.16, 0.19))
		if _texture == null:
			return
		var scale_factor := minf(size.x / float(_image_size.x), size.y / float(_image_size.y))
		var shown := Vector2(_image_size) * scale_factor
		var origin := (size - shown) * 0.5
		draw_texture_rect(_texture, Rect2(origin, shown), false)
		var font := get_theme_default_font()
		for i in _rects.size():
			var rect := Rect2(origin + Vector2(_rects[i].position) * scale_factor, Vector2(_rects[i].size) * scale_factor)
			draw_rect(rect, Color(0.35, 1.0, 0.45, 0.9), false, 1.0)
			if rect.size.x >= 14.0 and rect.size.y >= 14.0:
				draw_string(font, rect.position + Vector2(2, 12), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 0.4))
