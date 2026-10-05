class_name WrappedTooltipLabel
extends Label
## 2026-10-05 新增:一個只放圖示、滑鼠停上去才顯示完整說明的 Label。Godot 內建的 tooltip_text 不會自動換行,
## 長段說明會拉成一整條很寬的提示框,所以這裡改用自己的提示內容:限定寬度、自動換行(見 _make_custom_tooltip())。
## tooltip_text 要有值,Godot 才會去呼叫 _make_custom_tooltip();實際顯示的文字用 tooltip_text 的內容。


func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var body := Label.new()
	body.text = for_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(320, 0)
	panel.add_child(body)
	return panel
