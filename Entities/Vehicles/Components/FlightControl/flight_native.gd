class_name FlightNative
extends RefCounted

## The C++ flight kernels (FlightKernels, from addons/flight_kernels; source in Native/), or
## null to run the GDScript they replace. Each kernel gives the same bits as its GDScript,
## so the two are interchangeable; native is just faster (allocator, trim, sensor track,
## capability lookup).
##
## Off with the project setting physics/flight/native_kernels, or for one run with the
## environment variable FLIGHT_NATIVE=0 (A/B timing). Without a built library for the
## platform (see the .gdextension) the GDScript runs.

static var _kernels: Object
static var _checked := false


static func kernels() -> Object:
	if not _checked:
		_checked = true
		if ProjectSettings.get_setting("physics/flight/native_kernels", true) \
				and OS.get_environment("FLIGHT_NATIVE") != "0" and ClassDB.class_exists(&"FlightKernels"):
			_kernels = ClassDB.instantiate(&"FlightKernels")
	return _kernels
