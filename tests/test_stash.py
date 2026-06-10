import unittest

from engine.stash import deduplicate, pipeline_stashes


class TestStash(unittest.TestCase):
    SAMPLE = (
        "stash@{0} f-pause: feature/alpha\n"
        "stash@{1} WIP on main: 1234 unrelated\n"
        "stash@{2} f-pause: feature/beta\n"
        "stash@{3} f-pause: feature/alpha\n"
    )

    def test_filters_and_extracts_branch(self):
        self.assertEqual(
            pipeline_stashes(self.SAMPLE),
            [
                ("stash@{0}", "feature/alpha"),
                ("stash@{2}", "feature/beta"),
                ("stash@{3}", "feature/alpha"),
            ],
        )

    def test_deduplicate_keeps_newest(self):
        kept, stale = deduplicate(pipeline_stashes(self.SAMPLE))
        self.assertEqual(kept, [("stash@{0}", "feature/alpha"), ("stash@{2}", "feature/beta")])
        self.assertEqual(stale, [("stash@{3}", "feature/alpha")])

    def test_matches_git_on_branch_prefix(self):
        # git prefixes the stash subject with "On <branch>: ", so the f-pause
        # marker is not at the start — it must still be detected.
        out = "stash@{0} On feature/demo: f-pause: feature/demo\n"
        self.assertEqual(pipeline_stashes(out), [("stash@{0}", "feature/demo")])

    def test_empty(self):
        self.assertEqual(pipeline_stashes(""), [])
        self.assertEqual(deduplicate([]), ([], []))


if __name__ == "__main__":
    unittest.main()
