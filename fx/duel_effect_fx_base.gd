extends Node
class_name DuelEffectFxBase

signal finished

var effect_context: Dictionary = {}


func setup_effect_fx(ctx: Dictionary) -> void:
	effect_context = ctx.duplicate(true)


func play_effect_fx() -> void:
	push_warning(
		"DuelEffectFxBase.play_effect_fx() debe ser sobrescrito."
	)

	finished.emit()


func finish_effect_fx() -> void:
	finished.emit()
