namespace AGIMesh.Validation {

    function IsNonEmpty(
        value : String
    ) : Bool {

        return value != "";
    }

    operation ValidateRequiredFields(
        version : String,
        agency : String,
        release : String
    ) : Bool {

        return
            IsNonEmpty(version)
            and IsNonEmpty(agency)
            and IsNonEmpty(release);
    }
}
