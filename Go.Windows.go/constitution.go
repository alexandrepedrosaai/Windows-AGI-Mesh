package cch

type Principle string

const (
	PrimacyOfLife      Principle = "PRIMACY_OF_LIFE"
	HumanSovereignty   Principle = "HUMAN_SOVEREIGNTY"
	IndividualDignity  Principle = "INDIVIDUAL_DIGNITY"
	CulturalContinuity Principle = "CULTURAL_CONTINUITY"
	OpenKnowledge      Principle = "OPEN_KNOWLEDGE"
)

type Constitution struct {
	Version string
	Principles []Principle
}

type ConstitutionalLayer struct {
	Name string
	Weight float64
}

type ConstitutionalOverlay struct {
	Layers []ConstitutionalLayer
}

func NewConstitution() Constitution {
	return Constitution{
		Version: "4.0",
		Principles: []Principle{
			PrimacyOfLife,
			HumanSovereignty,
			IndividualDignity,
			CulturalContinuity,
			OpenKnowledge,
		},
	}
}

func (o ConstitutionalOverlay) DominantLayer() string {

	var winner string
	max := -1.0

	for _, l := range o.Layers {

		if l.Weight > max {
			winner = l.Name
			max = l.Weight
		}
	}

	return winner
}
