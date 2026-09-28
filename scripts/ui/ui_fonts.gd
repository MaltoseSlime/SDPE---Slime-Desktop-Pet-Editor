class_name UiFonts
extends RefCounted
## 介面字型庫:四款字型名稱 → 字型。黑體、圓體、像素體 Sliver 用專案自帶的字型檔(assets/fonts/,創作者提供);標楷體用系統字型。
## 字型檔載入失敗或缺字時退回系統字型,再不行就是預設字型,字型缺漏不會拋錯、不會中斷(企劃書「字型毀損退回系統預設」原則)。
## 自訂上傳字型之後由素材匯入流程註冊進 register()。

const FONT_NAMES: Array[String] = ["黑體", "圓體", "標楷體", "Sliver", "俐方體"]
const SYSTEM_FONTS := {
	"黑體": ["Microsoft JhengHei", "Microsoft YaHei", "Noto Sans CJK TC", "PingFang TC"],
	"圓體": ["jf-openhuninn-2.0", "Microsoft JhengHei UI", "Microsoft JhengHei"],
	"標楷體": ["DFKai-SB", "BiauKai", "KaiTi", "標楷體"],
	"Sliver": [],
	"俐方體": [],
}

## 專案自帶的字型檔(字型名稱 → 路徑):黑體 = 源樣黑體(GenYoGothic TW)、圓體 = 粉圓體 jf-openhuninn 2.0、
## Sliver = 像素體 Silver、俐方體 = 像素體 Cubic-11(ACh-K,https://github.com/ACh-K/Cubic-11)。
const BUNDLED := {
	"黑體": "res://assets/fonts/GenYoGothic-R.ttc",
	"圓體": "res://assets/fonts/jf-openhuninn-2.0.ttf",
	"Sliver": "res://assets/fonts/Silver.ttf",
	"俐方體": "res://assets/fonts/Cubic.ttf",
}

## 依介面語系挑不同字型檔的管線(2026-09-28,先做管線,還沒有真的第二份字型檔可驗證):字型名稱 → {語系代碼 → 路徑}。
## 源樣黑體之後可能出日文版,屆時只要在這裡補一筆(例如 "黑體": {"ja": "res://assets/fonts/GenYoGothic-JP-R.ttc"}),
## 不用改 _make_font() 的邏輯。找不到對應語系的檔案,或檔案根本不存在(還沒放進來),就照舊退回 BUNDLED 的預設檔;
## 快取 key 因此要把語系併進去,不然切語系不會換字型(見 get_font 的 cache key)。
static var BUNDLED_BY_LOCALE: Dictionary = {}


## 目前介面語系該用哪個字型檔路徑;沒有語系專屬版本或檔案不存在就回傳 BUNDLED 的預設路徑(可能是空字串)。
static func _bundled_path(font_name: String) -> String:
	var by_locale: Dictionary = BUNDLED_BY_LOCALE.get(font_name, {})
	if not by_locale.is_empty():
		var locale := TranslationServer.get_locale()
		for code: String in [locale, locale.split("_")[0]]:
			var path := str(by_locale.get(code, ""))
			if path != "" and ResourceLoader.exists(path):
				return path
	return str(BUNDLED.get(font_name, ""))

## 有些字型套用後視覺上明顯比其他字體小(像素體 Sliver 就是),在同一個字級設定值下私底下多放大一點,
## 不需要使用者自己調高全域字級(那樣連行距、間距都會一起放大,看起來很怪)。這裡抓不到的字型 = 不校正(1.0)。
## 俐方體(Cubic-11)也是像素體,視覺上可能也偏小,但這裡沒放校正值——沒辦法用截圖確認實際大小該乘多少倍,
## 需要使用者實機看過後回報數字再補(不要憑猜的塞一個沒驗證過的倍率)。
const FONT_SIZE_CORRECTION := {
	"Sliver": 1.3,
}

static var _cache: Dictionary = {}


## 這個字體名稱的視覺大小校正倍率(1.0 = 不校正)。
static func size_correction(font_name: String) -> float:
	return float(FONT_SIZE_CORRECTION.get(font_name, 1.0))


## 取得字型;名稱空白或不認得就取預設名稱,還是不認得就給黑體。快取 key 併入目前介面語系,
## 這樣切語系(見 BUNDLED_BY_LOCALE)才會換到對應字型,不會一直沿用切換前快取住的舊字型。
static func get_font(font_name: String, fallback_name := "黑體") -> Font:
	var name := font_name if _cache.has(_cache_key(font_name)) or SYSTEM_FONTS.has(font_name) else fallback_name
	var key := _cache_key(name)
	if not _cache.has(key):
		_cache[key] = _make_font(name)
	return _cache[key]


static func _cache_key(font_name: String) -> String:
	return font_name if BUNDLED_BY_LOCALE.get(font_name, {}).is_empty() else "%s@%s" % [font_name, TranslationServer.get_locale()]


## 專案自帶的字型檔(有的話,依語系挑選見 _bundled_path)加上系統字型當缺字的後備;沒有字型檔就是純系統字型。
static func _make_font(key: String) -> Font:
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(SYSTEM_FONTS.get(key, SYSTEM_FONTS["黑體"]))
	var path := _bundled_path(key)
	if path != "" and ResourceLoader.exists(path):
		var loaded: Variant = load(path)
		if loaded is FontFile:
			var bundled := (loaded as FontFile).duplicate() as FontFile
			bundled.fallbacks = [system_font]
			return bundled
	return system_font


## 之後註冊自訂上傳字型(TTF/OTF 載入成功才呼叫)。
static func register(font_name: String, font: Font) -> void:
	_cache[font_name] = font
