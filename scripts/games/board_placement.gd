class_name BoardPlacement
extends RefCounted
## 小遊戲棋盤/記分板/塔羅選牌這類可拖曳面板的「上次拖到哪裡」(2026-10-11 使用者要求:使用者拖到哪,下次就在
## 同一個位置生成)。面板物件每一局都是新的,自己記的 _fraction 活不過 queue_free(),所以存進
## user://settings.cfg 的 [boards],一種面板一個鍵(記分板、各種棋盤分開記,可以各放螢幕不同角落)。
## 存的是「在可拖曳範圍(螢幕)裡的比例位置」,跟各面板的 _fraction 同一個意思,換解析度不會跑出畫面。
## 右鍵選單「行動區重設」(面板的 recall())會連存檔一起忘掉,回到預設位置。

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "boards"


## 沒記過回 null(面板照自己的預設位置擺)。
static func load_fraction(kind: String) -> Variant:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK or not config.has_section_key(SECTION, kind + "_x") or not config.has_section_key(SECTION, kind + "_y"):
		return null
	return Vector2(clampf(float(config.get_value(SECTION, kind + "_x", 0.5)), 0.0, 1.0), clampf(float(config.get_value(SECTION, kind + "_y", 0.5)), 0.0, 1.0))


static func save_fraction(kind: String, fraction: Vector2) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SECTION, kind + "_x", fraction.x)
	config.set_value(SECTION, kind + "_y", fraction.y)
	config.save(SETTINGS_PATH)


## 全部忘掉(行動區重設:就算當下沒有任何面板開著,下次生成也回到預設位置)。
static func forget_all() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK or not config.has_section(SECTION):
		return
	config.erase_section(SECTION)
	config.save(SETTINGS_PATH)


static func forget(kind: String) -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK or not config.has_section(SECTION):
		return
	for key: String in [kind + "_x", kind + "_y"]:
		if config.has_section_key(SECTION, key):
			config.erase_section_key(SECTION, key)
	config.save(SETTINGS_PATH)
