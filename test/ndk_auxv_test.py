import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CC = ["cc", "-O1", "-Wall", "-Wextra", "-Werror", "-Wno-builtin-declaration-mismatch"]

with tempfile.TemporaryDirectory() as directory:
    maps = os.path.join(directory, "maps_test")
    subprocess.run(CC + ["-o", maps, os.path.join(HERE, "ndk_auxv_maps_test.c"), "-lpthread", "-ldl"], check=True)
    subprocess.run([maps], check=True)

    # the shim only rewrites lookups made from a library with the translator's name
    subprocess.run(CC + ["-shared", "-fPIC", "-o", os.path.join(directory, "libndk_translation.so"),
                         os.path.join(HERE, "ndk_auxv_gl_test_bridge.c")], check=True)
    gl = os.path.join(directory, "gl_test")
    subprocess.run(CC + ["-rdynamic", "-o", gl, os.path.join(HERE, "ndk_auxv_gl_test.c"),
                         "-L" + directory, "-lndk_translation", "-Wl,-rpath," + directory, "-ldl"], check=True)
    subprocess.run([gl], check=True)
print("ndk_auxv_test: all passed")
