"""Microsoft Teams collaborative-agent notification contract."""
from dataclasses import dataclass
from typing import Any

@dataclass(frozen=True)
class TeamsEvent:
    workload: str
    status: str
    release_url: str
    human_review_required: bool = True


def adaptive_card(event: TeamsEvent) -> dict[str, Any]:
    return {
        "type": "AdaptiveCard",
        "version": "1.5",
        "body": [
            {"type": "TextBlock", "text": event.workload, "weight": "Bolder"},
            {"type": "TextBlock", "text": f"Status: {event.status}"},
            {"type": "TextBlock", "text": "Human-agent collaboration is required for production approval."},
        ],
        "actions": [{"type": "Action.OpenUrl", "title": "Open release", "url": event.release_url}],
    }
