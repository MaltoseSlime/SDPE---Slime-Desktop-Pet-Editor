class_name GamePieceColors
extends RefCounted
## 小遊戲棋盤的棋子配色(2026-10-18 使用者要求,全局設定「棋子配色」):
## 系統配色(預設)= 回空陣列,棋盤照原本用強調色 / 文字色;
## 桌寵配色 = 桌寵用自己氣泡的外框色。兩隻太像時,第二隻換成牠的選項色,還是太像再換文字色;
## 使用者用強調色,跟桌寵太像就換文字色(還是太像,桌寵那邊換選項色)。

## RGB 距離小於這個就算「太像」(0~√3)。
const MIN_DISTANCE := 0.3


static func too_close(a: Color, b: Color) -> bool:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() < MIN_DISTANCE


static func _opaque(color: Color) -> Color:
	return Color(color, 1.0)


static func _style(pet: Node) -> PetUiStyle:
	return pet.ui_style if is_instance_valid(pet) and pet.get("ui_style") is PetUiStyle else PetUiStyle.new()


## 桌寵對桌寵:回傳 [a 的顏色, b 的顏色];系統配色回空陣列。
static func for_pets(a: Node, b: Node) -> Array:
	if AppSettings.piece_color_mode() != "pet":
		return []
	return pick_pair(_style(a), _style(b))


static func pick_pair(first: PetUiStyle, second: PetUiStyle) -> Array:
	var mine := _opaque(first.border)
	var choices: Array[Color] = [_opaque(second.border), _opaque(second.option), _opaque(second.text)]
	for candidate in choices:
		if not too_close(mine, candidate):
			return [mine, candidate]
	return [mine, choices[2]]


## 桌寵對使用者:回傳 [桌寵的顏色, 使用者的顏色];系統配色回空陣列。
static func for_user(pet: Node) -> Array:
	if AppSettings.piece_color_mode() != "pet":
		return []
	var colors: Dictionary = AppSettings.appearance()["colors"]
	return pick_user(_style(pet), colors["accent"], colors["text"])


static func pick_user(style: PetUiStyle, accent: Color, text: Color) -> Array:
	var pet_color := _opaque(style.border)
	for user_color: Color in [_opaque(accent), _opaque(text)]:
		if not too_close(pet_color, user_color):
			return [pet_color, user_color]
	return [_opaque(style.option), _opaque(accent)]
