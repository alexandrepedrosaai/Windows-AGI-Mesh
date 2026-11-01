namespace AGIMesh.Validation {

    function IsSupportedPlatform(
        platform : String
    ) : Bool {

        return platform == "Windows"
            or platform == "Linux"
            or platform == "Cloud"
            or platform == "macOS";
    }
}
