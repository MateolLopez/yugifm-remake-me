extends Node

const STORY_FLOW := {
	"ep_1_01": {
		"type": "timeline",
		"next": "duel_1"
	},
	"duel_1": {
		"type": "duel",
		"opponent": "kaiba",
		"next": "ep_1_02"
	},
	"ep_1_02": {
		"type": "timeline",
		"next": "duel_2"
	},
	"duel_2": {
		"type": "duel",
		"opponent": "joey",
		"next": "ep_2_01"
	},
	"ep_2_01": {
		"type": "timeline",
		"next": "duel_3"
	},
	"duel_3": {
		"type": "duel",
		"opponent": "???",
		"next": "ep_2_02"
	},
}

func get_node_def(key: String) -> Dictionary:
	return STORY_FLOW.get(key, {})

func exists(key: String) -> bool:
	return STORY_FLOW.has(key)

func is_timeline(key: String) -> bool:
	return exists(key) and STORY_FLOW[key].get("type","") == "timeline"

func is_duel(key: String) -> bool:
	return exists(key) and STORY_FLOW[key].get("type","") == "duel"

# ================= AYUDA MEMORIA: Cómo extender historia =================
# 1) Cada paso de la historia es un "nodo" en STORY_FLOW.
#    Tipos:
#      - "timeline": corre una timeline de Dialogic.
#      - "duel":     lanza un duelo (sin Dialogic).
#
# 2) Cuando termina una "timeline", Story mira STORY_FLOW[clave].next.
#    - Si es otro "timeline" → arranca esa timeline.
#    - Si es un "duel"       → setea GameState.current_opponent_id + rules y va a DuelLoader.
#
# 3) Cuando termina un "duel":
#    - Si gana: avanza al nodo definido en "next".
#    - Si pierde: NO avanza, se muestra el panel de derrota con “Reintentar / Título”.
#
# 4) Para agregar un episodio:
#    "ep_X_Y": {"type":"timeline","next":"duel_N"},
#    "duel_N": {"type":"duel","opponent":"<id>","next":"ep_X_Y+1"}
#
# 5) Si querés un final sin duelo, dejá "next" vacío o apuntando a otra timeline final.
#
# 6) La clave del nodo "timeline" DEBE coincidir con el nombre de la Timeline de Dialogic.
#    La clave "opponent" debe existir en OpponentDB.
# ========================================================================
