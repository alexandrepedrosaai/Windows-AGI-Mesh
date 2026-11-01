#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"POLICY FAILURE: {message}")
    sys.exit(1)


def load(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def has_severity(document, severities):
    return any(
        finding.get("severity") in severities
        for finding in document.get("findings", [])
    )


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: policy-check.py <review-output.json>")
    review_file = Path(sys.argv[1])
    if not review_file.exists():
        fail(f"file not found: {review_file}")
    review = load(review_file)
    review_outcome = review["review_outcome"]
    release_ready = review["release_ready"]
    build_status = review["build"]["status"]
    tests_status = review["tests"]["status"]
    security_status = review["security"]["status"]
    has_high = has_severity(review, {"High"})
    has_critical = has_severity(review, {"Critical"})

    if has_critical:
        if review_outcome != "ChangesRequested":
            fail("Critical findings require review_outcome=ChangesRequested")
        if release_ready is not False:
            fail("Critical findings require release_ready=false")

    if has_high:
        if review_outcome != "ChangesRequested":
            fail("High findings require review_outcome=ChangesRequested")
        if release_ready is not False:
            fail("High findings require release_ready=false")

    if build_status == "Fail":
        if review_outcome != "ChangesRequested":
            fail("Build failure requires review_outcome=ChangesRequested")
        if release_ready is not False:
            fail("Build failure requires release_ready=false")

    if tests_status == "Fail":
        if review_outcome != "ChangesRequested":
            fail("Test failure requires review_outcome=ChangesRequested")
        if release_ready is not False:
            fail("Test failure requires release_ready=false")

    if security_status == "Fail":
        if review_outcome != "ChangesRequested":
            fail("Security failure requires review_outcome=ChangesRequested")
        if release_ready is not False:
            fail("Security failure requires release_ready=false")

    if review_outcome == "ChangesRequested" and release_ready is not False:
        fail("ChangesRequested requires release_ready=false")

    if review_outcome.startswith("Approved"):
        if (
            has_high
            or has_critical
            or build_status == "Fail"
            or tests_status == "Fail"
            or security_status == "Fail"
        ):
            fail("Approved review contains release blockers")

    print("Policy validation passed")


if __name__ == "__main__":
    main()
  
