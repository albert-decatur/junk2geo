junk2geo
========

**Warning**

This is for patient people with very bad input data!
Many faster solutions exist which work very well on inputs that have rich context and are well formated.

These Bash scripts geocode your input TSV according to tre-agrep fuzzy text match with Geonames.
junk2geo's niche is extremely messy and brief text, especially multi-lingual / multi-character-encoded input, rife with HTML encoding or other junk.
It also lets you filter the output according to indicators like Double Metaphone and Levenshtein distance.
Your TSV input needs two columns: 

  1. ISO2(s) alpha codes related to the text
  2. text to geocode

We preserve the original text which was matched as well as the output geocoded placename, which is great for reviewing accuracy later.


Prerequisites
=============

* GNU parallel
* tre-agrep
* mawk

How To
======

```bash
sudo apt-get install parallel tre-agrep mawk
git clone URL
cd fuzz-geo/
chmod +x *.sh
./get_geonames.sh
./fuzzgeo.sh input.txt output.txt
./match_qa.sh output.txt output_qa.txt
./match_qa.sh output_qa.txt -l 3 -m 1 -s 4 -a > worthy_matches.txt
```

Use
============

Scripts are separated such that slow tasks can be run once, but faster tasks like filtering by quality metrics can be repeated easily and quickly.
GNU parallel allows junk2geo.sh to be run on an arbitrary number of hosts.
