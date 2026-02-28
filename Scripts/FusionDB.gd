extends Node

var repo: FusionRepository
var fusion: FusionService

func _ready() -> void:
	repo = FusionRepository.new()
	repo.load_all(
		"res://Scripts/JSON/CardsDB.json",
		"res://Scripts/JSON/generic_fusions.json",
		"res://Scripts/JSON/specific_fusions.json"
	)
	fusion = FusionService.new(repo, preload("res://Scenes/Card.tscn"))
