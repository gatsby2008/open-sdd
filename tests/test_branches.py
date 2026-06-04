import unittest

from engine.branches import (
    classify_branch,
    detect_base_branch,
    is_feature_branch,
    requires_clean_tree,
)


class TestBranches(unittest.TestCase):
    def test_classify(self):
        self.assertEqual(classify_branch("feature/IR-70"), "feature")
        self.assertEqual(classify_branch("hotfix/x"), "hotfix")
        self.assertEqual(classify_branch("main"), "main")
        self.assertEqual(classify_branch("master"), "main")
        self.assertEqual(classify_branch("development"), "develop")
        self.assertEqual(classify_branch("whatever"), "other")

    def test_is_feature_branch(self):
        self.assertTrue(is_feature_branch("feature/x"))
        self.assertTrue(is_feature_branch("bugfix/x"))
        self.assertFalse(is_feature_branch("main"))

    def test_requires_clean_tree(self):
        for b in ("main", "master", "develop", "development"):
            self.assertTrue(requires_clean_tree(b))
        self.assertFalse(requires_clean_tree("feature/x"))

    def test_detect_base_branch(self):
        self.assertEqual(detect_base_branch("feature/x", "develop"), "develop")
        self.assertEqual(detect_base_branch("feature/x", ""), "development")
        self.assertEqual(detect_base_branch("feature/x", "", "main"), "main")


if __name__ == "__main__":
    unittest.main()
