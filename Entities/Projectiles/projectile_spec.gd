class_name ProjectileSpec
extends Resource

## What a weapon fires: how the shot flies, what it does on a hit and how it looks.
## Nothing is hit-scan. A BEAM is a straight line of condensed Minovsky particles: the
## barrel pours it out for `emit_time`, the whole line following the barrel, its front
## travelling at `speed` (fast, but dodgeable from far enough). Let go, it flies on, its
## front dissipating at its range, leaving a short wake. Bullets and missiles are bolts.

enum Kind { BEAM, BULLET, MISSILE }

@export var kind := Kind.BEAM
## Speed off the muzzle, m/s, on top of the shooter's own velocity.
@export var speed: float = 4000.0
## Rocket burn after launch: acceleration m/s² for burn_time s (missiles).
@export var acceleration: float = 0.0
@export var burn_time: float = 0.0
## The shot fades out (a missile self-destructs) after this long, s.
@export var lifetime: float = 2.0
@export var damage: float = 100.0
## Missiles: burst when passing this close to something, hurting everything within
## blast_radius (full damage at the centre, none at the edge). 0 = contact only.
@export var fuse_radius: float = 0.0
@export var blast_radius: float = 0.0
## Seconds the barrel glows before the shot leaves: the dodge cue, seen from afar.
## The trigger has to be held through it (0 = fires on the press).
@export var spool_time: float = 0.0
## BEAM: seconds the beam keeps leaving the barrel (its length: speed × emit_time).
@export var emit_time: float = 0.0

@export_group("Look")
@export var color := Color(1.0, 0.16, 0.12)
## Radius of the bolt's glowing core, m.
@export var width: float = 0.9
## Length of the bright bolt at the head, m (bolts).
@export var bolt_length: float = 60.0
## How long the wake keeps glowing after the shot has passed, s.
@export var trail_time: float = 0.55
## Brightness (HDR): the core reaches this, so glow blooms around it.
@export var intensity: float = 9.0
## How strongly the shot lights the cockpit and things near it (0 = not at all).
@export var glow: float = 1.0
## Muzzle flash and impact size, m.
@export var flash_size: float = 9.0
@export var impact_size: float = 16.0

@export_group("Sound")
## Played on the muzzle as the shot leaves (the cockpit's simulated outside sound).
@export var fire_sound: AudioStream
@export var fire_volume_db: float = 0.0
## Within this distance the fire sound plays at full volume; it falls off past it, m.
@export var sound_unit_size: float = 150.0
## Past this the fire sound isn't heard at all, m.
@export var sound_max_distance: float = 2000.0


## Distance flown t seconds after launch, relative to the shooter's frame at launch.
func distance_at(t: float) -> float:
	var tb := minf(t, burn_time)
	return speed * t + 0.5 * acceleration * tb * tb + acceleration * burn_time * maxf(t - burn_time, 0.0)


## Farthest the shot gets before it fades.
func get_range() -> float:
	return distance_at(lifetime)
