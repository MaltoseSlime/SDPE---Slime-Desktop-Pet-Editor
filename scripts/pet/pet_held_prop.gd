class_name PetHeldProp
extends Node2D
## 桌寵手上拿著的道具(可持有的道具被拾取後,見 Pet.held_prop):掛在 Pet 的視覺根節點底下,位置是素材包的「持有錨點」(pack.json 的 hold_anchor,沒設就用判定框旁邊的預設位置),
## 跟著角色縮放、爬牆旋轉走;左右鏡像時圖不跟著翻(免得字是反的)。有圖就畫圖,沒有圖用程式畫的色塊加名稱第一個字(和 PropItem 一樣,不附任何圖像素材)。

var _texture: Texture2D
var _label := ""
var _size := 40.0


func setup(prop_name: String, texture: Texture2D, size: float) -> void:
	_label = prop_name
	_texture = texture
	_size = size
	z_index = 6
	queue_redraw()


func _process(_delta: float) -> void:
	var parent := get_parent() as Node2D
	if parent != null:
		var sign_x := signf(parent.scale.x)
		if sign_x != 0.0 and not is_equal_approx(scale.x, sign_x):
			scale.x = sign_x


func _draw() -> void:
	if _texture != null:
		var texture_size := _texture.get_size()
		var factor := _size / maxf(maxf(texture_size.x, texture_size.y), 1.0)
		var draw_size := texture_size * factor
		draw_texture_rect(_texture, Rect2(-draw_size * 0.5, draw_size), false)
		return
	var hue := float(absi(_label.hash()) % 360) / 360.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color.from_hsv(hue, 0.45, 0.95)
	style.set_corner_radius_all(int(_size * 0.22))
	style.border_color = Color(0, 0, 0, 0.35)
	style.set_border_width_all(2)
	draw_style_box(style, Rect2(-Vector2(_size, _size) * 0.5, Vector2(_size, _size)))
	var font := UiFonts.get_font("黑體")
	var letter := _label.left(1)
	var font_size := int(_size * 0.55)
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2(-text_size.x * 0.5, text_size.y * 0.3), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.1, 0.1, 0.12))
