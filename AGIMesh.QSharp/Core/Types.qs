namespace AGIMesh.Core {

    newtype WindowsCompatibility = (
        Supported : Bool,
        Confidence : Double
    );

    newtype SemanticClassification = (
        Domain : String,
        Category : String
    );
}
