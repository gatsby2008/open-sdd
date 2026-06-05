import os
import tempfile
import unittest

from engine import coverage

JAVA_MAIN = "service/src/main/java/com/acme/lead/LeadProcessor.java"


class TestIsTestableSourceJava(unittest.TestCase):
    def test_production_service_is_testable(self):
        self.assertTrue(coverage.is_testable_source(JAVA_MAIN, "java"))

    def test_root_level_src_main_is_testable(self):
        # No module prefix: git returns "src/main/..." with no leading slash.
        self.assertTrue(coverage.is_testable_source(
            "src/main/java/com/acme/LeadProcessor.java", "java"))

    def test_file_outside_src_main_is_not(self):
        self.assertFalse(coverage.is_testable_source(
            "service/src/test/java/com/acme/LeadProcessorTest.java", "java"))

    def test_test_file_is_not_production(self):
        self.assertFalse(coverage.is_testable_source(
            "service/src/test/java/com/acme/FooIT.java", "java"))

    def test_dto_suffix_excluded(self):
        self.assertFalse(coverage.is_testable_source(
            "service/src/main/java/com/acme/LeadRequest.java", "java"))

    def test_config_suffix_excluded(self):
        self.assertFalse(coverage.is_testable_source(
            "service/src/main/java/com/acme/SecurityConfig.java", "java"))

    def test_config_package_excluded(self):
        self.assertFalse(coverage.is_testable_source(
            "service/src/main/java/com/acme/config/Beans.java", "java"))

    def test_dto_package_excluded(self):
        self.assertFalse(coverage.is_testable_source(
            "service/src/main/java/com/acme/dto/Whatever.java", "java"))

    def test_package_info_excluded(self):
        self.assertFalse(coverage.is_testable_source(
            "service/src/main/java/com/acme/package-info.java", "java"))

    def test_application_excluded(self):
        self.assertFalse(coverage.is_testable_source(
            "service/src/main/java/com/acme/AcmeApplication.java", "java"))

    def test_non_java_in_java_stack_excluded(self):
        self.assertFalse(coverage.is_testable_source(
            "service/src/main/resources/app.yml", "java"))


class TestIsTestableSourceFrontend(unittest.TestCase):
    def test_component_is_testable(self):
        self.assertTrue(coverage.is_testable_source("src/cart/CartView.tsx", "frontend"))

    def test_hook_is_testable(self):
        self.assertTrue(coverage.is_testable_source("src/hooks/useCart.ts", "frontend"))

    def test_declaration_file_excluded(self):
        self.assertFalse(coverage.is_testable_source("src/types/global.d.ts", "frontend"))

    def test_test_file_excluded(self):
        self.assertFalse(coverage.is_testable_source("src/cart/CartView.test.tsx", "frontend"))

    def test_spec_file_excluded(self):
        self.assertFalse(coverage.is_testable_source("src/cart/CartView.spec.tsx", "frontend"))

    def test_tests_dir_excluded(self):
        self.assertFalse(coverage.is_testable_source("src/__tests__/CartView.tsx", "frontend"))

    def test_index_barrel_excluded(self):
        self.assertFalse(coverage.is_testable_source("src/cart/index.ts", "frontend"))

    def test_styles_module_excluded(self):
        self.assertFalse(coverage.is_testable_source("src/cart/CartView.styles.ts", "frontend"))

    def test_types_module_excluded(self):
        self.assertFalse(coverage.is_testable_source("src/cart/cart.types.ts", "frontend"))

    def test_config_excluded(self):
        self.assertFalse(coverage.is_testable_source("vite.config.ts", "frontend"))

    def test_stories_excluded(self):
        self.assertFalse(coverage.is_testable_source("src/cart/CartView.stories.tsx", "frontend"))


class TestHasMatchingTestJava(unittest.TestCase):
    def test_unit_test_matches(self):
        self.assertTrue(coverage.has_matching_test(
            JAVA_MAIN, ["service/src/test/java/com/acme/lead/LeadProcessorTest.java"], "java"))

    def test_integration_test_matches(self):
        self.assertTrue(coverage.has_matching_test(
            JAVA_MAIN, ["service/src/test/java/com/acme/LeadProcessorIT.java"], "java"))

    def test_itcase_matches(self):
        self.assertTrue(coverage.has_matching_test(
            JAVA_MAIN, ["service/src/test/java/com/acme/LeadProcessorITCase.java"], "java"))

    def test_no_test_no_match(self):
        self.assertFalse(coverage.has_matching_test(
            JAVA_MAIN, ["service/src/test/java/com/acme/OtherTest.java"], "java"))

    def test_match_ignores_package_path(self):
        self.assertTrue(coverage.has_matching_test(
            JAVA_MAIN, ["other/module/src/test/java/x/LeadProcessorTests.java"], "java"))


