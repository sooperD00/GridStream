"""Module entrypoint: ``python -m standard_service_stub``.

The distroless image (ADR-0009) has no shell, so the container ENTRYPOINT
invokes this module directly rather than calling a console-script wrapper.

Three equivalent ways to run this service locally; all dispatch to
``main.run()``:

    standard-service-stub                  # console-script (project.scripts)
    python -m standard_service_stub        # this file
    python src/standard_service_stub/main.py  # direct script invocation

Production uses ``python -m`` for portability across container runtimes.
Local development can use any; the console-script form is shortest.
"""

from standard_service_stub.main import run

if __name__ == "__main__":
    run()
