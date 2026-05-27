import unittest

from engine.retry import bounded_retry


class RetryTestCase(unittest.TestCase):

    def test_success_on_first_attempt(self):
        call_count = 0

        @bounded_retry(max_attempts=3)
        def work():
            nonlocal call_count
            call_count += 1
            return "ok"

        result = work()
        self.assertEqual(result, "ok")
        self.assertEqual(call_count, 1)

    def test_retries_on_failure_then_succeeds(self):
        call_count = 0

        @bounded_retry(max_attempts=3)
        def work():
            nonlocal call_count
            call_count += 1
            if call_count < 3:
                raise ValueError("not yet")
            return "ok"

        result = work()
        self.assertEqual(result, "ok")
        self.assertEqual(call_count, 3)

    def test_exhausts_all_attempts_and_raises(self):
        call_count = 0

        @bounded_retry(max_attempts=3)
        def work():
            nonlocal call_count
            call_count += 1
            raise ValueError("always fails")

        with self.assertRaises(ValueError):
            work()
        self.assertEqual(call_count, 3)

    def test_on_exhausted_callback(self):
        exhausted_args = []

        def callback(state, exc):
            exhausted_args.append((state, exc))

        @bounded_retry(max_attempts=2, on_exhausted=callback)
        def work(state=None):
            raise RuntimeError("boom")

        with self.assertRaises(RuntimeError):
            work(42)

        self.assertEqual(len(exhausted_args), 1)
        state, exc = exhausted_args[0]
        self.assertEqual(state, 42)
        self.assertIsInstance(exc, RuntimeError)

    def test_on_exhausted_called_only_when_exhausted(self):
        exhausted_args = []

        def callback(state, exc):
            exhausted_args.append((state, exc))

        @bounded_retry(max_attempts=3, on_exhausted=callback)
        def work(state=None):
            return "ok"

        result = work("state")
        self.assertEqual(result, "ok")
        self.assertEqual(exhausted_args, [])

    def test_default_max_attempts_is_2(self):
        call_count = 0

        @bounded_retry()
        def work():
            nonlocal call_count
            call_count += 1
            raise ValueError("fail")

        with self.assertRaises(ValueError):
            work()
        self.assertEqual(call_count, 2)

    def test_single_attempt_no_retry(self):
        call_count = 0

        @bounded_retry(max_attempts=1)
        def work():
            nonlocal call_count
            call_count += 1
            raise ValueError("fail")

        with self.assertRaises(ValueError):
            work()
        self.assertEqual(call_count, 1)

    def test_preserves_return_value_across_retries(self):
        @bounded_retry(max_attempts=3)
        def add(a, b):
            return a + b

        self.assertEqual(add(2, 3), 5)
        self.assertEqual(add(-1, 1), 0)

    def test_does_not_swallow_exception_type(self):
        @bounded_retry(max_attempts=2)
        def work():
            raise TypeError("bad type")

        with self.assertRaises(TypeError):
            work()


if __name__ == "__main__":
    unittest.main()
