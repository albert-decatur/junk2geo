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
* tre-agrep
* mawk


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
============

Scripts are separated such that slow tasks can be run once, but faster tasks like filtering by quality metrics can be repeated easily and quickly.
GNU parallel allows junk2geo.sh to be run on an arbitrary number of hosts.
