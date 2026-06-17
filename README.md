## Please see the official version at lz2hv.org/mshv

This is a clone/fork of [MSHV Amateur Radio Software](http://lz2hv.org/mshv) by LZ2HV ([sourceforge link](https://sourceforge.net/projects/mshv/)) 

Please visit [the official site](http://lz2hv.org/mshv) for the most up-to-date source code and downloads.

MSHV is multiplatform software designed for use by amateur radio afficinados. It supports many radio modes: MSK JTMS FSK ISCAT JT6M FT8/4/2 JT65 PI4 Q65. It builds on the open source work of Joe Taylor (K1JT), Steve Franke (K9AN) and many others.

## Why this fork

This fork is designed to lift a couple of the restrictions present in the main project, and add a couple features:
 - Better N3FJP logging compatability.  (Band & Mode updating, Dupe Coloring, etc)
 - Allow autosequence CQ mode when in contests.  (Remember, check if the contest allows this)
 - Feature to periodically call another "CQ __" station while calling "CQ __" yourself.
 - Option to grey out lines for duplicates
 - Option to 'Blacklist" certain stations to hide them from the decode list, and never automatically respond to them.
 - "Pounce" mode to automatically respond to certain messages.  (calls to you even if you do not have transmit enabled)

This fork was designed for personal use, and is not made with any expectation to be used by anyone else.