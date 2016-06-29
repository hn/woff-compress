# woff-compress
woff-compress is a woff font file compressor. It (re)compresses TableDirectoryEntry data with flag Z_BEST_COMPRESSION or Zopfli, and removes private and metadata data blocks. The latter may conflict with your font vendor's license.

Install Zopfli for best results. As there is no perl-zopfli (yet), you need the command line application.
