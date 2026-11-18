import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

with tempfile.TemporaryDirectory() as directory:
    binary = os.path.join(directory, "maps_test")
    subprocess.run(
        ["cc", "-O1", "-Wall", "-Wextra", "-Werror", "-Wno-builtin-declaration-mismatch",
         "-o", binary, os.path.join(HERE, "ndk_auxv_maps_test.c"), "-lpthread", "-ldl"],
        check=True,
    )
    subprocess.run([binary], check=True)
print("ndk_auxv_maps_test: all passed")
