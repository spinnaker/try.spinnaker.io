#!/bin/bash

# cd into scripts folder, aka where this file is located
cd "${0%/*}"

rm -rf portieris
mkdir portieris 
cd portieris

# download latest portieris release 
curl -s https://api.github.com/repos/IBM/portieris/releases/latest \
| grep "portieris.*tgz" \
| cut -d : -f 2,3 \
| tr -d \" \
| wget -qi -

tar -xf portieris*
mv portieris/* .

sh ./gencerts