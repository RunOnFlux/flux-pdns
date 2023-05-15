#!/bin/bash

# Check if pm2 is installed
if ! [ -x "$(command -v pm2)" ]; then
  echo 'pm2 is not installed. Installing now...'
  npm install pm2@latest -g
fi

# Navigate to your project directory (replace with your actual directory)
cd /path/to/your/project

# Start your application with pm2
pm2 start npm --name "healthchecker" -- start