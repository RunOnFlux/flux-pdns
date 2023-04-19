#!/usr/bin/python3

from sys import stdin, stdout
from util import get_char_to_find
from fdm_conf import APP2_CONF, APP_CONF
data = stdin.readline()
stdout.write("OK\tMy Backend\n")
stdout.flush()

deploy_env = os.environ.get('DEPLOY_ENV', 'staging')  # Default to 'staging' if not set
config = APP_CONF if deploy_env == 'release' else APP2_CONF

while True:
    data = stdin.readline().strip()
    kind, qname, qclass, qtype, id, ip = data.split("\t")
    if qtype == "SOA":
        stdout.write("DATA\t" + qname + "\t" + qclass + "\tSOA\t3600\t" + id + "\tns1.runonflux.io st.runonflux.io 2022040801 3600 600 86400 3600\n")
    else:
        name = qname.split(".")[0]
        char_to_search = get_char_to_find(name, config["TYPE"])
        if char_to_search not in config["SPLITS"]:
            stdout.write("NXDOMAIN\n")
        else:
            stdout.write("DATA\t" + qname + "\t" + qclass + "\tA\t3600\t" + id + f'\t{config["SPLITS"][char_to_search]}\n')
        
    stdout.write("LOG\t" + data + "\n")
    stdout.write("END\n")
    stdout.flush()