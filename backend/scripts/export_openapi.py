"""Write the OpenAPI specification generated from the code to docs/api/schemas/openapi.json.

Run from backend/:  python scripts/export_openapi.py
The file is version-controlled and linted (docs/api/strategy.md).
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.main import create_app  # noqa: E402

TARGET = Path(__file__).resolve().parents[2] / "docs" / "api" / "schemas" / "openapi.json"


def main() -> None:
    spec = create_app().openapi()
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"written {TARGET}")


if __name__ == "__main__":
    main()
