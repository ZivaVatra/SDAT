#!/usr/bin/env perl
# vim: ts=4 ai
# SDAT - Scanned document archival tool
#
#Copyright 2020 Ziva-Vatra, Belgrade
#(www.ziva-vatra.com, mail: info@ziva_vatra.com)
#
# Project URL: http://www.ziva-vatra.com/index.php?aid=71&id=U29mdHdhcmU=
# Project REPO: https://github.com/ZivaVatra/SDAT
#
#Licensed under the GNU GPL. Do not remove any information from this header
#(or the header itself). If you have modified this code, feel free to add your
#details below this (and by all means, mail me, I like to see what other people
#have done)
#
#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License (version 2)
#as published by the Free Software Foundation.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#
# This is a script for archival of Documents/Bills/Invoices/etc...
# It scans the page, runs OCR on the text, and saves the text to the comment field in the metadata
# This allows indexing engines (e.g. Desktop search) to know what text the document contains, allowing
# for easier searching, while keeping the original text+format as an image scan.
# It saves a PNG file into the $FINALDST folder

# Requirements:
#	tesseract (OCR)
#	sane-tools (SCANNING)
#	Exiv2 image metadata library (for adding text to comment field)
#	imageMagick tools (FORMAT CONVERSION)
#

use strict;
use File::Basename;
use lib "./";
use SDAT::core;
use FindBin;

my $OCRtype = shift or usage();
my $target = shift or usage();
our $OLLAMA_ENDPOINT = "http://localhost:11434/api/generate";

die("Can't find file\n") unless (-f $target);

if (-f "$FindBin::Bin/settings.pm") {
        require "$FindBin::Bin/settings.pm";
} 

my ($name, $path, $extension) = fileparse($target, qr/\.[^.]*/);
# Remove the leading dot and convert to all upper case
$extension =~ s/^.// if $extension;
$extension =~ tr/a-z/A-Z/;

# We use the extension of the input image to work out the output format (as it should match)

my @tessOpts = qw|-l eng|;
my $core = SDAT::core->new({
	tessOpts => \@tessOpts,
	filePattern => "reprocess",
	OCR => 1, # Enable OCR
	ollamaEndpoint => $OLLAMA_ENDPOINT,
	OCRtype => $OCRtype,
	outFormat => $extension,
	outDIR => $path  # We use the input path, to overwrite the original
});

if ($extension =~ m/pdf/i) {
	# unpack the PDF and get a list of images to process further
	$core->unpackPDF($target);
	my @images = glob("$core->{tempDIR}/$core->{filePattern}*.png");
	# We append the OCR text from each image into a single string
	my $OCRtext = "";
	foreach(@images) {
		print "$_\n";
		$OCRtext .= $core->OCR($_);
	}
	# We do not regenerate the PDF, but just add/replace the comment
	# field
	$core->addPDFcomment($target, $OCRtext);
} elsif ($extension =~ m/png/i) {
	my $text = $core->OCR($target);
	# We overwrite the input file, but only
	$core->_writeExif($target, $text);
} else {
	die("Extension $extension unknown, cannot continue!\n");
}

# Cleanup
$core->deleteTempDir();

sub usage {
	print(qq/Usage: $0 \$OCR_backend ( "tesseract" or "ollama" ) \$target_file \n/);
	exit 1;
}

