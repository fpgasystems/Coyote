#!/usr/bin/env python

import os, sys

def getOutput(cmd):
    return os.popen(cmd).read()

if (len(sys.argv) <> 2):
    print "usage: %s size_in_bytes" % sys.argv[0]
else:
    maxSize = int(sys.argv[1])

    revisions = getOutput("git rev-list HEAD").split()

    bigfiles = set()
    for revision in revisions:
        files = getOutput("git ls-tree -zrl %s" % revision).split('\0')
        for file in files:
            if file == "":
                continue
            splitdata = file.split()
            commit = splitdata[2]
            if splitdata[3] == "-":
                continue
            size = int(splitdata[3])
            path = splitdata[4]
            if (size > maxSize):
                bigfiles.add("%10d %s %s" % (size, commit, path))

    bigfiles = sorted(bigfiles, reverse=True)

    for f in bigfiles:
        print f
