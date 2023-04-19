import hashlib

def build_split_map(splits):
  return {
    char: ip 
    for conf in splits
    for char_code in range(ord(conf['start']), ord(conf['end'])+1)
    for char, ip in zip(chr(char_code), conf['ips'])
  }

def get_char_to_find(name, split_type):
  if split_type == SPLIT_TYPES.NAME:
    return name[0]
  else:
    hash_object = hashlib.sha256(name)
    hex_dig = hash_object.hexdigest()
    return hex_dig[0]

