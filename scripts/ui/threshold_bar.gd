class_name ThresholdBar
extends Control
## Status 面板的「條 + 門檻刻度」:一條 min~max 的槓,填到目前的值,並在幾個門檻的位置畫直線刻度(精力條標「累了/睡著」、心情條標「生氣/開心」)。
## 純向量繪製;顏色由呼叫端(依桌寵的介面風格)給。

var _min := 0.0
var _max := 100.0
var _value := 0.0
var _marks: Array[float] = []
var _fill := Color.WHITE
var _tick := Color.WHITE
var _factor := 1.0


func setup(min_value: float, max_value: float, value: float, marks: Array[float], fill: Color, tick: Color, factor: float) -> void:
	_min = min_value
	_max = maxf(max_value, min_value + 0.001)
	_value = clampf(value, _min, _max)
	_marks = marks
	_fill = fill
	_tick = tick
	_factor = factor
	custom_minimum_size.y = 10.0 * factor
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## 值在槓上的位置(0~1)。
func fraction(value: float) -> float:
	return clampf((value - _min) / (_max - _min), 0.0, 1.0)


func _draw() -> void:
	var height := size.y
	var radius := int(4 * _factor)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	background.set_corner_radius_all(radius)
	draw_style_box(background, Rect2(Vector2.ZERO, size))
	var fill_width := size.x * fraction(_value)
	if fill_width > 0.5:
		var fill := StyleBoxFlat.new()
		fill.bg_color = _fill
		fill.set_corner_radius_all(radius)
		draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(fill_width, height)))
	for mark in _marks:
		var x := size.x * fraction(mark)
		draw_line(Vector2(x, -1.0), Vector2(x, height + 1.0), _tick, maxf(2.0 * _factor, 1.5))
