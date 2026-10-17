class_name PetUiStyle
extends Resource
## 個別桌寵的專屬介面風格(企劃書第三章「UI 配色、字體與縮放」):對話氣泡與 Status 面板共用。
## 顏色支援 Alpha;縮放只有固定 8 檔;字體是系統內建字型的名稱(見 UiFonts)。

const SCALE_STEPS: Array[int] = [25, 50, 75, 100, 125, 150, 175, 200]

@export var background := Color("2B2B3AAA")
@export var border := Color("FFD166")
@export var text := Color("FFFFFF")
@export var option := Color("EF476F")
@export var border_width := 2
@export var corner_radius := 8
## 介面縮放百分比,必須是 SCALE_STEPS 其中一檔(不是的話取最接近的)。
@export var ui_scale := 100
@export var default_font := "黑體"
## 字級(只影響文字大小,不像 ui_scale 連框體、邊框、間距一起放大),百分比(100 = 字級 16)。
## 以前只能是 SCALE_STEPS 其中一檔;2026-10-17 起桌寵管理改成直接填字級數字(見 font_size/set_font_size),可以是兩檔之間的值。
@export var font_scale := 100.0
## 有選項的對話最多等使用者這麼久(秒);逾時視為沒有選擇。
@export var option_wait_seconds := 60.0
## 思考泡泡(對話積木的 BUBBLE = thought):和對話框長得像、配色獨立設定,預設是比較淡的淺色雲朵感。
@export var thought_background := Color("F3F5FFDD")
@export var thought_border := Color("9AA6D0")
@export var thought_text := Color("30344A")
@export var thought_option := Color("7C8BC9")


const MAX_BORDER_WIDTH := 8
## 桌寵管理「字級」數字的範圍(= 舊的 25%~200%)。
const MIN_FONT_SIZE := 4
const MAX_FONT_SIZE := 32
const MAX_CORNER_RADIUS := 32
const MIN_OPTION_WAIT := 5.0
const MAX_OPTION_WAIT := 600.0


## 泡泡種類對應的四色:thought = true 用思考泡泡的配色。回傳 {background, border, text, option}。
func palette(thought: bool) -> Dictionary:
	if thought:
		return {"background": thought_background, "border": thought_border, "text": thought_text, "option": thought_option}
	return {"background": background, "border": border, "text": text, "option": option}


## 縮放倍率(1.0 = 100%)。
func scale_factor() -> float:
	return nearest_scale_step(ui_scale) / 100.0


## 字級倍率(1.0 = 100%),只給文字大小用。
func font_scale_factor() -> float:
	return clamp_font_scale(font_scale) / 100.0


## 字級數字(縮放前、沒有字體校正;100% = UiStyleKit.BASE_FONT_SIZE)。
func font_size() -> int:
	return roundi(clamp_font_scale(font_scale) * UiStyleKit.BASE_FONT_SIZE / 100.0)


func set_font_size(size: int) -> void:
	font_scale = clampi(size, MIN_FONT_SIZE, MAX_FONT_SIZE) * 100.0 / UiStyleKit.BASE_FONT_SIZE


## 字級百分比夾在合法範圍(25%~200%,不必是 SCALE_STEPS 其中一檔)。
static func clamp_font_scale(value: float) -> float:
	return clampf(value, float(SCALE_STEPS[0]), float(SCALE_STEPS[-1]))


## 文字實際大小要乘的總倍率:介面縮放 × 字級 × 這個字體自己的視覺大小校正(見 UiFonts.size_correction,
## 例如像素體 Silver 套用後看起來比其他字體小很多,私底下多放大一點,不需要使用者自己調)。
func text_scale_factor() -> float:
	return scale_factor() * font_scale_factor() * UiFonts.size_correction(default_font)


## 最接近的合法縮放檔位(25~200%,共 8 檔)。
static func nearest_scale_step(value: int) -> int:
	var best := SCALE_STEPS[3]
	for step in SCALE_STEPS:
		if absi(step - value) < absi(best - value):
			best = step
	return best


## 還原成內建預設風格(管理視窗的「還原預設」用)。
func reset_to_defaults() -> void:
	var fresh := PetUiStyle.new()
	background = fresh.background
	border = fresh.border
	text = fresh.text
	option = fresh.option
	border_width = fresh.border_width
	corner_radius = fresh.corner_radius
	ui_scale = fresh.ui_scale
	default_font = fresh.default_font
	font_scale = fresh.font_scale
	option_wait_seconds = fresh.option_wait_seconds
	thought_background = fresh.thought_background
	thought_border = fresh.thought_border
	thought_text = fresh.thought_text
	thought_option = fresh.thought_option
