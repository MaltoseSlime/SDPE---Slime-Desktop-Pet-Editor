class_name DialogueTicket
extends RefCounted
## 一句對話的「完成憑證」:直譯器送出對話請求時附上,對話介面在這句結束(點擊推進、選了選項、
## 自動跳下一句、被使用者互動中斷)時呼叫 finish()。只會生效一次;重複呼叫無效。

signal finished(choice: int)

var closed := false


## choice 是被點選的選項索引;沒有選項或被中斷時是 -1。
func finish(choice := -1) -> void:
	if closed:
		return
	closed = true
	finished.emit(choice)
