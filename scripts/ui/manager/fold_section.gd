class_name FoldSection
extends VBoxContainer
## 可收合的區段(2026-10-15,精靈圖編輯器「圖層」頁整理):點標題列收起/展開,內容放進 content。
## 收合狀態只在這次開著的視窗裡記得。

signal toggled(open: bool)

var content: VBoxContainer
var _header: Button
var _title := ""


func _init(title: String, tip := "", open := true) -> void:
	_title = title
	add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_header = Button.new()
	_header.flat = true
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # 文字自己翻(前面接著 ▾ ▸)
	_header.pressed.connect(func() -> void: set_open(not content.visible))
	ManagerUi.fixed_font_size(_header, 16)
	row.add_child(_header)
	if tip != "":
		row.add_child(InfoIcon.new(tip))
	add_child(row)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	set_open(open)


func is_open() -> bool:
	return content.visible


func set_open(open: bool) -> void:
	content.visible = open
	_header.text = "%s %s" % ["▾" if open else "▸", TranslationServer.translate(_title)]
	_header.tooltip_text = TranslationServer.translate("點一下收起") if open else TranslationServer.translate("點一下展開")
	toggled.emit(open)
