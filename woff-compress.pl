#!/usr/bin/perl
#
# woff-compress.pl -- Compresses .woff (1.0) font files
#
# (re)compresses TableDirectoryEntry data with flag Z_BEST_COMPRESSION,
# removes private and metadata data blocks. The latter may conflict
# with your font vendor's license. Based on http://www.w3.org/TR/WOFF/ .
#
# Install Zopfli for best results. As there is no perl-zopfli (yet),
# you need the command line application.
#
#
# (C) 2015-2016 Hajo Noerenberg
#
# http://www.noerenberg.de/
# https://github.com/hn/woff-compress
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3.0 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.txt>.
#

use strict;
use Getopt::Long;
use Fcntl qw(:flock);
use Compress::Zlib qw(uncompress);
use Compress::Zopfli::ZLIB qw(compress);

my $verbose=0;
my $overwrite=0;
my $iterations=50;

sub help {
  print "
  $0 [options] <input.woff|-> [output.woff|-]

  Options:
    -i, --iterations    Maximum trials (default: 50)
    -v, --verbose       Enable verbose mode (repeatable)
";
exit 1;
};

GetOptions(
	'--help' => \&help,
	'--verbose|v+' => sub { $verbose++ },
	'--iterations|i=i' => \$iterations,
);

my $f=$ARGV[0];
my $d=$ARGV[1]||$f;
$f=\*STDIN if $f eq '-';
$d=\*STDOUT if $d eq '-';

sub rb {
  my ($buf, $t);
  my ($p, $l) = @_;

  seek(IF, $p, 0) || die;
  read(IF, $buf, $l);
  $t=$buf;
  $t=~s/[^[:print:]]+/./g;;
  print "Reading " . sprintf("%6d", $l) . " bytes at offset " . sprintf("%7d", $p) . ": 0x" . sprintf("%-32s", unpack("H*", substr($buf, 0, 16))) . " (a '" . substr($t, 0, 16) . "') \n" if ($verbose>2);
  return $buf;
}

sub rl {
  my ($buf, $n);
  my ($p, $l) = @_;

  seek(IF, $p, 0) || die;
  read(IF, $buf, $l);
  $n=unpack("L>*", $buf);
  print "Reading " . sprintf("%6d", $l) . " bytes at offset " . sprintf("%7d", $p) . ": 0x" . sprintf("%-32s", unpack("H*",$buf)) . " (l " . $n . ")\n" if ($verbose>2);
  return $n;
}

sub rs {
  my ($buf, $n);
  my ($p, $l) = @_;

  seek(IF, $p, 0) || die;
  read(IF, $buf, $l);
  $n=unpack("S>*", $buf);
  print "Reading " . sprintf("%6d", $l) . " bytes at offset " . sprintf("%7d", $p) . ": 0x" . sprintf("%-32s", unpack("H*",$buf)) . " (s " . $n . ")\n" if ($verbose>2);
  return $n;
}

$overwrite = $^O =~ /win/i ? lc $f eq lc $d : $f eq $d;
open (IF, "<$f") || die ("Unable to open input file '$f': " . $!);
flock(IF, LOCK_SH); binmode(IF);
$d .= '.tmp' if $overwrite;
open (OF, ">$d") || die ("Unable to open output '$d': " . $!);
flock(OF, LOCK_EX); binmode(OF);
my $ofpos=0;

# WOFFHeader
#  0 UInt32	signature	0x774F4646 'wOFF'
#  4 UInt32	flavor		The "sfnt version" of the original file: 0x00010000 for TrueType flavored fonts or 0x4F54544F 'OTTO' for CFF flavored fonts.
#  8 UInt32	length		Total size of the WOFF file.
# 12 UInt16	numTables	Number of entries in directory of font tables.
# 14 UInt16	reserved	Reserved, must be set to zero.
# 16 UInt32	totalSfntSize	Total size needed for the uncompressed font data, including the sfnt header, directory, and tables.
# 20 UInt16	majorVersion	Major version of the WOFF font, not necessarily the major version of the original sfnt font.
# 22 UInt16	minorVersion	Minor version of the WOFF font, not necessarily the minor version of the original sfnt font.
# 24 UInt32	metaOffset	Offset to metadata block, from beginning of WOFF file; zero if no metadata block is present.
# 28 UInt32	metaLength	Length of compressed metadata block; zero if no metadata block is present.
# 32 UInt32	metaOrigLength	Uncompressed size of metadata block; zero if no metadata block is present.
# 36 UInt32	privOffset	Offset to private data block, from beginning of WOFF file; zero if no private data block is present.
# 40 UInt32	privLength	Length of private data block; zero if no private data block is present.

