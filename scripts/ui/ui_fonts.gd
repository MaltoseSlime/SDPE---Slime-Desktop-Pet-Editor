class_name UiFonts
extends RefCounted
## 介面字型庫:四款字型名稱 → 字型。黑體、圓體、像素體 Silver 用專案自帶的字型檔(assets/fonts/,創作者提供);標楷體用系統字型。
## 字型檔載入失敗或缺字時退回系統字型,再不行就是預設字型,字型缺漏不會拋錯、不會中斷(企劃書「字型毀損退回系統預設」原則)。
## 自訂上傳字型之後由素材匯入流程註冊進 register()。

const FONT_NAMES: Array[String] = ["黑體", "圓體", "標楷體", "Silver", "俐方體"]
## 改過名字的字體(舊名稱 → 現在的名稱):像素體 Silver 早期版本誤寫成「Sliver」(2026-10-14 更正),舊的桌寵設定、
## 全局設定、積木裡存的還是舊名稱,讀到時一律當成新名稱(見 canonical),不讓舊資料掉回預設字體。
const ALIASES := {"Sliver": "Silver"}
const SYSTEM_FONTS := {
	"黑體": ["Microsoft JhengHei", "Microsoft YaHei", "Noto Sans CJK TC", "PingFang TC"],
	"圓體": ["jf-openhuninn-2.0", "Microsoft JhengHei UI", "Microsoft JhengHei"],
	"標楷體": ["DFKai-SB", "BiauKai", "KaiTi", "標楷體"],
	"Silver": [],
	"俐方體": [],
}

## 專案自帶的字型檔(字型名稱 → 路徑):黑體 = 源樣黑體(GenYoGothic TW)、圓體 = 粉圓體 jf-openhuninn 2.0、
## Silver = 像素體 Silver(Poppy Works)、俐方體 = 像素體 Cubic-11(ACh-K,https://github.com/ACh-K/Cubic-11)。
const BUNDLED := {
	"黑體": "res://assets/fonts/GenYoGothic-R.ttc",
	"圓體": "res://assets/fonts/jf-openhuninn-2.0.ttf",
	"Silver": "res://assets/fonts/Silver.ttf",
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

## 有些字型套用後視覺上明顯比其他字體小(像素體 Silver 就是),在同一個字級設定值下私底下多放大一點,
## 不需要使用者自己調高全域字級(那樣連行距、間距都會一起放大,看起來很怪)。這裡抓不到的字型 = 不校正(1.0)。
## 俐方體(Cubic-11)也是像素體,視覺上可能也偏小,但這裡沒放校正值——沒辦法用截圖確認實際大小該乘多少倍,
## 需要使用者實機看過後回報數字再補(不要憑猜的塞一個沒驗證過的倍率)。
const FONT_SIZE_CORRECTION := {
	"Silver": 1.6,   # 2026-10-14 使用者回報 1.3 還是偏小。實測同字級下 Silver 的中文字寬只有其他字體的 62.5%(16 級 = 10px),1.6 倍剛好等大
}

## 行距校正(字級的倍數,負的 = 行與行靠近一點):有些字型本身上下留白很多(Silver 就是),多行文字看起來很鬆。
## 用法見 line_spacing():對話氣泡、聊天室、編輯器介面的多行文字都套。這裡沒列的字型 = 不校正。
const LINE_SPACING_RATIO := {
	"Silver": -0.4,   # 實測行高是字級的 1.44 倍,但字只佔字級的 62.5%;放大 1.6 倍後行高變成別的字體的 1.6 倍,扣掉 0.4 個字級大約回到一樣
}

## 缺字時先找的另一款自帶字型(再缺才退回系統字型):Silver 缺少十幾個中文字(碟牠拚睏…),
## 用同為像素體的俐方體補,不會突然冒出一個黑體字(2026-10-14 使用者要求;字級跟 Silver 相同,補上的字會偏大一些)。
const FALLBACK_FONT := {
	"Silver": "俐方體",
}

static var _cache: Dictionary = {}


## 舊名稱換成現在的名稱(見 ALIASES);其他名稱原樣回傳。
static func canonical(font_name: String) -> String:
	return str(ALIASES.get(font_name, font_name))


## 這個字體名稱的視覺大小校正倍率(1.0 = 不校正)。
static func size_correction(font_name: String) -> float:
	return float(FONT_SIZE_CORRECTION.get(canonical(font_name), 1.0))


## 給「一整塊介面」用的字型(編輯器主題、對話氣泡):行高校正直接做在字型上(FontVariation 的上下間距),
## 這樣單行的按鈕、輸入框、頁籤、勾選項也會跟著變矮,不只是多行文字的行距(2026-10-14 使用者回報 Silver
## 在這些控制項裡上下多了不必要的空白)。間距是像素、不會跟著字級變,所以要給「主要字級」;沒有行距校正的字型原樣回傳。
static func get_ui_font(font_name: String, font_size: int, fallback_name := "黑體") -> Font:
	var name := canonical(font_name)
	if not SYSTEM_FONTS.has(name) and not _cache.has(_cache_key(name)):
		name = fallback_name
	var total := line_spacing(name, font_size)
	if total == 0:
		return get_font(name)
	var key := "%s#%d" % [_cache_key(name), font_size]
	if not _ui_cache.has(key):
		var variation := FontVariation.new()
		variation.base_font = get_font(name)
		# 上面少扣一點、下面多扣一點:Silver 的留白主要在基線以下(下緣是字級的一半,字本身幾乎不往下伸)。
		variation.spacing_top = int(total * 0.45)
		variation.spacing_bottom = total - int(total * 0.45)
		_ui_cache[key] = variation
	return _ui_cache[key]


static var _ui_cache: Dictionary = {}


## 這個字體在這個字級下,行與行之間要額外加多少像素(負的 = 靠近;0 = 不校正)。給 Label 的 line_spacing、
## RichTextLabel 的 line_separation 用。
static func line_spacing(font_name: String, font_size: int) -> int:
	return roundi(font_size * float(LINE_SPACING_RATIO.get(canonical(font_name), 0.0)))


## 取得字型;名稱空白或不認得就取預設名稱,還是不認得就給黑體。快取 key 併入目前介面語系,
## 這樣切語系(見 BUNDLED_BY_LOCALE)才會換到對應字型,不會一直沿用切換前快取住的舊字型。
static func get_font(font_name: String, fallback_name := "黑體") -> Font:
	font_name = canonical(font_name)
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
			bundled.fallbacks = [get_font(FALLBACK_FONT[key])] if FALLBACK_FONT.has(key) else [system_font]
			return bundled
	return system_font


## 之後註冊自訂上傳字型(TTF/OTF 載入成功才呼叫)。
static func register(font_name: String, font: Font) -> void:
	_cache[font_name] = font
