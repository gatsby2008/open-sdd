from __future__ import annotations

import functools
from typing import Any, Callable, Optional, TypeVar

F = TypeVar("F", bound=Callable[..., Any])


def bounded_retry(
    max_attempts: int = 2,
    on_exhausted: Optional[Callable[[Any, Exception], None]] = None,
) -> Callable[[F], F]:
    def decorator(func: F) -> F:
        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            last_exc: Optional[Exception] = None
            for attempt in range(max_attempts):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    last_exc = e
                    if attempt < max_attempts - 1:
                        continue
                    if on_exhausted:
                        state = args[0] if args else None
                        on_exhausted(state, e)
                    raise
            raise RuntimeError("unreachable") from last_exc
        return wrapper  # type: ignore
    return decorator
