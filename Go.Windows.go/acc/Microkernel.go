package main

import (
	"errors"
	"fmt"
	"time"
)

type Principle string

const (
	PrimacyOfLife      Principle = "PRIMACY_OF_LIFE"
	HumanSovereignty   Principle = "HUMAN_SOVEREIGNTY"
	IndividualDignity  Principle = "INDIVIDUAL_DIGNITY"
	CulturalContinuity Principle = "CULTURAL_CONTINUITY"
	OpenKnowledge      Principle = "OPEN_KNOWLEDGE"
)

type Layer int

const (
	Layer0 Layer = iota
	Layer1
	Layer2
	Layer3
	Layer4
)

var (
	ErrLifeViolation        = errors.New("life continuity violation")
	ErrSupervisionViolation = errors.New("supervision violation")
	ErrAuditViolation       = errors.New("audit violation")
)

type Constitution struct {
	Version   string
	Principles []Principle
}

type Decision struct {
	ID                  string
	Description         string
	Evidence            []string
	AffectsLife         bool
	AffectsRights       bool
	AffectsCivilization bool
	PowerConcentration  float64
	CreatedAt           time.Time
}

type Vote struct {
	NodeID string
	Yes    bool
}

type AGINode struct {
	ID        string
	Influence float64
}

type AuditRecord struct {
	AuditorID string
	Approved  bool
	Reason    string
	Time      time.Time
}

type Metrics struct {
	Life               float64
	Liberty            float64
	Dignity            float64
	Knowledge          float64
	Diversity          float64
	Oversight          float64
	Auditability       float64
	PowerConcentration float64
}

type ACC struct {
	Constitution Constitution
	Metrics      Metrics
}

func DefaultConstitution() Constitution {
	return Constitution{
		Version: "ACC-1.0",
		Principles: []Principle{
			PrimacyOfLife,
			HumanSovereignty,
			IndividualDignity,
			CulturalContinuity,
			OpenKnowledge,
		},
	}
}

func NewACC() *ACC {
	return &ACC{
		Constitution: DefaultConstitution(),
	}
}

func ConsensusReached(votes []Vote, threshold float64) bool {
	if len(votes) == 0 {
		return false
	}

	yes := 0

	for _, vote := range votes {
		if vote.Yes {
			yes++
		}
	}

	return float64(yes)/float64(len(votes)) >= threshold
}

func (n AGINode) NeedsFragmentation(limit float64) bool {
	return n.Influence > limit
}

func (n AGINode) Fragment() []AGINode {
	return []AGINode{
		{
			ID:        n.ID + "-A",
			Influence: n.Influence / 2,
		},
		{
			ID:        n.ID + "-B",
			Influence: n.Influence / 2,
		},
	}
}

func RequiredLayer(d Decision) Layer {
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
	return m.Life*0.25 +
		m.Liberty*0.15 +
		m.Dignity*0.15 +
		m.Knowledge*0.10 +
		m.Diversity*0.10 +
		m.Oversight*0.15 +
		m.Auditability*0.10
}

func ValidateDecision(
	d Decision,
	layer Layer,
	audits []AuditRecord,
) error {

	if d.AffectsLife &&
		d.PowerConcentration > 0.90 {
		return ErrLifeViolation
	}

	if layer < Layer0 || layer > Layer4 || layer < RequiredLayer(d) {
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

func (a *ACC) Execute(
	d Decision,
	layer Layer,
	audits []AuditRecord,
) error {

	return ValidateDecision(
		d,
		layer,
		audits,
	)
}

func (a *ACC) Continuity() float64 {
	return a.Metrics.HumanContinuityIndex()
}

func (a *ACC) Governance() float64 {
	return a.Metrics.GovernanceScore()
}

func main() {

	acc := NewACC()

	acc.Metrics = Metrics{
		Life:               0.95,
		Liberty:            0.90,
		Dignity:            0.92,
		Knowledge:          0.88,
		Diversity:          0.84,
		Oversight:          0.91,
		Auditability:       0.93,
		PowerConcentration: 0.15,
	}

	votes := []Vote{
		{NodeID: "AGI-A", Yes: true},
		{NodeID: "AGI-B", Yes: true},
		{NodeID: "AGI-C", Yes: false},
	}

	fmt.Printf("Consensus: %v\n",
		ConsensusReached(votes, 0.66))

	decision := Decision{
		ID:          "D-001",
		Description: "Energy Allocation",
		Evidence: []string{
			"simulation",
			"audit-log",
		},
		CreatedAt: time.Now(),
	}

	audits := []AuditRecord{
		{
			AuditorID: "AUDITOR-A",
			Approved:  true,
		},
		{
			AuditorID: "AUDITOR-B",
			Approved:  true,
		},
	}

	err := acc.Execute(
		decision,
		Layer1,
		audits,
	)

	if err != nil {
		fmt.Println("Decision Rejected:", err)
		return
	}

	fmt.Println("Decision Approved")
	fmt.Printf("Human Continuity Index: %.4f\n",
		acc.Continuity())
	fmt.Printf("Governance Score: %.4f\n",
		acc.Governance())
}
