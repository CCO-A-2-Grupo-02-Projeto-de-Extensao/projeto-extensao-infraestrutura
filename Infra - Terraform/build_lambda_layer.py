import shutil
import subprocess
import sys
from pathlib import Path


def main():
    destination = Path(sys.argv[1]).resolve()
    requirements = Path(sys.argv[2]).resolve()
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--disable-pip-version-check",
            "--no-compile",
            "--target",
            str(destination),
            "-r",
            str(requirements),
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
