class_name BeamRifle
extends MsEquipment

## Beam rifle. "Active" = raised to the ready position. Firing comes later.


func get_muzzle() -> Marker3D:
	return get_node("Muzzle") as Marker3D