class TestHasMatchingTestFrontend(unittest.TestCase):
    def test_sibling_test_matches(self):
        self.assertTrue(coverage.has_matching_test(
            "src/cart/CartView.tsx", ["src/cart/CartView.test.tsx"], "frontend"))

    def test_spec_matches(self):
        self.assertTrue(coverage.has_matching_test(
            "src/cart/CartView.tsx", ["src/cart/CartView.spec.ts"], "frontend"))

    def test_tests_dir_matches(self):
        self.assertTrue(coverage.has_matching_test(
            "src/cart/CartView.tsx", ["src/__tests__/CartView.test.tsx"], "frontend"))

    def test_unrelated_test_no_match(self):
        self.assertFalse(coverage.has_matching_test(
            "src/cart/CartView.tsx", ["src/cart/Other.test.tsx"], "frontend"))


class TestClassesMissingTests(unittest.TestCase):
    def test_flags_class_without_test(self):
        self.assertEqual(coverage.classes_missing_tests([JAVA_MAIN], [JAVA_MAIN], "java"), [JAVA_MAIN])

    def test_satisfied_by_existing_test_in_repo(self):
        all_files = [JAVA_MAIN, "service/src/test/java/com/acme/LeadProcessorTest.java"]
        self.assertEqual(coverage.classes_missing_tests([JAVA_MAIN], all_files, "java"), [])

    def test_satisfied_by_test_changed_in_same_diff(self):
        changed = [JAVA_MAIN, "service/src/test/java/com/acme/LeadProcessorIT.java"]
        self.assertEqual(coverage.classes_missing_tests(changed, changed, "java"), [])

    def test_waived_class_excluded(self):
        self.assertEqual(
            coverage.classes_missing_tests([JAVA_MAIN], [JAVA_MAIN], "java", waived={JAVA_MAIN}), [])

    def test_dto_change_not_flagged(self):
        changed = ["service/src/main/java/com/acme/LeadRequest.java"]
        self.assertEqual(coverage.classes_missing_tests(changed, changed, "java"), [])

    def test_test_only_change_not_flagged(self):
        changed = ["service/src/test/java/com/acme/LeadProcessorTest.java"]
        self.assertEqual(coverage.classes_missing_tests(changed, changed, "java"), [])

    def test_multiple_offenders_sorted_and_deduped(self):
        a = "service/src/main/java/com/acme/A.java"
        b = "service/src/main/java/com/acme/B.java"
        self.assertEqual(coverage.classes_missing_tests([b, a, b], [a, b], "java"), [a, b])

    def test_frontend_offender(self):
        changed = ["src/cart/CartView.tsx"]
        self.assertEqual(coverage.classes_missing_tests(changed, changed, "frontend"), changed)

    def test_frontend_satisfied(self):
        changed = ["src/cart/CartView.tsx"]
        all_files = changed + ["src/cart/CartView.test.tsx"]
        self.assertEqual(coverage.classes_missing_tests(changed, all_files, "frontend"), [])

    def test_unknown_stack_flags_nothing(self):
        self.assertEqual(coverage.classes_missing_tests([JAVA_MAIN], [JAVA_MAIN], "unknown"), [])


class TestWaivers(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self._cwd = os.getcwd()
        os.chdir(self._tmp.name)
        self.addCleanup(lambda: os.chdir(self._cwd))

    def test_waiver_paths_with_slug(self):
        self.assertEqual(
            coverage.waiver_paths("demo"),
            [".specwork/_test/demo-coverage-waivers.json", ".sdd-coverage-waivers.json"])

    def test_waiver_paths_without_slug(self):
        self.assertEqual(coverage.waiver_paths(None), [".sdd-coverage-waivers.json"])

    def test_empty_when_no_files(self):
        self.assertEqual(coverage.load_waivers("demo"), set())

    def test_reads_standalone_fallback(self):
        with open(".sdd-coverage-waivers.json", "w") as f:
            f.write('{"src/Foo.java": "no logic"}')
        self.assertEqual(coverage.load_waivers(None), {"src/Foo.java"})

    def test_reads_pipeline_file(self):
        os.makedirs(".specwork/_test")
        with open(".specwork/_test/demo-coverage-waivers.json", "w") as f:
            f.write('{"src/Bar.java": "config"}')
        self.assertEqual(coverage.load_waivers("demo"), {"src/Bar.java"})

    def test_malformed_json_is_ignored(self):
        with open(".sdd-coverage-waivers.json", "w") as f:
            f.write("{not json")
        self.assertEqual(coverage.load_waivers(None), set())


class TestIsTestPath(unittest.TestCase):
    def test_java_test(self):
        self.assertTrue(coverage.is_test_path("src/test/java/FooTest.java", "java"))

    def test_java_production_is_not(self):
        self.assertFalse(coverage.is_test_path(JAVA_MAIN, "java"))

    def test_frontend_spec(self):
        self.assertTrue(coverage.is_test_path("src/Foo.spec.ts", "frontend"))


if __name__ == "__main__":
    unittest.main()
