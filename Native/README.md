# Native flight kernels (GDExtension)

The flight computer's and sensors' hot loops in C++. GDScript pays ~0.5–1 µs for each step
of a tight numeric loop; these run one to two orders faster. Each kernel is the GDScript it
replaces with the same operations in the same order (and no fused multiply-add), so the
results are **bit-identical**: the GDScript stays as the fallback and the two can be swapped
at any time.

| Kernel (`FlightKernels`) | Replaces | GDScript → C++ (RX-93) |
|---|---|---|
| `allocator_solve`, `allocator_wrench_of` | `ConeProjectedAllocator._solve`, `_wrench_of` | allocate + trim per tick: 1.61 → 0.09 ms |
| `allocator_trim` | the FISTA loop in `ConeProjectedAllocator.trim` | (in the line above) |
| `track_predict`, `track_update` | `SensorTrack._predict`, `_update_gdscript` | per measurement with estimates: 0.125 → 0.014 ms |
| `capability_lookup` | the blend in `ForceCapabilityMap.lookup` | per call: 5.5 → 1.9 µs |

`FlightNative.kernels()` hands out the kernels, or null to run the GDScript: off with the
project setting `physics/flight/native_kernels` or, for one run, `FLIGHT_NATIVE=0` (A/B
timing). A platform without a built library (see `addons/flight_kernels/flight_kernels.gdextension`)
runs the GDScript.

## Building

The engine here is a `precision=double` build, so the extension must be too, against the
API dumped from that build (`api/extension_api.json`; godot-cpp's bundled one is single
precision). godot-cpp is a submodule (branch 4.5: extensions are forward compatible, and
4.6 / 4.7 have no branch).

```sh
git submodule update --init Native/godot-cpp
~/pkgs/scons-venv/bin/scons -C Native precision=double target=template_release \
    custom_api_file=api/extension_api.json -j6
```

Writes `addons/flight_kernels/bin/libflight_kernels.linux.template_release.double.x86_64.so`
(the first build compiles godot-cpp, ~3 min). The release build serves the editor too.
After rebuilding the engine, dump the API again (`godot-double --headless --dump-extension-api`
in `Native/api/`) and rebuild.

**Windows:** build there with the same command (MSVC needs no extra flag), or cross-compile
with `platform=windows use_mingw=yes` (needs mingw-w64). The `.gdextension` already lists the
`.dll`.

## Changing a kernel

Change the GDScript and the C++ together, keeping the order of operations, and check them
against each other: the old/new harness pattern in `Docs/Performance/frame_budget.md` (same
inputs through both, compared exactly). A float read from a `PackedFloat32Array` widens to
double and one stored into it rounds back to float, as in GDScript; `MAX` / `CLAMP` are
the engine's (`maxf` / `clampf`).
