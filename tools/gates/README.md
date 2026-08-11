# Vendored gate suite

Copied from PowerPlant at scaffold time so CI can run the same deterministic gates the build loop runs. Do not edit by hand — it is overwritten on every run.

    PYTHONPATH=tools/gates python -m powerplant.verify .
