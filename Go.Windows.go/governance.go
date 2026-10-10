package cch

import "time"

type Decision struct {
	ID string

	Description string

	Evidence []string

	AffectsLife bool
	AffectsRights bool
	AffectsCivilization bool

	PowerConcentration float64

	Timestamp time.Time
}

type Vote struct {
	NodeID string
	Yes bool
}

type AGINode struct {
	ID string
	Influence float64
}

func ConsensusReached(
	votes []Vote,
	threshold float64,
) bool {

	if len(votes) == 0 {
		return false
	}

	yes := 0

	for _, vote := range votes {

		if vote.Yes {
			yes++
		}
	}

	return float64(yes) /
		float64(len(votes)) >= threshold
}

func (n AGINode) NeedsFragmentation(
	limit float64,
) bool {

	return n.Influence > limit
}

func (n AGINode) Fragment() []AGINode {

	return []AGINode{
		{
			ID: n.ID + "-A",
			Influence: n.Influence / 2,
		},
		{
			ID: n.ID + "-B",
			Influence: n.Influence / 2,
		},
	}
}
j
