junk2geo
========

These scripts geocode your input TSV according to tre-agrep fuzzy text match with GeoNames.
A GeoNames SQLite database is required, which you can get [here](https://github.com/albert-decatur/geonames2sqlite.git).

junk2geo's niche is extremely messy and brief text, especially multi-lingual / multi-character-encoded input, rife with HTML encoding or other junk.
It also lets you filter the output according to indicators like Double Metaphone and Levenshtein distance.
Your TSV input needs two columns: 

  1. ISO2 alpha codes related to the text
    1. If multiple ISO2s may apply them pipe separate them like so: IR|US|CN
    1. If no applicable ISO2 is know simply leave the column blank.
  2. input text to geocode

We preserve the original text which was matched as well as the output geocoded placename, which is great for reviewing accuracy later.
String metrics can be calculated with the script match_metrics.sh.

**Warning**

junk2geo is for patient people with very bad input data!
Many faster solutions exist which work well on inputs that have rich context and are well formated:

* [TwoFishes](https://github.com/foursquare/twofishes)
* [CLAVIN](https://github.com/Berico-Technologies/CLAVIN)
* [geocodify](https://github.com/tmcw/geocodify)
* [geocoder](https://github.com/alexreisner/geocoder)


Prerequisites
=============

* GNU parallel
* agrep
* tre-agrep
* mawk

Why agrep **and** tre-agrep?  The first is very fast, and the second can show you the exact pattern that was matched.

How To
======

```bash
sudo apt-get install parallel tre-agrep mawk
git clone https://github.com/albert-decatur/junk2geo.git
cd junk2geo/
chmod +x *.sh
./junk2geo.sh input.tsv output.tsv
./match_metrics.sh output.tsv output_qa.tsv
./match_metrics.sh output_qa.tsv -l 3 -m 1 -s 4 -a > worthy_matches.tsv
```

Use
===

Scripts are separated such that slow tasks can be run once, but faster tasks like filtering by quality metrics can be repeated easily and quickly.
GNU parallel allows junk2geo.sh to be run on an arbitrary number of hosts.

Note that you can greatly speed up performance on repeatative datasets by finding only unique values that should matter to geocoding.
For example, if you start with a 2.7m record OECD CRS dataset, try taking unique values of just fields that have geocodeable information, and use this input to join back to the original after geocoding.

How it Works
============

1. make a SQLite table of geonames for each unique combination of ISO2s found in the user provided TSV
2. make a body of text to geocode for each unique combination of ISO2s found in the user provided TSV
3. determine which is smaller - the geonames or the text to geocode
4. use the smaller set to search for matches in the larger set
  4. note that if the text to geocode is the small set, an intermediate set of geonames is made by searching for each input term in the appropriate geonames ISO2 table
5. output geonames information for each input record, along with the text that used to determine the match

TODO:
junk2geo will always search for smaller sets in larger sets.
For example, if the text to geocode is very large and the set of possible placenames is small then we search for the placenames in the text.
However, if the text to geocode is small and the set of possible placenames is large ( for example when a list of countries is not known ) then we search for the text in the list of placenames.