die ("Error: Invalid magic\n") if (rb(0, 4) ne "wOFF");

my $WOFFHeader_numTables = rs(12, 2);

print "Number of TableDirectory Entries: " . $WOFFHeader_numTables . "\n" if ($verbose>1);

# copy header and TableDirectory
$ofpos=44+5*4*$WOFFHeader_numTables;
print OF rb(0, $ofpos);

my @TableDirFix;

for (my $i=0; $i<$WOFFHeader_numTables; $i++) {

  print "Reading TableDirectoryEntry $i\n" if ($verbose>1);

  # WOFF TableDirectoryEntry
  #  0 UInt32	tag		4-byte sfnt table identifier.
  #  4 UInt32	offset		Offset to the data, from beginning of WOFF file.
  #  8 UInt32	compLength	Length of the compressed data, excluding padding.
  # 12 UInt32	origLength	Length of the uncompressed table, excluding padding.
  # 14 UInt32	origChecksum	Checksum of the uncompressed table.

  my $WOFFTableDirectoryEntry_offset     = rl(44+ 4+($i*5*4), 4);
  my $WOFFTableDirectoryEntry_compLength = rl(44+ 8+($i*5*4), 4);
  my $WOFFTableDirectoryEntry_origLength = rl(44+12+($i*5*4), 4);

  my $buffin = rb($WOFFTableDirectoryEntry_offset,  $WOFFTableDirectoryEntry_compLength);
  my $buffout;

  if ($WOFFTableDirectoryEntry_compLength < $WOFFTableDirectoryEntry_origLength) {
    print "Uncompressing TableDirectoryEntry $i data (compLength: $WOFFTableDirectoryEntry_compLength, origLength: $WOFFTableDirectoryEntry_origLength)\n" if ($verbose>1);
    $buffin = uncompress($buffin);
  }

  if (length($buffin) != $WOFFTableDirectoryEntry_origLength) {
    die("WOFF TableDirectoryEntry $i broken (length " . length($buffin) . " mismatches $WOFFTableDirectoryEntry_origLength)");
  }

  $buffout = compress($buffin, { iterations => $iterations, blocksplitting => 0 });

  printf "Compressing TableDirectoryEntry %3d data (compLength: %6d, origLength: %6d)\n", $i, length($buffout), $WOFFTableDirectoryEntry_origLength if ($verbose>1);

  if (length($buffout) >= length($buffin)) {
    $buffout = $buffin;
  }

  push @TableDirFix, pack("L>*", $ofpos, length($buffout));

  print OF $buffout;
  my $pad = 4-length($buffout)%4;
  $pad = 0 if ($pad>3);
  print OF "\x00"x$pad;
  $ofpos += $pad+length($buffout);

}

# set correct offset and length info
for (my $i=$WOFFHeader_numTables; $i>0; $i--) {
  seek(OF, 44+4+(($i-1)*5*4), 0) || die;
  print OF pop(@TableDirFix);
}

# set correct file length
seek(OF, 8, 0) || die;
print OF pack("L>*", $ofpos);

# zero private and metadata data block head info
seek(OF, 24, 0) || die;
print OF "\x00"x20;

close (OF);
close (IF);

if ($verbose) {
  printf "Original file size: %d, compressed size: %d (%0.2f%% reduction)\n", ( -s $f ), $ofpos, 100*(1-($ofpos / -s $f));
}

rename($d, $f) if ($overwrite)