package cch

import "errors"

var (
	ErrLifeViolation = errors.New(
		"life continuity violation",
	)

	ErrSupervisionViolation = errors.New(
		"supervision violation",
	)

	ErrAuditViolation = errors.New(
		"audit violation",
	)
)

func ValidateDecision(
	d Decision,
	layer Layer,
	audits []AuditRecord,
) error {

	if d.AffectsLife &&
		d.PowerConcentration > 0.90 {

		return ErrLifeViolation
	}

	if layer <
		RequiredLayer(d) {

		return ErrSupervisionViolation
	}

	if !ValidateAuditTrail(
		d.Evidence,
		audits,
	) {

		return ErrAuditViolation
	}

	return nil
}
