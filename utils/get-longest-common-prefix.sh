#!/bin/sh

sed -e '$!{N;s/^\(.*\).*\n\1.*$/\1\n\1/;D;}'
