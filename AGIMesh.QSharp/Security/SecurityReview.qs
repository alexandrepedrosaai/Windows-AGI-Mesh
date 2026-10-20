namespace AGIMesh.Security {

    newtype SecurityReview = (
        Reviewed : Bool,
        Score : Double,
        Risk : String
    );

    function CreateReview(
        score : Double
    ) : SecurityReview {

        return SecurityReview(
            true,
            score,
            RiskLevel(score)
        );
    }
}
