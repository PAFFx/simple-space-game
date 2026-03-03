extends Node

const WORLD := 1 << 0
const VEHICLE_EXT := 1 << 1
const VEHICLE_FP := 1 << 2
const COCKPIT := 1 << 3
const PILOT := 1 << 4
const FX := 1 << 5
const HUD_3D := 1 << 6

const DEBUG := 1 << 19

const MASK_THIRD_PERSION := WORLD | VEHICLE_EXT | FX
const MASK_FIRST_PERSON :=  WORLD | VEHICLE_FP | COCKPIT | PILOT | FX | HUD_3D
