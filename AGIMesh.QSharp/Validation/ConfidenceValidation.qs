namespace AGIMesh.Validation {

    function IsValidConfidence(
        confidence : Double
    ) : Bool {

        return confidence >= 0.0
            and confidence <= 1.0;
    }
}
