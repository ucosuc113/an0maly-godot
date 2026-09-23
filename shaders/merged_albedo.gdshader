shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Superficies fusionadas por render_tuning.gd: materiales que solo diferian en
// el albedo. El color (ya lineal) viaja por vertice en CUSTOM0.

uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;

varying flat vec3 albedo_lin;

void vertex() {
	albedo_lin = CUSTOM0.rgb;
}

void fragment() {
	ALBEDO = albedo_lin;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
