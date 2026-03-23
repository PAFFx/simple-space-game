class_name CockpitRX0
extends Node3D

## Root script for the RX-0 cockpit.
## Exposes internal components so the parent vehicle scene can reference them
## without needing to know the cockpit's internal node structure.

@export var panoramic_screen: PanoramicScreen
