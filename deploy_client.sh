#!/bin/bash

# pull to make sure you have the newest version
git pull

# backup the previous build, just in case the build fails
# also delete the previous 
mv build/ build-old/

# delete the old build cause idk if godot reuses it if it already exists
rm -rf build/

# rebuild the web templates
./export_web.sh

# start docker containers and force rebuilding and recreation
docker compose up -d --build --force-recreate

echo "Redeployed the client"
