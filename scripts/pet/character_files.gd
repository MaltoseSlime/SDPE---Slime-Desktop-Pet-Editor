class_name CharacterFiles
extends RefCounted
## 「一個角色一個資料夾」:角色庫(user://sprites/)裡的角色,設定、狀態、導入的積木檔都存在自己的資料夾底下的 character/:
##   <角色資料夾>/character/profile.json  角色設定(數值定義、狀態鏡、介面風格、性格副本、關鍵詞庫…),原本是 user://profiles/<辨識代號>.json
##   <角色資料夾>/character/state.json    執行狀態(數值目前的值、記憶、戰績),原本是 user://profiles/<辨識代號>_state.json
##   <角色資料夾>/character/logic.json    導入過的積木檔,原本是 user://logic/<辨識代號>.logic.json
## 這樣整個資料夾就是角色的完整打包(之後 .pet 就是把它壓成一個檔),改名、複製、刪除也不用另外找設定檔。
## 只有「角色庫裡的素材包」用這個位置;範例 Mal / Buddy、半身立繪、庫外的素材包資料夾(從別處直接放上桌面)沿用舊位置,不會在別人的資料夾裡亂寫檔案。
## 全域數值(_global.json)不屬於任何角色,還在 user://profiles/。

const SUBDIR := "character"
const PROFILE_NAME := "profile.json"
const STATE_NAME := "state.json"
const LOGIC_NAME := "logic.json"
## 搬家後舊檔留一份在這裡(不直接刪),使用者確認沒問題後可以自己清掉。
const MIGRATED_DIR := "user://profiles/_migrated"


static func profile_in(folder: String) -> String:
	return folder.path_join(SUBDIR).path_join(PROFILE_NAME)


static func state_in(folder: String) -> String:
	return folder.path_join(SUBDIR).path_join(STATE_NAME)


static func logic_in(folder: String) -> String:
	return folder.path_join(SUBDIR).path_join(LOGIC_NAME)


## 這個資料夾是不是角色庫管理的(在 sprite 根資料夾底下且存在)。
static func is_managed(folder: String) -> bool:
	var normalized := folder.replace("\\", "/").trim_suffix("/")
	return normalized != "" and SpriteLibrary.is_inside(normalized) and DirAccess.dir_exists_absolute(normalized)


## 這隻桌寵的角色資料夾:用角色庫的素材包生成的(名單 meta 的 kind = pack 且路徑在角色庫裡)回資料夾,其他回空字串。
static func folder_of(pet: Node) -> String:
	if pet == null or not pet.has_meta("roster"):
		return ""
	var entry: Variant = pet.get_meta("roster")
	if entry is Dictionary and str(entry.get("kind", "")) == "pack":
		var path := str(entry.get("path", "")).replace("\\", "/").trim_suffix("/")
		if is_managed(path):
			return path
	return ""


## 舊位置的三個檔(依辨識代號):[設定, 狀態, 積木檔]。
static func legacy_paths(tag: String) -> Array[String]:
	var safe := tag.validate_filename()
	return ["user://profiles/%s.json" % safe, "user://profiles/%s_state.json" % safe, "user://logic/%s.logic.json" % safe]


## 把這個角色資料夾對應的舊檔搬進 character/。回傳 {moved: [搬了哪些檔名], conflicts: [新舊都有所以沒搬的檔名], errors: [失敗原因]}。
## 規則:舊檔存在、新檔不存在 → 複製過去(位元組驗證大小)成功後把舊檔移到 _migrated/;新檔已存在 → 不覆蓋、舊檔留在原地並回報;可以重複執行。
## 庫外的資料夾一律不動。
static func migrate_pack(folder: String) -> Dictionary:
	var report := {"moved": [], "conflicts": [], "errors": []}
	if not is_managed(folder):
		return report
	var legacy := legacy_paths(SpriteLibrary.tag_of(folder))
	var targets: Array[String] = [profile_in(folder), state_in(folder), logic_in(folder)]
	for i in legacy.size():
		var source := legacy[i]
		if not FileAccess.file_exists(source):
			continue
		if FileAccess.file_exists(targets[i]):
			report["conflicts"].append(targets[i].get_file())
			continue
		if DirAccess.make_dir_recursive_absolute(targets[i].get_base_dir()) != OK:
			report["errors"].append(TranslationServer.translate("無法建立資料夾:%s") % targets[i].get_base_dir())
			continue
		if DirAccess.copy_absolute(source, targets[i]) != OK or FileAccess.get_size(source) != FileAccess.get_size(targets[i]):
			report["errors"].append(TranslationServer.translate("複製失敗:%s") % source.get_file())
			if FileAccess.file_exists(targets[i]):
				DirAccess.remove_absolute(targets[i])
			continue
		_archive_legacy(source)
		report["moved"].append(targets[i].get_file())
	return report


## 整個角色庫的舊檔搬家(開機時跑一次;之後每次放上桌面前也會對那一個資料夾跑)。回傳合併的 {moved, conflicts, errors}(項目前面加上資料夾名)。
static func migrate_all() -> Dictionary:
	var total := {"moved": [], "conflicts": [], "errors": []}
	for folder in SpriteLibrary.list_packs():
		var report := migrate_pack(folder)
		for key: String in ["moved", "conflicts", "errors"]:
			for item in report[key]:
				(total[key] as Array).append("%s/%s" % [folder.get_file(), item])
	return total


## 舊檔搬進 _migrated/(同名已存在就加序號,不蓋掉之前留的)。
static func _archive_legacy(source: String) -> void:
	DirAccess.make_dir_recursive_absolute(MIGRATED_DIR)
	var target := "%s/%s" % [MIGRATED_DIR, source.get_file()]
	var counter := 2
	while FileAccess.file_exists(target):
		target = "%s/%s.%d" % [MIGRATED_DIR, source.get_file(), counter]
		counter += 1
	if DirAccess.rename_absolute(source, target) != OK:
		# 搬不動就留在原地(不能刪:使用者的資料);下次啟動會當成「新舊都有」回報。
		push_warning("舊設定檔無法搬到 %s,留在原地" % MIGRATED_DIR)
