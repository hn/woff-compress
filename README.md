# woff-compress
woff-compress is a woff font file (re)compressor. It (re)compresses TableDirectoryEntry data with flag Z_BEST_COMPRESSION, removes private and metadata data blocks. The latter may conflict with your font vendor's license. Based on <http://www.w3.org/TR/WOFF/>.

Install Zopfli for best results. As there is no perl-zopfli (yet), you need the command line application.
