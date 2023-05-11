#!/usr/bin/python3

from sys import stdin, stdout
import os
import hashlib

SPLIT_NAME = "NAME"
SPLIT_HASH = "HASH"

app2_list = [
  {
    "start": 'a',
    "end": 'n',
    "ips": [
      "fdm-lb-2-1.runonflux.io"
    ]
  },
  {
    "start": 'o',
    "end": 'z',
    "ips": [
      "fdm-lb-2-2.runonflux.io"
    ]
  },
]

APP2_CONF = {
  "TYPE": SPLIT_NAME,
  "SPLITS": {
    char: ip 
    for conf in app2_list
    for char_code in range(ord(conf['start']), ord(conf['end'])+1)
    for char, ip in zip(chr(char_code), conf['ips'])
  },
}

app_list = [
  {
    "start": 'a',
    "end": 'n',
    "ips": [
      "1.1.1.1"
    ]
  },
  {
    "start": 'o',
    "end": 'z',
    "ips": [
      "2.2.2.2"
    ]
  },
]

APP_CONF = {
  "TYPE": SPLIT_NAME,
  "SPLITS": {
    char: ip 
    for conf in app_list
    for char_code in range(ord(conf['start']), ord(conf['end'])+1)
    for char, ip in zip(chr(char_code), conf['ips'])
  },
}

data = stdin.readline()
stdout.write("OK\tMy Backend\n")
stdout.flush()

deploy_env = os.environ.get('DEPLOY_ENV', 'staging')  # Default to 'staging' if not set
config = APP_CONF if deploy_env == 'release' else APP2_CONF

def get_char_to_find(name, split_type):
  if split_type == SPLIT_NAME:
    return name[0]
  else:
    hash_object = hashlib.sha256(name)
    hex_dig = hash_object.hexdigest()
    return hex_dig[0]

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
            stdout.write("DATA\t" + qname + "\t" + qclass + "\tCNAME\t3600\t" + id + f'\t{config["SPLITS"][char_to_search]}\n')
        
    stdout.write("LOG\t" + data + "\n")
    stdout.write("END\n")
    stdout.flush()