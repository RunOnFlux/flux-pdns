#!/bin/bash

# Check if pm2 is installed
if ! [ -x "$(command -v pm2)" ]; then
  echo 'pm2 is not installed. Installing now...'
  npm install pm2@latest -g
fi

npm i >> /dev/null

is_running=$(pm2 list | grep healthchecker)

if [ -z "$is_running" ]; then
    # if the application is not running, start it
    pm2 start npm --name "healthchecker" -- start
else
    # if the application is running, restart it
    pm2 restart healthchecker
fi
