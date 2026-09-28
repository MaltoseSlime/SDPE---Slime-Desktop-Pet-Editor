class_name GaugeBar
extends Control
## 心情量表:一條漸層色的槓,加上一個三角形標示目前數值落在範圍的哪裡。
## 預設數值低 → 高是 紅 → 黃 → 綠(心情、好感度);reverse = 數值高是不好的(疲勞、壓力),顏色反過來。
## 純程序繪製,不需要任何圖檔;Status 面板的「量表」顯示模式使用(見 PetValueDef.DisplayMode.GAUGE)。

const LOW_COLOR := Color("e0605a")
const MID_COLOR := Color("e8c95a")
const HIGH_COLOR := Color("5ac08a")
const STEPS := 40

var _min := 0.0
var _max := 1.0
var _value := 0.0
var _unit := 1.0
var _marker_color := Color.WHITE
var _gradient := Gradient.new()


func setup(min_value: float, max_value: float, value: float, reverse: bool, unit: float, marker_color: Color) -> void:
	_min = min_value
	_max = maxf(max_value, min_value + 0.0001)
	_value = value
	_unit = unit
	_marker_color = marker_color
	var low := HIGH_COLOR if reverse else LOW_COLOR
	var high := LOW_COLOR if reverse else HIGH_COLOR
	_gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_gradient.colors = PackedColorArray([low, MID_COLOR, high])
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, _bar_height() + _triangle_height() + 3.0 * _unit)


func _bar_height() -> float:
	return 10.0 * _unit


func _triangle_height() -> float:
	return 9.0 * _unit


## 目前數值在範圍裡的位置 0~1。
func ratio() -> float:
	return clampf((_value - _min) / (_max - _min), 0.0, 1.0)


func _draw() -> void:
	var width := size.x
	var bar_height := _bar_height()
	for i in STEPS:
		var left := width * float(i) / STEPS
		var right := width * float(i + 1) / STEPS
		draw_rect(Rect2(left, 0.0, right - left + 1.0, bar_height), _gradient.sample((float(i) + 0.5) / STEPS))
	draw_rect(Rect2(0.0, 0.0, width, bar_height), Color(0.0, 0.0, 0.0, 0.5), false, 1.0)
	# 三角形標記:尖端朝上,貼在槓的下方;左右不超出槓的範圍。
	var half := _triangle_height() * 0.7
	var x := clampf(width * ratio(), half, maxf(width - half, half))
	var top := bar_height + 1.0
	var points := PackedVector2Array([Vector2(x, top), Vector2(x - half, top + _triangle_height()), Vector2(x + half, top + _triangle_height())])
	draw_colored_polygon(points, _marker_color)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), Color(0.0, 0.0, 0.0, 0.7), 1.0)
