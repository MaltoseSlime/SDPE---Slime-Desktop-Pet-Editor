class_name DrawLayers
extends RefCounted
## 畫面圖層編號系列(CanvasItem.z_index)。桌面上所有東西的前後關係都靠這份表,新功能要放圖層先看這裡、在自己的區段內取號,
## 不要隨手設 z_index:
##
##   -1000 ~ -501   BACKDROP     背景物、家具(桌寵後面)
##    -500 ~ -101   AMBIENT     環境效果(螢火蟲、背景粒子)
##    -100 ~  -37   STILL       半身立繪:每隻一個「帶」(STILL_BAND_SIZE 個編號),依生成先後由後往前排;
##                              帶內:+0 本體後面的配件、+1 本體與一般配件、+2 最上層配件。所以立繪的任何部件
##                              都在所有一般桌寵後面,兩隻立繪互相重疊時也不會有一隻的配件跑到另一隻本體前面。
##          0        PET         一般桌寵(地面/飛行/漂浮…),同一層內用節點順序(點到的浮到最上面)
##    +100 ~ +499   PET_EFFECT  桌寵特效(飄愛心、殘影…)
##    +500 ~ +999   FOREGROUND  前景(桌寵前面的家具、前景粒子)
##   對話氣泡、Status 面板在獨立的 CanvasLayer(UiManager,layer 10),永遠在上面。

const BACKDROP_MIN := -1000
const AMBIENT_MIN := -500
const STILL_BASE := -100
const STILL_BAND_SIZE := 4
const MAX_STILL_BANDS := 16
const PET := 0
const PET_EFFECT_MIN := 100
const FOREGROUND_MIN := 500


## 第 index 隻半身立繪(0 起算,依生成先後)本體的 z_index。
static func still_z(index: int) -> int:
	return STILL_BASE + clampi(index, 0, MAX_STILL_BANDS - 1) * STILL_BAND_SIZE + 1
