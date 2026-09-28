class_name InfoIcon
extends Control
## 圓形的「i」小圖示:滑過去才顯示說明文字(tooltip)。視窗版面很擠時,長的說明不要直接印在畫面上,用它代替(見 ManagerUi.hint_row / heading_with_info)。
## 說明文字會自動折行(每行約 TIP_WIDTH 個字),不然長句的 tooltip 會拉成一整條。

const SIZE := 18.0
const TIP_WIDTH := 30

var _hover := false
## 說明文字可能是好幾段接起來(見 set_tip_parts):每一段要各自獨立查表翻譯,不能先串成一整串字面再當
## 查表 key——串起來的字串幾乎不可能剛好等於 translations/ui_strings.csv 裡的任何一筆原文,一定翻不到
## (2026-09-30 使用者回報「交互行為」的收合卡片標題與圈圈i沒翻譯到,根因除了下面 wrap_text 那個坑之外,
## 呼叫端(interaction_tab.gd)把 tip 跟 WEB_HINT 用 + 先接成一整串字面再傳進來,也是同一類問題)。
var _tip_parts: PackedStringArray = []


func _init(tip := "") -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP
	if tip != "":
		_tip_parts = [tip]
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func set_tip(tip: String) -> void:
	_tip_parts = [tip]


## 說明文字由好幾段組成(例如「這個功能怎麼用」+ 一段所有卡片共用的固定提示):每段各自是
## ui_strings.csv 裡獨立的一筆原文,顯示時各自翻譯、再用空行接起來,不要在呼叫端先用 + 串接。
func set_tip_parts(parts: PackedStringArray) -> void:
	_tip_parts = parts


## 不能在建立時就把翻譯結果先算好存進 tooltip_text:折行(wrap_text)是照字數切,存進 tooltip_text 的字串一旦
## 被折過行,就再也不等於 translations/ui_strings.csv 裡的原文 key,Godot 的自動翻譯(Control 屬性字串照原文查表,
## 不需要另外包 tr())永遠對不上,長一點(需要折行)的說明幾乎全部翻不到——這是使用者回報「圈圈i漏很多」翻譯的根因
## (2026-09-28)。改成覆寫 _get_tooltip():每次滑鼠停留才即時用 tr() 查目前語系的翻譯、再折行,永遠用未折行的原文
## 當查表 key,也天生就會跟著切換語系即時更新,不用額外處理語系變更事件。
func _get_tooltip(_at_position: Vector2) -> String:
	var translated: PackedStringArray = []
	for part in _tip_parts:
		translated.append(tr(part))
	return wrap_text("\n\n".join(translated), TIP_WIDTH)


## 把文字依「每行最多 width 個字」折行(已經有的換行保留)。中文沒有空白可以斷,所以直接按字數切。
static func wrap_text(text: String, width: int) -> String:
	var lines: PackedStringArray = []
	for paragraph in text.split("\n"):
		var current := ""
		for character in paragraph:
			current += character
			if current.length() >= width and character in [" ", ",", ",", "、", "。", ";", ";", ":", ":", ")", ")", "」", "!", "?", "!", "?"]:
				lines.append(current)
				current = ""
			elif current.length() >= width + 8:
				lines.append(current)
				current = ""
		lines.append(current)
	return "\n".join(lines)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var center := Vector2(SIZE, SIZE) * 0.5
	# 說明圖示是次要資訊:平時用次要文字色,滑過去用一般文字色(強調色留給選取與焦點,配色組的強調色可能很淡,當圖示會看不見)
	var color := get_theme_color("font_color", "Label") if _hover else ManagerUi.muted_color(self)
	draw_arc(center, SIZE * 0.5 - 1.5, 0.0, TAU, 32, color, 1.6, true)
	# 「i」:一個點 + 一小豎
	draw_circle(center + Vector2(0, -3.6), 1.3, color)
	draw_line(center + Vector2(0, -1.0), center + Vector2(0, 4.2), color, 1.8, true)
