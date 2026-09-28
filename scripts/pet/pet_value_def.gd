class_name PetValueDef
extends Resource
## 數值屬性定義(企劃書第六章「數值屬性定義與自訂圖示」+「Status 菜單白名單」):
## 內部名稱、顯示名稱、預設/上下限、步進、小圖示,以及在 Status 面板的呈現方式。
## 所有數值預設對 Status 面板隱藏(避免洩露中介變數或彩蛋),創作者必須主動勾選 show_in_status。

enum DisplayMode { TEXT, BAR, GAUGE }

## 內部名稱(積木、對話插值、存檔都用它)。
@export var key := ""
## 顯示名稱(Status 面板用);空白就顯示 key。
@export var display_name := ""
## true = 全域數值(所有桌寵共享),false = 局部數值(屬於各桌寵)。
@export var is_global := false
@export var default_value := 0.0
## 上下限:設值/增減一律經過閘道器夾限。沒有上限就維持預設的極大值(Status 也就不顯示「/ 最大值」)。
@export var min_value := -1.0e9
@export var max_value := 1.0e9
## 步進量:>= 1 且為整數時顯示成整數,否則顯示一位小數。
@export var step := 1.0
@export var icon: Texture2D
## 圖示來源路徑(res:// 內建資源,或使用者選的 PNG 等圖檔),存檔時只記路徑;icon 由 set_icon_path() 載入。
@export var icon_path := ""
@export_group("Status 面板")
@export var show_in_status := false
## 排序權重:越小越上面。
@export var sort_weight := 0
@export var display_mode := DisplayMode.TEXT
## 量表(GAUGE)模式:true = 數值高是不好的(疲勞、壓力),漸層顏色反過來(預設 低=紅、高=綠)。
@export var gauge_reverse := false
@export var prefix := ""
@export var suffix := ""
## 這個數值定義是誰帶進來的(同 PetStateLens.source):空字串 = 使用者自己建的;"personality:<性格 id>" = 套用性格時加入的。
@export var source := ""
@export var source_hash := 0


const MAX_ICON_SIZE := 256


## 載入圖示。空路徑 = 清除圖示。圖檔壞掉、太大或不存在就回傳 false 並保持原本的圖示(不拋錯、不中斷)。
func set_icon_path(path: String) -> bool:
	if path == "":
		icon_path = ""
		icon = null
		return true
	var texture: Texture2D = null
	if path.begins_with("res://"):
		texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
	else:
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty() and image.get_width() <= MAX_ICON_SIZE and image.get_height() <= MAX_ICON_SIZE:
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		return false
	icon_path = path
	icon = texture
	return true


func label() -> String:
	return display_name if display_name != "" else key


func has_max() -> bool:
	return max_value < 1.0e8


## 上下限都有限才畫得出量表/進度條的範圍。
func has_finite_range() -> bool:
	return min_value > -1.0e8 and max_value < 1.0e8


func clamp_value(value: float) -> float:
	return clampf(value, min_value, max_value)


## 數字格式化:整數步進顯示成整數,否則一位小數。
func format_number(value: float) -> String:
	if is_equal_approx(step, roundf(step)) and step >= 1.0:
		return str(int(roundf(value)))
	return "%.1f" % value


## Status 面板的文字:前綴 + 數值 + 後綴,有上限時再加「/ 上限」。
func format_text(value: float) -> String:
	var text := prefix + format_number(value) + suffix
	if has_max():
		text += " / " + format_number(max_value) + suffix
	return text
