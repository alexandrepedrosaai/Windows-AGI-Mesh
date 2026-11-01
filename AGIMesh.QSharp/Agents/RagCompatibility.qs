namespace AGIMesh.Agents {

    function IsRagCompatible(
        indexed : Bool,
        searchable : Bool
    ) : Bool {

        return indexed
            and searchable;
    }
}
