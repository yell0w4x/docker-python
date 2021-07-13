#!/usr/bin/python3

import os
import argparse
import re, shutil, tempfile

def sed_inplace(filename, pattern, repl):
    '''
    Perform the pure-Python equivalent of in-place `sed` substitution: e.g.,
    `sed -i -e 's/'${pattern}'/'${repl}' "${filename}"`.
    '''
    # For efficiency, precompile the passed regular expression.
    pattern_compiled = re.compile(pattern)

    # For portability, NamedTemporaryFile() defaults to mode "w+b" (i.e., binary
    # writing with updating). This is usually a good thing. In this case,
    # however, binary writing imposes non-trivial encoding constraints trivially
    # resolved by switching to text writing. Let's do that.
    with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp_file:
        with open(filename) as src_file:
            for line in src_file:
                tmp_file.write(pattern_compiled.sub(repl, line))
                print(pattern_compiled.sub(repl, line))

    # Overwrite the original file with the munged temporary file in a
    # manner preserving file attributes (e.g., permissions).
    shutil.copystat(filename, tmp_file.name)
    shutil.move(tmp_file.name, filename)

ap = argparse.ArgumentParser()
ap.add_argument("-NotebookApp.base_url", "--NotebookApp.base_url", required=True, help="")
ap.add_argument("-NotebookApp.token", "--NotebookApp.token", required=False, help="")
ap.add_argument("-NotebookApp.allow_origin", "--NotebookApp.allow_origin", required=False, help="")
args = vars(ap.parse_args())

uuid = args["NotebookApp.base_url"].split("/")[2]

command = 'wget -O /dev/null -o /dev/null https://ms-backend-api.mdscdev.com/api/1.0/rents/service/status/' + uuid
os.system("( crontab -l | grep -v -F \"" + command + "\" ; echo \"*/15 * * * * " + command + "\" ) | crontab -")

sed_inplace('/home/jovyan/.jupyter/custom/custom.js', '""', "\"" + uuid + "\"")
