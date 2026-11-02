"""Service-name resolver parity.

open-sdd (lib/service-name.sh) and sdd-plugin derive the registry's service key
separately. When both write the same registry ($OPEN_SDD_DOC_HOME ==
$CLAUDE_DOC_HOME) they must agree, or one service's specs and ADRs land in two
folders. These fixtures pin open-sdd's behavior; when a sdd-plugin checkout is
found (SDD_PLUGIN_ROOT, default ../sdd-plugin) its resolver must match on every
fixture.
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OPEN_SDD_RESOLVER = REPO_ROOT / "lib" / "service-name.sh"
SDD_PLUGIN_RESOLVER = (
    Path(os.environ.get("SDD_PLUGIN_ROOT", REPO_ROOT.parent / "sdd-plugin"))
    / "lib" / "service-name.sh"
)

# name -> ({relative path: content}, expected key). The repo dir is named
# "fixture-repo", so the git-basename fallback resolves to that.
FIXTURES = {
    "yaml nested": (
        {"src/main/resources/application.yml":
            "server:\n  port: 8080\nspring:\n  application:\n    name: Leads-Service\n"},
        "leads-service",
    ),
    "yaml ignores decoy name keys": (
        {"src/main/resources/application.yml":
            "info:\n  name: decoy\nspring:\n  datasource:\n    name: db\n"
            "  application:\n    name: consent-service  # deployed name\n"},
        "consent-service",
    ),
    "yaml quoted": (
        {"src/main/resources/application.yaml":
            "spring:\n  application:\n    name: \"marketing-service\"\n"},
        "marketing-service",
    ),
    "properties": (
        {"src/main/resources/application.properties":
            "server.port=8080\nspring.application.name = report-service\n"},
        "report-service",
    ),
    "yaml wins over properties": (
        {"src/main/resources/application.yml": "spring:\n  application:\n    name: a-service\n",
         "src/main/resources/application.properties": "spring.application.name=b-service\n"},
        "a-service",
    ),
    "service-info heading": (
        {"docs/service-info.md": "# Service: Consumer Portal\n\nbody\n"},
        "consumer-portal",
    ),
    "git basename fallback": ({}, "fixture-repo"),
}


def _resolve(resolver: Path, files: dict) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "fixture-repo"
        repo.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        for rel, content in files.items():
            p = repo / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
        out = subprocess.run(
            ["bash", "-c", f'. "{resolver}" && resolve_service_name'],
            cwd=repo, capture_output=True, text=True, check=True,
        )
        return out.stdout.strip()


class TestOpenSddResolver(unittest.TestCase):
    def test_fixtures(self):
        for name, (files, expected) in FIXTURES.items():
            with self.subTest(name):
                self.assertEqual(_resolve(OPEN_SDD_RESOLVER, files), expected)


@unittest.skipUnless(SDD_PLUGIN_RESOLVER.is_file(),
                     f"sdd-plugin resolver not found at {SDD_PLUGIN_RESOLVER}")
class TestParityWithSddPlugin(unittest.TestCase):
    def test_same_key_on_every_fixture(self):
        for name, (files, _) in FIXTURES.items():
            with self.subTest(name):
                self.assertEqual(_resolve(SDD_PLUGIN_RESOLVER, files),
                                 _resolve(OPEN_SDD_RESOLVER, files))


if __name__ == "__main__":
    unittest.main()
