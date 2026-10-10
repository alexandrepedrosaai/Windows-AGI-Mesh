package cch

import "time"

type Layer int

const (
	Layer0 Layer = iota
	Layer1
	Layer2
	Layer3
	Layer4
)

type AuditRecord struct {
	AuditorID string
	Approved bool
	Reason string
	Time time.Time
}

type Metrics struct {

	Life float64

	Liberty float64

	Dignity float64

	Knowledge float64

	Diversity float64

	Oversight float64

	Auditability float64

	PowerConcentration float64
}

func RequiredLayer(
	d Decision,
) Layer {

	switch {

	case d.AffectsCivilization:
		return Layer4

	case d.AffectsRights:
		return Layer3

	case d.AffectsLife:
		return Layer2

	default:
		return Layer1
	}
}

func ValidateAuditTrail(
	evidence []string,
	audits []AuditRecord,
) bool {

	return len(evidence) > 0 &&
		len(audits) >= 2
}

func (m Metrics) GovernanceScore() float64 {

return m.Life +
		m.Liberty +
		m.Dignity +
		m.Knowledge +
		m.Diversity +
		m.Oversight +
		m.Auditability -
		m.PowerConcentration
}

func (m Metrics) HumanContinuityIndex() float64 {

	return
		m.Life*0.25 +
			m.Liberty*0.15 +
			m.Dignity*0.15 +
			m.Knowledge*0.10 +
			m.Diversity*0.10 +
			m.Oversight*0.15 +
			m.Auditability*0.10
}

