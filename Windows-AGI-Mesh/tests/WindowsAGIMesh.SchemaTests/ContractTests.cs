using WindowsAGIMesh.Contracts;

namespace WindowsAGIMesh.SchemaTests;

/// <summary>
/// Unit tests for the core contract records in WindowsAGIMesh.Contracts.
/// Verifies computed properties, helper methods, and record equality.
/// </summary>
public sealed class ContractTests
{
    // ─────────────────────────────────────────────────────────────────────────
    // MeshNode
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void MeshNode_IsAccelerated_WhenGpuTrue_ReturnsTrue()
    {
        var node = new MeshNode("n1", "Edge", [], false, true, false);
        node.IsAccelerated.Should().BeTrue();
    }

    [Fact]
    public void MeshNode_IsAccelerated_WhenNpuTrue_ReturnsTrue()
    {
        var node = new MeshNode("n1", "Edge", [], false, false, true);
        node.IsAccelerated.Should().BeTrue();
    }

    [Fact]
    public void MeshNode_IsAccelerated_WhenCpuOnly_ReturnsFalse()
    {
        var node = new MeshNode("n1", "Edge", [], true, false, false);
        node.IsAccelerated.Should().BeFalse();
    }

    [Fact]
    public void MeshNode_HardwareProfile_ContainsAllFlags()
    {
        var node = new MeshNode("n1", "Edge", [], true, true, false);
        node.HardwareProfile.Should()
            .Contain("CPU=True")
            .And.Contain("GPU=True")
            .And.Contain("NPU=False");
    }

