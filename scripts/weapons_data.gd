class_name WeaponsData
extends RefCounted
## Datos ajustables de armas y detector de metal.

const WEAPONS := {
	"pistol": {"name": "PISTOLA", "cd": 0.28, "pellets": 1, "spread": 0.0, "auto": false, "kick": 0.02, "dmg": 14.0, "start": 14, "max": 45, "box": 8},
	"shotgun": {"name": "ESCOPETA", "cd": 0.85, "pellets": 8, "spread": 0.12, "auto": false, "kick": 0.07, "dmg": 11.0, "start": 4, "max": 12, "box": 3},
	"rifle": {"name": "RIFLE", "cd": 0.09, "pellets": 1, "spread": 0.012, "auto": true, "kick": 0.012, "dmg": 7.0, "start": 28, "max": 90, "box": 18},
}

const DET := {"speed": 45.0, "range": 70.0, "cd": 4.0, "reveal": 7.0, "prox": 9.0, "pick": 1.8}
