@tool
extends Node

# Cambiá esta ruta si tu CardDB está en otro lado
const CARD_DB_SCRIPT = preload("res://Scripts/CardDB.gd")

func _ready() -> void:
	# Cambiá el nombre si querés otro archivo
	var out_path := "user://cards_export.csv"
	export_cards_to_csv(out_path)
	print("CSV exportado en: ", ProjectSettings.globalize_path(out_path))
	# Si lo corrés en el editor, podés hacer que se destruya solo:
	if Engine.is_editor_hint():
		queue_free()


func export_cards_to_csv(path: String) -> void:
	var cards: Dictionary = CARD_DB_SCRIPT.CARDS

	# Definimos las columnas que queremos en el CSV
	# (mismas propiedades que en tu DB)
	var columns := [
		"card_id",
		"card_type",
		"card_name",
		"attribute",
		"level",
		"atk",
		"def",
		"type",
		"guardian_star",
		"description",
		"effects",
		"tags",
		"passcode"
	]

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo abrir el archivo para escribir: %s" % path)
		return

	# Escribimos la fila de encabezados
	file.store_line(_csv_join(columns))

	# Recorremos las cartas ordenadas por card_id
	var keys := cards.keys()
	keys.sort()

	for key in keys:
		var card: Dictionary = cards[key]
		var row: Array = []

		for col in columns:
			var value = card.get(col, null)

			# Arrays y diccionarios los pasamos a JSON
			if value is Array or value is Dictionary:
				value = JSON.stringify(value)
			elif value == null:
				value = ""

			row.append(_csv_escape(str(value)))

		file.store_line(_csv_join(row))

	file.close()


func _csv_escape(text: String) -> String:
	# Escapar comillas dobles duplicándolas
	var escaped := text.replace("\"", "\"\"")
	# Envolver en comillas para evitar problemas con comas
	return "\"" + escaped + "\""

func _csv_join(fields: Array) -> String:
	return ",".join(fields)