    [Fact]
    public void MeshNode_RecordEquality_SameValues_AreEqual()
    {
        var a = new MeshNode("n1", "Edge", ["nlp"], true, false, false);
        var b = new MeshNode("n1", "Edge", ["nlp"], true, false, false);
        a.Should().Be(b);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MeshAgent
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void MeshAgent_IsTrusted_WhenTrustLevel_GreaterOrEqual_0_8_ReturnsTrue()
    {
        var agent = new MeshAgent("a1", "Executor", [], 0.9);
        agent.IsTrusted.Should().BeTrue();
    }

    [Fact]
    public void MeshAgent_IsTrusted_WhenTrustLevel_Below_0_8_ReturnsFalse()
    {
        var agent = new MeshAgent("a1", "Executor", [], 0.5);
        agent.IsTrusted.Should().BeFalse();
    }

    [Fact]
    public void MeshAgent_HasSkill_ExistingSkill_ReturnsTrue()
    {
        var agent = new MeshAgent("a1", "Executor", ["nlp", "code-gen"], 0.9);
        agent.HasSkill("NLP").Should().BeTrue(); // case-insensitive
    }

    [Fact]
    public void MeshAgent_HasSkill_MissingSkill_ReturnsFalse()
    {
        var agent = new MeshAgent("a1", "Executor", ["nlp"], 0.9);
        agent.HasSkill("vision").Should().BeFalse();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MeshPolicy
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void MeshPolicy_IsHighRisk_WhenHigh_ReturnsTrue()
    {
        var policy = new MeshPolicy("p1", "High", false);
        policy.IsHighRisk.Should().BeTrue();
    }

    [Fact]
    public void MeshPolicy_IsHighRisk_WhenCritical_ReturnsTrue()
    {
        var policy = new MeshPolicy("p1", "Critical", true);
        policy.IsHighRisk.Should().BeTrue();
    }

    [Fact]
    public void MeshPolicy_IsHighRisk_WhenLow_ReturnsFalse()
    {
        var policy = new MeshPolicy("p1", "Low", false);
        policy.IsHighRisk.Should().BeFalse();
    }

    [Fact]
    public void MeshPolicy_RequiresFullGovernance_WhenBothTrue_ReturnsTrue()
    {
        var policy = new MeshPolicy("p1", "High", HumanReview: true, AuditRequired: true);
        policy.RequiresFullGovernance.Should().BeTrue();
    }

    [Fact]
    public void MeshPolicy_RequiresFullGovernance_WhenAuditFalse_ReturnsFalse()
    {
        var policy = new MeshPolicy("p1", "High", HumanReview: true, AuditRequired: false);
        policy.RequiresFullGovernance.Should().BeFalse();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MeshBenchmark
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void MeshBenchmark_Passed_WhenScore_GreaterOrEqual_60_ReturnsTrue()
    {
        var bm = new MeshBenchmark("bm1", 75.0, 120.0);
        bm.Passed.Should().BeTrue();
    }

    [Fact]
    public void MeshBenchmark_Passed_WhenScore_Below_60_ReturnsFalse()
    {
        var bm = new MeshBenchmark("bm1", 45.0, 300.0);
        bm.Passed.Should().BeFalse();
    }

    [Fact]
    public void MeshBenchmark_Summary_ContainsKeyFields()
    {
        var bm = new MeshBenchmark("bm-test", 80.0, 50.0);
        bm.Summary.Should()
            .Contain("bm-test")
            .And.Contain("80")
            .And.Contain("50");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MeshAttestation
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void MeshAttestation_IsApproved_WhenApproved_ReturnsTrue()
    {
        var att = new MeshAttestation("att1", "reviewer@mesh.ai", DateTime.UtcNow, Outcome: "Approved");
        att.IsApproved.Should().BeTrue();
    }

    [Fact]
    public void MeshAttestation_IsRejected_WhenRejected_ReturnsTrue()
    {
        var att = new MeshAttestation("att1", "reviewer@mesh.ai", DateTime.UtcNow, Outcome: "Rejected");
        att.IsRejected.Should().BeTrue();
    }

    [Fact]
    public void MeshAttestation_Summary_ContainsReviewer()
    {
        var att = new MeshAttestation(
            "att1", "alice@mesh.ai", DateTime.UtcNow, Outcome: "Approved");
        att.Summary.Should().Contain("alice@mesh.ai");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MeshTask
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void MeshTask_IsPending_WhenStatusPending_ReturnsTrue()
    {
        var task = new MeshTask("t1", "Do something.", Status: "Pending");
        task.IsPending.Should().BeTrue();
    }

    [Fact]
    public void MeshTask_IsCompleted_WhenStatusCompleted_ReturnsTrue()
    {
        var task = new MeshTask("t1", "Do something.", Status: "Completed");
        task.IsCompleted.Should().BeTrue();
    }

    [Fact]
    public void MeshTask_IsOverdue_WhenDeadlinePassed_ReturnsTrue()
    {
        var task = new MeshTask(
            "t1", "Do something.",
            Deadline: DateTime.UtcNow.AddDays(-1),
            Status: "Pending");

        task.IsOverdue.Should().BeTrue();
    }

    [Fact]
    public void MeshTask_IsOverdue_WhenCompleted_ReturnsFalse()
    {
        var task = new MeshTask(
            "t1", "Do something.",
            Deadline: DateTime.UtcNow.AddDays(-1),
            Status: "Completed");

        task.IsOverdue.Should().BeFalse();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MeshResult
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void MeshResult_IsSuccess_WhenSuccess_ReturnsTrue()
    {
        var result = new MeshResult("r1", "t1", "a1", "Success");
        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public void MeshResult_IsFailure_WhenFailure_ReturnsTrue()
    {
        var result = new MeshResult("r1", "t1", "a1", "Failure");
        result.IsFailure.Should().BeTrue();
    }

    [Fact]
    public void MeshResult_IsFailure_WhenTimeout_ReturnsTrue()
    {
        var result = new MeshResult("r1", "t1", "a1", "Timeout");
        result.IsFailure.Should().BeTrue();
    }

    [Fact]
    public void MeshResult_Summary_ContainsAllKeyFields()
    {
        var result = new MeshResult("r1", "t1", "a1", "Success", ExecutionMs: 42.5);
        result.Summary.Should()
            .Contain("r1")
            .And.Contain("t1")
            .And.Contain("a1")
            .And.Contain("Success");
    }
}