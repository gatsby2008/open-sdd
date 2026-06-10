import unittest

from engine.titles import commit_subject, mr_title, ticket


class TestTitles(unittest.TestCase):
    def test_ticket(self):
        self.assertEqual(ticket("feature/MYYES-123-foo"), "MYYES-123")
        self.assertEqual(ticket("feature/add-thing"), "")

    def test_commit_subject(self):
        self.assertEqual(
            commit_subject("feature/MYYES-123-foo", "feat", "add consent"),
            "[MYYES-123] feat: add consent",
        )
        self.assertEqual(
            commit_subject("feature/add-thing", "fix", "bug"), "[NO-TICKET] fix: bug"
        )

    def test_mr_title(self):
        self.assertEqual(mr_title("feature/IR-70", "feat", "do it"), "[IR-70] feat: do it")
        self.assertEqual(mr_title("feature/add-thing", "chore", "tidy"), "chore: tidy")


if __name__ == "__main__":
    unittest.main()
