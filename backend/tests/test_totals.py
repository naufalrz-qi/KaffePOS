import json
from pathlib import Path

import pytest

from sales.totals import compute_totals

CASES = json.loads((Path(__file__).resolve().parents[2] / "shared" / "totals_cases.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
def test_totals_match_shared_vectors(case):
    assert compute_totals(**case["input"]) == case["expected"]
