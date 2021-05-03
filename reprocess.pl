#!/usr/bin/perl -w
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

# Extra options for tesseract
our $TESSOPTS=" --tessdata-dir /usr/share/tesseract-ocr/4.00/tessdata/ -l eng ";

require "./lib/core.pm";

sub usage {
	die("Usage: $0 \$target_file\n");
}

my $target = shift or usage();

die("Can't find file\n") unless (-f $target);

ocrit($target, "/tmp/ocr_text", $TESSOPTS);
addComment("/tmp/ocr_text.txt", $target);
unlink("/tmp/ocr_text.txt");

