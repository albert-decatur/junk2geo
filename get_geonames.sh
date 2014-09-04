#!/bin/bash

# download Geonames' allCountries.txt to geonames/, if you haven't already

if [[ -z $( find geonames/ -maxdepth 1 -type f -iregex ".*allCountries.txt$" ) ]]; then
	cd geonames/
	wget -c http://download.geonames.org/export/dump/allCountries.zip
	unzip allCountries.zip
	cd geonames/
	rm allCountries.zip
else
	echo -e "Geonames allCountries.txt is already under the geonames/ directory!\nIf this is not the right file, remove it and run this script again."
fi
