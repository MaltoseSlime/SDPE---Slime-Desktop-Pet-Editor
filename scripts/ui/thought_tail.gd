class_name ThoughtTail
extends Control
## 思考泡泡的「尾巴」:從泡泡邊緣往桌寵頭部排幾顆由大到小的圓泡泡(oO),像漫畫裡角色在想事情。
## 純向量繪製(圓 + 框線),配色與泡泡本體一致;尺寸與間距跟著介面縮放率。由 DialogueBubble 擁有、UiManager 排版時定位(place)。

const DOT_COUNT := 3
## 三顆的半徑(縮放前,像素),由靠近泡泡的大顆到靠近桌寵的小顆。
const RADII: Array[float] = [7.0, 5.0, 3.0]
const GAP := 3.0

var _fill := Color.WHITE
var _line := Color.BLACK
var _line_width := 2.0
var _factor := 1.0
## 每顆圓心(自己的區域座標)與半徑,place() 算好。
var _dots: Array[Vector3] = []


func setup(fill: Color, line: Color, line_width: float, factor: float) -> void:
	_fill = fill
	_line = line
	_line_width = maxf(line_width, 1.0)
	_factor = factor
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1


## 總高度(縮放後):三顆圓直徑加間距。排版時桌寵與泡泡之間要留這麼多空間。
static func total_height(factor: float) -> float:
	var total := 0.0
	for radius in RADII:
		total += radius * 2.0 + GAP
	return total * factor


## 把尾巴接在 bubble_rect(全域)靠桌寵那一側,朝 target(全域座標,通常是桌寵頭部)排開。
## bubble_below = true 表示泡泡在桌寵下方(尾巴往上長)。
func place(bubble_rect: Rect2, target: Vector2, bubble_below: bool) -> void:
	_dots.clear()
	var start_y := bubble_rect.position.y if bubble_below else bubble_rect.end.y
	# 起點在泡泡邊緣上,水平位置靠近桌寵的 x(夾在泡泡寬度內,留圓角的餘地)。
	var start_x := clampf(target.x, bubble_rect.position.x + 24.0 * _factor, bubble_rect.end.x - 24.0 * _factor)
	var direction := -1.0 if bubble_below else 1.0
	var cursor := Vector2(start_x, start_y)
	var lowest := cursor
	var highest := cursor
	for i in DOT_COUNT:
		var radius := RADII[i] * _factor
		cursor.y += direction * (radius + GAP * _factor * 0.5)
		# 越往下越朝桌寵的水平位置靠攏,形成一串斜著的泡泡。
		cursor.x = lerpf(cursor.x, target.x, 0.35)
		_dots.append(Vector3(cursor.x, cursor.y, radius))
		cursor.y += direction * (radius + GAP * _factor * 0.5)
		lowest.y = maxf(lowest.y, cursor.y)
		highest.y = minf(highest.y, cursor.y)
	var xs := _dots.map(func(dot: Vector3) -> float: return dot.x)
	var left := minf(minf(xs.min(), start_x), target.x) - 12.0 * _factor
	var right := maxf(maxf(xs.max(), start_x), target.x) + 12.0 * _factor
	var top := minf(start_y, cursor.y) - 6.0
	var bottom := maxf(start_y, cursor.y) + 6.0
	global_position = Vector2(left, top)
	size = Vector2(right - left, bottom - top)
	queue_redraw()


## 尾巴實際佔的全域矩形(穿透形狀用,讓泡泡尾巴也點得到不被裁掉)。
func global_rect() -> Rect2:
	return Rect2(global_position, size)


func _draw() -> void:
	for dot in _dots:
		var center := Vector2(dot.x, dot.y) - global_position
		draw_circle(center, dot.z, _fill)
		draw_arc(center, dot.z, 0.0, TAU, 20, _line, _line_width * _factor * 0.75, true)

