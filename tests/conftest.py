import pathlib
import sys

# scripts/ is a directory of standalone executables, not an installed package.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "scripts"))
