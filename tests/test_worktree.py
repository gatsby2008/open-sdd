import unittest

from engine.worktree import parse_porcelain


class TestParsePorcelain(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(parse_porcelain(""), [])

    def test_changed_files(self):
        out = " M src/A.java\n?? new.txt\nA  staged.txt\n"
        self.assertEqual(parse_porcelain(out), ["src/A.java", "new.txt", "staged.txt"])

    def test_rename_keeps_new_path(self):
        self.assertEqual(parse_porcelain("R  old/n.md -> new/n.md\n"), ["new/n.md"])

    def test_exclude_agent_files(self):
        out = " M CLAUDE.md\n M AGENTS.md\n M src/Real.java\n"
        self.assertEqual(parse_porcelain(out, exclude_agent_files=True), ["src/Real.java"])

    def test_exclude_agent_files_by_basename(self):
        self.assertEqual(parse_porcelain(" M docs/CLAUDE.md\n", exclude_agent_files=True), [])


if __name__ == "__main__":
    unittest.main()
