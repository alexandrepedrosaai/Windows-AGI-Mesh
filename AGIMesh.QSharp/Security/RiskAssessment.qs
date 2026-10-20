namespace AGIMesh.Security {

    function CalculateRiskScore(
        confidence : Double,
        vulnerabilities : Int
    ) : Double {

        if confidence < 0.0
            or confidence > 1.0 {

            fail "Invalid confidence.";
        }

        if vulnerabilities < 0 {
            fail "Vulnerability count must be nonnegative.";
        }

        let vulnerabilityPenalty =
            IntAsDouble(vulnerabilities) * 10.0;

        let confidenceBonus =
            confidence * 100.0;

        let score =
            confidenceBonus
            - vulnerabilityPenalty;

        if score < 0.0 {
            return 0.0;
        }

        return score;
    }

    function RiskLevel(
        score : Double
    ) : String {

        if score >= 90.0 {
            return "Low";
        }

        if score >= 70.0 {
            return "Medium";
        }

        return "High";
    }
}
