class_name BuildProfile
extends RefCounted
## 這份程式跑在「開發專案」還是「發行版」:開發專案裡有測試用素材(範例桌寵 Mal / Buddy 用的 assets/sample_pets、半身立繪 Still A / B 的 assets/still),
## 發行版(tools/make_release_copy.ps1 做的副本)不會帶這些,召喚 / 測試選單就只剩「從角色庫放出角色」,開機沒有名單時也改放角色庫裡的預設活動桌寵。
## 判斷方式是看素材在不在(不是看 OS.has_feature),所以副本、匯出後的 exe 都會自動走發行版的路。

const SAMPLE_PET_PROBE := "res://assets/sample_pets/Mal/idle_r_0.png"
const STILL_PROBE := "res://assets/still/still_A/時間軸10_0001.png"

## 測試用:-1 = 照實際素材判斷、0 = 假裝沒有、1 = 假裝有。
static var override_samples := -1
static var override_stills := -1


static func has_sample_pets() -> bool:
	if override_samples >= 0:
		return override_samples == 1
	return ResourceLoader.exists(SAMPLE_PET_PROBE)


static func has_stills() -> bool:
	if override_stills >= 0:
		return override_stills == 1
	return ResourceLoader.exists(STILL_PROBE)
