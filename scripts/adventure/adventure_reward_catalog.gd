extends Resource
class_name AdventureRewardCatalog

## Explicit export-safe reward pool. Add new reward resources here so Godot can
## discover and include them as direct dependencies during export.
@export_category("Reward Pools")
@export var cards: Array[CardData] = []
@export var equipment: Array[EquipmentData] = []
@export var consumables: Array[ConsumableData] = []
