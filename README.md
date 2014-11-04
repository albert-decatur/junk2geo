junk2geo
========

These scripts geocode your input TSV according to tre-agrep fuzzy text match with GeoNames.
A GeoNames SQLite database is required, which you can get [here](https://github.com/albert-decatur/geonames2sqlite.git).

junk2geo's niche is extremely messy and brief text, especially multi-lingual / multi-character-encoded input, rife with HTML encoding or other junk.
It also lets you filter the output according to indicators like Double Metaphone and Levenshtein distance.
Your TSV input needs two columns: 

  1. ISO2 alpha codes related to the text
    1. If multiple ISO2s may apply then pipe separate them like so: IR|US|CN
    1. If no applicable ISO2 is know simply leave the column blank.
  2. input text to geocode

We preserve the original text which was matched as well as the output geocoded placename, which is great for reviewing accuracy later.
String metrics can be calculated with the script match_metrics.sh.

Some features include:

* choose whether to use GeoNames alternate names (non-English names)
* choose whether to filter by a stopword list
  * this applies to both the output matched text and the input GeoNames text
* choose whether to filter by length
  * this applies to both the output matched text and the input GeoNames text

Note that while junk2geo.sh **and** match_metrics.sh can tell you if a match was a stopword, 
and the length of the match, junk2geo.sh is **much** slower than match_metrics.sh.
Because both tools have these two features you can pursue these strategies:

* pass a short stopwords list to junk2geo.sh, and a huge one to match_metrics.sh
* restrict lengths to be greather than n characters for junk2geo.sh, but plot **all** the resulting lengths with match_metrics.sh

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
* moreutils
  * for mktemp and sponge
* wdiff
* [Levenshtein distance](https://github.com/albert-decatur/as-seen-online/blob/master/levenshtein.py) 
* [Double Metaphone](https://github.com/slacy/double-metaphone)

Why agrep **and** tre-agrep?  The first is very fast, and the second can show you the exact pattern that was matched.

How To
======

```bash
sudo apt-get install agrep tre-agrep mawk moreutils
# moreutils has a util called parallel, but this is not GNU parallel
sudo rm $(which parallel)
# to use the GNU parallel from this repo just use parallel-20121122/src/parallel
# however, you may have to compile from source.  for that see instructions below
sudo cp src/parallel /usr/bin/parallel
# get this repo
git clone https://github.com/albert-decatur/junk2geo.git
cd junk2geo/
# make scripts executable
chmod +x *.sh
# compile double metaphone algorithm in submodule
cd double-metaphone/
make
cd ..
./junk2geo.sh -g geonames/geonames_2014-10-02.sqlite -i test/test.tsv > output.tsv
./match_metrics.sh output.tsv > metrics.tsv
./match_metrics.sh metrics.tsv -l 3 -m 1 -s 4 -a > worthy_matches.tsv
```

To install GNU parallel from scratch:
```bash
wget -c http://ftp.gnu.org/gnu/parallel/parallel-20121122.tar.bz2
tar jxvf parallel-20121122.tar.bz2
cd parallel-20121122/
./configure && make && make install
# moreutils has a util called parallel, but this is not GNU parallel
sudo rm $(which parallel)
sudo cp src/parallel /usr/bin/parallel
```

Scripts are separated such that slow tasks can be run once, but faster tasks like filtering by quality metrics can be repeated easily and quickly.
GNU parallel allows junk2geo.sh to be run on an arbitrary number of hosts as long as the GeoName SQLite database and the input TSV are available on each.

Note that you can greatly speed up performance on repeatative datasets by finding only unique values that should matter to geocoding.
For example, if you start with a 2.7m record OECD CRS dataset, try taking unique values of just fields that have geocodeable information, and use this input to join back to the original after geocoding.

Cultivating a good stopword list is one of the best ways to improve accuracy.
The ideal stopword list would contain all the words that appear in your text, regardless of language and spelling, that are not placenames.
Of course, you don't want to make the stopword list enourmous (eg >1m records).

How it Works
============

junk2geo.sh

1. make a SQLite table of geonames for each unique combination of ISO2s found in the user provided TSV
2. make a body of text to geocode for each unique combination of ISO2s found in the user provided TSV
3. determine which is smaller - the geonames or the text to geocode
  1. multiply the number of doc terms by a large number, eg 500, because for every doc term many candidate geonames will be found by fuzzy text match
4. use the smaller set to search for matches in the larger set
  4. note that if the text to geocode is the small set, an intermediate set of geonames is made by searching for each input term in the appropriate geonames ISO2 table, using agrep for speed
5. use tre-agrep to get both the records that were matched and their character positions in those records
6. pull out the matched text and the geonames candidates for each ISO2 unique set
7. use the match text to join geonames candidates to each input record, and present this along with the geonames candidates

match_metrics.sh

1. use the output from junk2geo.sh to make a series of new fields with string metrics comparing the matched text and the geonames candidates
2. filter out geonames candidates according to poor performance in metrics of your choice (eg, sound does not match according to Double Metaphone)
3. remove duplicate geonames for the same place (eg a place that was matched in both Italian and Spanish should appear as a single match)

Notes
=====

The stopword list called 'google_ngrams.tsv'
is from Google N-grams English One Million.
The list is a sbuset according to these rules:

* only 1-grams were considered
* must be greater than 3 characters
* must have more than 10,000 matches since 1991

Acknowledgements
================

The Levenshtein distance script is by [Martin Schimmels](http://code.activestate.com/recipes/576874-levenshtein-distance/) and is under the [MIT License](http://opensource.org/licenses/MIT).
The Double Metaphone script is by [Steve Lacy](https://github.com/slacy/double-metaphone) and is under the [Artistic License](http://dev.perl.org/licenses/artistic.html).
