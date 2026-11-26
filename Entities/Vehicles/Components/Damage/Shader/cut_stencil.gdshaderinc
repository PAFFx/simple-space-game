// Stencil writer for a cut part (a next pass on its damage material; HoleSet makes one shader per
// stencil value): the part's back faces seen through the cut mark the stencil. Those pixels are
// exactly the part's cross-section, whatever its shape; the cap (cut_cap.gdshaderinc) is drawn
// only there.

#include "res://Entities/Vehicles/Components/Damage/Shader/beam_hole.gdshaderinc"

void vertex() {
	v_part_pos = hole_part_pos(VERTEX);
	v_part_cam = hole_part_cam(MODELVIEW_MATRIX);
}

void fragment() {
	// A back face on the kept side, the camera on the removed side: the line of sight crossed the
	// cut to reach it.
	if (FRONT_FACING || cut_side == 0.0 || cut_field(v_part_pos) > 0.0 || cut_field(v_part_cam) <= 0.0) {
		discard;
	}
	ALBEDO = vec3(0.03);
	ROUGHNESS = 1.0;
}
