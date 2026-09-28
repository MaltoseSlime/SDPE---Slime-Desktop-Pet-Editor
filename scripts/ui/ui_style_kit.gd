class_name UiStyleKit
extends RefCounted
## 對話氣泡與 Status 面板共用的程序化繪製工具(企劃書「輕量程序化渲染」):全部用 StyleBoxFlat 向量方塊,
## 不需要創作者提供切片圖檔;顏色、邊框粗細、圓角、字級依 PetUiStyle 與 UI 縮放率同步縮放。

const BASE_FONT_SIZE := 16


## 思考泡泡的圓角至少這麼大(圓潤一點,像想事情的雲朵)。
const THOUGHT_MIN_RADIUS := 16


## thought = true:思考泡泡,用 PetUiStyle 的 thought_* 配色,圓角至少 THOUGHT_MIN_RADIUS。
static func panel_style(style: PetUiStyle, factor: float, thought := false) -> StyleBoxFlat:
	var colors := style.palette(thought)
	var box := StyleBoxFlat.new()
	box.bg_color = colors["background"]
	box.border_color = colors["border"]
	box.set_border_width_all(maxi(int(style.border_width * factor), 1))
	box.set_corner_radius_all(int((maxi(style.corner_radius, THOUGHT_MIN_RADIUS) if thought else style.corner_radius) * factor))
	box.set_content_margin_all(10.0 * factor)
	# 名字標籤跨在上邊框上,上方多留一點空間讓標籤不蓋到第一行字。
	box.content_margin_top = 16.0 * factor
	return box


## 嵌在面板左上角邊框上的名字標籤;呼叫端要把它設成 top_level 再自己擺位置。
static func name_tag(text: String, font: Font, style: PetUiStyle, factor: float, thought := false) -> PanelContainer:
	var border_color: Color = style.palette(thought)["border"]
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = border_color
	box.set_corner_radius_all(int(6 * factor))
	box.content_margin_left = 8.0 * factor
	box.content_margin_right = 8.0 * factor
	box.content_margin_top = 1.0 * factor
	box.content_margin_bottom = 1.0 * factor
	tag.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", int((BASE_FONT_SIZE - 3) * style.text_scale_factor()))
	# 標籤底色是框線色,文字要選跟它反差夠大的顏色,不能直接用文字色(兩個可能很接近)。
	label.add_theme_color_override("font_color", Color.BLACK if border_color.get_luminance() > 0.5 else Color.WHITE)
	tag.add_child(label)
	return tag


static func option_button(text: String, font: Font, style: PetUiStyle, factor: float, thought := false) -> Button:
	var colors := style.palette(thought)
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	# 一行一個選項,太長的文字自動換行(全寬、不撐開氣泡)。
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", int(BASE_FONT_SIZE * style.text_scale_factor()))
	var text_color: Color = colors["text"]
	var option_color: Color = colors["option"]
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = option_color.lightened(0.2) if state != "normal" else option_color
		box.set_corner_radius_all(int(style.corner_radius * factor * 0.6))
		box.set_content_margin_all(6.0 * factor)
		button.add_theme_stylebox_override(state, box)
	return button


## 把名字標籤貼在面板左上角邊框上(標籤跨在邊框線上)。
static func place_tag(tag: PanelContainer, panel: Control, factor: float) -> void:
	tag.reset_size()
	tag.global_position = panel.global_position + Vector2(10.0 * factor, -tag.size.y * 0.5)
