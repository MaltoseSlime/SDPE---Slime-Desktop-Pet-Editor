class_name PaintToolButton
extends Button
## 繪圖工具列的按鈕。畫筆、橡皮擦、吸色可以按右鍵綁到「畫布上的右鍵」:綁定中的按鈕外面畫一圈虛線框(一次只有一個)。

signal right_clicked

var bindable := false
var bound := false:
	set(value):
		bound = value
		queue_redraw()


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	if bindable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit()
		accept_event()


func _draw() -> void:
	if not bound:
		return
	var color := get_theme_color("font_color")
	var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		draw_dashed_line(corners[k], corners[(k + 1) % 4], color, 1.5, 4.0)
