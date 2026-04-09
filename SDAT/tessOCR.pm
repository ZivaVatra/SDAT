#!/usr/bin/env perl
# vim: ts=4 noexpandtab ai
#
# Copyright 2026 Ziva-Vatra, Belgrade (www.ziva-vatra.com)
#
# Project Repository: https://github.com/ZivaVatra/SDAT
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
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA	02110-1301, USA.    #
# All rights reserved
# ============================================================================|
#
# Class conventions used:
#	- Understore prefix for private subroutines
#

### BEGIN Class ###
package SDAT::tessOCR;

use strict;
use File::Slurp qw(write_file read_file);

# Constructor options
# Format: "key" (type:default)	//comment
#	"tessOpts" (list)

sub new {
	_checkDeps();
	my ($class, $arg) = @_;
	my $self = bless($arg, $class);
	return $self;
}

sub _checkDeps {
	# Check if all the binaries we need are available
	my @deps = (
		"tesseract",
	);
	foreach(@deps) {
		die("\"$_\" not found in \$PATH, cannot continue\n") if system(
			"which","-s", $_
		);
	}
}

sub OCR {
	my $self = shift;
    my $inputImage = shift;
	# if a remnant from a previous run exists, remove
	unlink("$inputImage.txt") if (-e "$inputImage.txt");
    die("OCR failed: $!\n") if system(
		"tesseract",
		$inputImage,
		$inputImage, # tesseract auto-appends .txt
		@{$self->{tessOpts}}
	);
	my $text = read_file("$inputImage.txt");
	unlink("$inputImage.txt");
	return $text;
}

# Destructor
sub DESTROY {
	# N.B. We cannot delete the temp directory here because when we fork and
	# and the children end, the destructor is called and it deletes the tempDIR
	# before the rest of the program has finished executing, breaking everything.
}

1;  # End of file

