#ifndef MAJORANA_NEON_H
#define MAJORANA_NEON_H
#ifdef __cplusplus
extern "C" {
#endif
void majorana_phase_shift_neon(float *re, float *im, const float *phi, int dim);
void compute_phase_angles_neon(const float *omega, float t, float *phi, int dim);
void apply_majorana_identity_neon(const float *er, const float *ei, const float *cr, const float *ci, float *outr, float *outi, int dim);
float majorana_purity_neon(const float *re, const float *im, int dim);
#ifdef __cplusplus
}
#endif
#endif
