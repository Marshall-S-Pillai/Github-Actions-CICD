"""Small dependency-free sample application for the GitHub Actions CI/CD capstone."""

APP_VERSION = "1.0.0"


def health() -> dict:
    """Return a simple health response."""
    return {"status": "healthy", "version": APP_VERSION}


def greet(name: str = "GitHub Actions") -> str:
    """Return a greeting for the supplied name."""
    clean_name = name.strip()
    if not clean_name:
        clean_name = "GitHub Actions"
    return f"Hello, {clean_name}!"


if __name__ == "__main__":
    print(greet())
    print(health())
