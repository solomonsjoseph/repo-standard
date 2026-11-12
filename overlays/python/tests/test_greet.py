from __PKG__ import greet


def test_greet() -> None:
    assert greet("world") == "Hello, world!"
