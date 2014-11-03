#!/usr/bin/python
"""Calculates the Levenshtein distance of 2 strings"""
import sys

def printMatrix(m):
    print ' '
    for line in m:
        spTupel = ()
        breite = len(line)
        for column in line:
            spTupel = spTupel + (column, )
        print "%3i"*breite % spTupel

s1 = sys.argv[1]
s2 = sys.argv[2]

def levenshtein(s1, s2):
  l1 = len(s1)
  l2 = len(s2)

  matrix = [range(l1 + 1)] * (l2 + 1)
  for zz in range(l2 + 1):
    matrix[zz] = range(zz,zz + l1 + 1)
  for zz in range(0,l2):
    for sz in range(0,l1):
      if s1[sz] == s2[zz]:
        matrix[zz+1][sz+1] = min(matrix[zz+1][sz] + 1, matrix[zz][sz+1] + 1, matrix[zz][sz])
      else:
        matrix[zz+1][sz+1] = min(matrix[zz+1][sz] + 1, matrix[zz][sz+1] + 1, matrix[zz][sz] + 1)
  #print "That's the Levenshtein-Matrix:"
  #printMatrix(matrix)
  return matrix[l2][l1]
    
distance = levenshtein(s1, s2)		
print distance
