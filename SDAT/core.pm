#!/usr/bin/env perl
# vim: ts=4 noexpandtab ai
#
# File Created: Mon Apr 28 14:06:04 CEST 2025
# Copyright 2025 Ziva-Vatra, Belgrade (www.ziva-vatra.com)
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
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA	02110-1301, USA.	#
# All rights reserved
# ============================================================================|
#
# Class conventions used:
#	- Understore prefix for private subroutines
#

### BEGIN Class ###
use strict;
use Forks::Super;
$Forks::Super::ON_BUSY = 'block';
use Data::GUID;
use File::Path qw(make_path rmtree);
use File::Copy qw(move);
use File::Slurp qw(write_file read_file);
package SDAT::core;

# Constructor options
# Format: "key" (type:default)	//comment
#	"resolution" (integer)
#	"outDIR" (string)
#	"filePattern" (string)
#	"scanOpts" (list)
#	"device" (string)
#	"tessOpts" (list)
#	"OCRtype" (string)
#	"OCR" (bool)
#	"enableADF" (bool:0)
#	"duplex" (bool:1) //this only applies if there is an Auto document feeder
#	"outFormat" (string:[png/pdf]) // we now limit to only these two

sub new {
	_checkDeps();
	my ($class, $arg) = @_;
	my $self = bless($arg, $class);

	my $GUID = Data::GUID->new()->as_string();
	$self->{tempDIR} = "/tmp/SDAT/$GUID";
	File::Path::make_path($self->{tempDIR}) unless (-d $self->{tempDIR});
	File::Path::make_path($self->{outDIR}) unless (-d $self->{outDIR});
	die("Output format $self->{outFormat} not valid, only PNG and PDF supported\n") unless (
		$self->{outFormat} =~ m/(PDF|PNG)/i
	);

	return $self;
}

sub _checkDeps {
	# Check if all the binaries we need are available
	my @deps = (
		"scanimage",
		"tesseract",
		"magick",
		"img2pdf",
		"exiv2"
	);
	foreach(@deps) {
		die("\"$_\" not found in \$PATH, cannot continue\n") if system(
			"which","-s", $_
		);
	}
}

sub unpackPDF {
	""" This subroutine unpacks a PDF file into images following the internal
	directory structure, so we can OCR it. Used primarily for reprocessing
	existing scans """
	my $self = shift;
	my $pdfFile = shift;
	
	my $im = Image::Magick->new();
	
	# Read the entire PDF to get its properties
	my $error = $im->Read($pdfFile);
	if ($error) {
		die "Error reading PDF file: $error\n";
	}
	# Get the original PDF density/resolution, or fallback to 300dpi
	# and we set it for extraction
	my $density = $im->Get('density');
	$density = '300' if !$density; 
	$im->Set(density => $density);
	
	my $page_count = $im->Get('pages');
	$page_count = 1 if !$page_count; # it is a single page pdf

	# Process each page
	for my $page_num (1..$page_count) {
		# Create a copy of the image for this page matching
		# the PDF original density
		my $page_image = Image::Magick->new();
		$page_image->Set(density => $density);
		
		# Set the page to extract (0-indexed)
		$page_image->Set(page => $page_num - 1);
		
		my $error = $page_image->Read($pdfFile);
		if ($error) {
			warn "Error reading page $page_num: $error";
			next;
		}
		my $filename = sprintf("%s/%s_%02d.png", 
							  $self->{tempDIR}, 
							  $self->{filePattern}, 
							  $page_num);
		
		my $write_error = $page_image->Write(filename => $filename);
		if ($write_error) {
			warn "Error writing image $filename: $write_error";
		}
		$page_image->Destroy();
	}
	# Final cleanup
	$image->Destroy();
	
	return 1;  # Success
}
sub scan {
	my $self = shift;
	if ($self->{enableADF} == 1) {
		push(@{$self->{scanOpts}}, "--source", "ADF Duplex");
	}

	die("Failed to scan, got error: $!\n") if system(
		"scanimage", "-v", "-p", "--format=png",
		"-d", $self->{device},
		"--resolution", $self->{resolution}
		, @{$self->{scanOpts}},
		"--batch=$self->{tempDIR}/$self->{filePattern}_%02d.png"
	);
} 

