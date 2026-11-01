namespace AGIMesh.Governance {

    function ApprovalDecision(
        reviewApproved : Bool
    ) : String {

        if reviewApproved {
            return "Approved";
        }

        return "Rejected";
    }
}
