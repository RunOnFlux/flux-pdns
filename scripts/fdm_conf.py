from utils import build_split_map

SPLIT_TYPES = {
  "NAME": "NAME",
  "HASH": "HASH",
}

APP2_CONF = {
  "TYPE": SPLIT_TYPES["NAME"],
  "SPLITS": build_split_map([
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
        "1.1.1.1"
      ]
    },
  ])
}

APP_CONF = {
  "TYPE": SPLIT_TYPES["NAME"],
  "SPLITS": build_split_map([
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
        "1.1.1.1"
      ]
    },
  ])
}