sub writeFormatBatch {
	my $self = shift;
	my @files = glob("$self->{tempDIR}/$self->{filePattern}*.png");

	if ($self->{OCR} == 1) {
		Forks::Super::pmap { $self->OCR($_) } {timeout => 120}, @files;
	}
	Forks::Super::waitall();

	if ($self->{outFormat} =~ m/PDF/i) {
		return $self->mergePDF(\@files);
	} else {
		Forks::Super::pmap { 
			$self->_writeExif($_);
		} {timeout => 120}, @files;
		Forks::Super::waitall();
		foreach(@files) {
			my $outName = $_;
			$outName =~ s/$self->{tempDIR}//g;
			print "move $_ to $self->{outDIR}/$outName\n";
			File::Copy::move($_,"$self->{outDIR}/$outName");
		if ($!{EINTR}) {
				# Sometimes we get interrupted system calls, but the files is moved
				# anyway, so we check to see if the file exists at destination
				# before retrying
				if ( not -f "$self->{outDIR}/$outName" ) {
				warn "File move interrupted, retrying...\n";
					push(@files, $_); # re-add the failed file to the bottom of list
				}
			} else {
				die("Failed to move file '$_': $!");
			}
		}
		return 1;
	/
i


sub mergePDF {
	# Unlike images, where each image has its OCR'd text in its EXIF header, PDFs are multipage
	# and we can't set a comment per page, so what we have to do is load up all the OCR text files
	# for each page, concatenate them and set the entire thing as a comment. I guess I will find out
	# if the PDF spec sets a limit on comment size...

	my $text = "";
	my $self = shift;
	my $files = shift;
	if ($self->{OCR} == 1) {
		foreach my $file (@{$files}) {
			print "mergePDF: $file\n";
			my $textFile = "$file.txt";
			warn("Unable to find OCR text for '$file'! Cannot add to PDF.") unless (-f $textFile);
			open(FD, $textFile);
			while(<FD>){
				chomp;
				$text .= "$_ ";
			}
			close(FD);
		}
		# If despite OCR, we have no data, we update the text to indicate this
		if ($text eq "") {
			$text = "NO OCR DATA captured";
		}
	} else {
		print "OCR disabled, skipping.\n";
		$text = "OCR disabled";
	}

	foreach(@{$files}) {
		print "merging file: $_\n";
	}
	die("Failed to create PDF: $!") if system(
		"magick", 
		@{$files},
		"-define", q~pdf:Producer="SDAT - https://github.com/ZivaVatra/SDAT"~,
		"-define", q~pdf:Author="SDAT - https://github.com/ZivaVatra/SDAT"~,
		"-define", qq/pdf:Title="$self->{filePattern}"/,
		"-define", qq/pdf:Keywords="$text"/,
		"-compress", "lossless",
		"-density", $self->{resolution},
		"$self->{outDIR}/$self->{filePattern}.pdf");

	# From what I can see, PDF does not have the ability to set a comment field,
	# however the PDF standard does support comments, you just have to prefix '%'
	# Ideally done at the start of the PDF, but before the '%PDF-1.3' definition
	my $pdfData;
	open(FD, "$self->{outDIR}/$self->{filePattern}.pdf") or die("Failed to open PDF for read: $!");
	$pdfData = <FD>; # First line is our PDF definition
	while(<FD>) {
		$pdfData .= $_; #Load the rest as is
	};
	$pdfData .= "%$text\n"; # We add our text as a single line PDF comment after EOF
	close(FD);
	# Now write the data back
	open(FD, ">$self->{outDIR}/$self->{filePattern}.pdf") or die("Failed to open PDF for write: $!");
	print(FD $pdfData);
	close(FD);
	return 1;
}

sub OCR {
	""" This will OCR a given image file, and return the text. Only image files supported """
	my $self = shift;
	my $inputImage = shift;
	my $text = "";

	if ($self->{OCRtype} == "tesseract") {
		use SDAT::tessOCR;
		my $inst = SDAT::tessOCR->new({
			tessOpts => $self->{tessOpts}
		});
		return $inst->tessOCR($inputImage);
	} elsif ($self->{OCRtype} == "ollama") {
		die("Please set ollamaENDPOINT environment variable!\n") unless ($ENV{ollamaENDPOINT});
		use SDAT::ollamaOCR;
		$inst = SDAT::ollamaOCR->new({
			endpoint => $ENV{ollamaENDPOINT}
		});
		return $inst->OCR($inputImage);

	} else {
		die("OCR type '$self->{OCRtype}' not recognised.\n");
	}
}

sub _writeExif {
	my $self = shift;
	my $file = shift;
	my $text = "";

	if ($self->{OCR} == 1) {
		my $textFile = "$file.txt";
		warn("Unable to find OCR text for '$file'! Cannot add to Exif data.") unless (-f $textFile);
		$text = read_file($textFile);
		# If despite OCR, we have no data, we update the text to indicate this
		if ($text eq "") {
			$text = "NO OCR DATA captured";
		}
	} else {
		print "OCR disabled, skipping.\n";
		$text = "OCR disabled";
	}

	die("EXIT write failed: $!") if system(
		"exiv2", "-M",
		qq/set Exif.Photo.UserComment charset=Unicode $text/,
		$file
	);
}

sub deleteTempDir {
	my $self = shift;
	File::Path::rmtree($self->{tempDIR});
}

# Destructor
sub DESTROY {
	# N.B. We cannot delete the temp directory here because when we fork and
	# and the children end, the destructor is called and it deletes the tempDIR
	# before the rest of the program has finished executing, breaking everything.
}



1;	# End of file

