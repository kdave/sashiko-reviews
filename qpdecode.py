#!/usr/bin/env python3

import quopri
import sys

if len(sys.argv) < 3:
    print("Usage: $0 input.mbox output.mbox")
else:
    fin = open(sys.argv[1], 'rb')
    fout = open(sys.argv[2], 'wb')
    quopri.decode(fin, fout)
