#!/usr/bin/env python3
"""Prints the ndk-modes entry for the game in an .apkm (read from its info.json), or nothing."""
import json
import sys
import zipfile


def package(path):
    try:
        with zipfile.ZipFile(path) as archive:
            return json.loads(archive.read('info.json')).get('pname')
    except (OSError, KeyError, ValueError, zipfile.BadZipFile):
        return None


def main(table, game):
    name = package(game)
    if not name:
        return
    with open(table, encoding='utf-8') as lines:
        for line in lines:
            fields = line.split()
            if len(fields) == 2 and fields[0] == name:
                print(fields[1])
                return


if __name__ == '__main__':
    main(*sys.argv[1:3])
