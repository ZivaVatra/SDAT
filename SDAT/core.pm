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
# - Underscore prefix for private subroutines
#

### BEGIN Class ###
use strict;
use Forks::Super;
$Forks::Super::ON_BUSY = 'block';
package SDAT::core;
use Data::GUID;
use File::Path qw(make_path rmtree);
use File::Basename "fileparse";
use File::Copy qw(move);
use File::Slurp qw(write_file read_file);

# Constructor options
# Format: "key" (type:default)	//comment
#	"resolution" (integer)
#	"outDIR" (string)
#	"filePattern" (string)
#	"scanOpts" (list)
#	"device" (string)
#	"tessOpts" (list)
#	"ollamaEndpoint" (string)
#	"OCRtype" (string)
#	"OCR" (bool)
#	"enableADF" (bool:0)
#	"tmpDIR" (string) // The base temporary directory (default /tmp/SDAT)
#	"duplex" (bool:1) //this only applies if there is an Auto document feeder
#	"outFormat" (string:[png/pdf]) // we now limit to only these two

sub new {
	_checkDeps();
	my ($class, $arg) = @_;
	my $self = bless($arg, $class);

	die("OCR enabled but no OCR backend selected\n") if (($self->{OCR} == 1) and (!$self->{OCRtype}));
	$self->{tmpDIR} = "/tmp/SDAT" unless ($self->{tmpDIR});
	my $GUID = Data::GUID->new()->as_string();
	$self->{tempDIR} = "$self->{tmpDIR}/$GUID";
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
		"magick",
		"exiv2"
	);
	foreach(@deps) {
		die("\"$_\" not found in \$PATH, cannot continue\n") if system(
			"which","-s", $_
		);
	}
}

sub unpackPDF_TEST {
	# This is here to test against the native perl code below.in case of issues.
	my $self = shift;
	my $pdfFile = shift;

	die("Could not extract PDF pages: $!\n") if system(
		"magick", "-density", 400, "-quality", 100, $pdfFile, "$self->{tempDIR}/$self->{filePattern}-%04d.png");
}

sub unpackPDF {
	# Despite my best efforts, the below keeps extracting tiny thumbnail 
	# versions of the PDF, rather than the actual high resolution pages.
	# For the moment I've given up and am just using the command line version
	# to unpack the PDF (see above)

	# This subroutine unpacks a PDF file into images following the internal
	# directory structure, so we can OCR it. Used primarily for reprocessing
	# existing scans
	my $self = shift;
	my $pdfFile = shift;
	
	my $im = Image::Magick->new();
	
	$im->Set('define:pdf:use-cropbox=true');
	# Read the entire PDF to get its properties
	my $error = $im->Read($pdfFile);
	if ($error) {
		die "Error reading PDF file: $error\n";
	}

	# We tried to use the original density from the PDF, but it was buggy, resulting
	# in too small output for OCR, so we hard coded 400DPI for density, which seems
	# to be high enough for good re-OCR-ing of the scan.
	my $density = '400'; 

	my $width = $im->Get('width');
	my $height = $im->Get('height');

	if ($ENV{DEBUG} == 1) {
		print "Processed PDF Density DPI: $density\n";
		my $page_size = $im->Get('page');
		print "PDF Width: $width, Height: $height, Page size: $page_size\n";
	}

	my $page_count = $im->Get('pages');
	print "We have $page_count pages in the PDF file.\n" if ($ENV{DEBUG} == 1);
	# If we got nothing for $page_count, try to use image count instead
	if (!$page_count) {
		print "No pages found! Trying to use image count instead... " if ($ENV{DEBUG} == 1);
		$page_count = scalar(@$im);
		print "We have $page_count images in the PDF file.\n" if ($ENV{DEBUG} == 1);
	}
	# If we can't find page count either way, die (rather than generate incorrect PDF
	# output)
	die("Could not get number of image or pages in PDF! (got: $page_count)\n") if !$page_count;

	# Process each page, as its off by on (start 0) subtract from
	# $page_count
	for my $page_num (0..$page_count - 1) {
		my $page_image = Image::Magick->new();
		$page_image->Set('density' => $density);
		$page_image->Set('define:pdf:use-cropbox=true');
		$page_image->Set('define:pdf:flatten=true');

		print "Reading in \"${pdfFile}[${page_num}]\"\n" if ($ENV{DEBUG} == 1);
		my $page_error = $page_image->Read("${pdfFile}[${page_num}]");
		if ($error) {
			die "Error reading PDF page $page_num: $error\n";
		}

		if ($ENV{DEBUG} == 1) {
			my $width = $page_image->Get('width');
			my $height = $page_image->Get('height');
			my $page_size = $page_image->Get('page');
			print "Image Width: $width, Height: $height, Page size: $page_size\n";
		}

		$page_image->Set(page => $page_num);
		my $filename = sprintf("%s/%s_%02d.png", 
							  $self->{tempDIR}, 
							  $self->{filePattern}, 
							  $page_num);
		
		my $write_error = $page_image->Write(filename => $filename);
		if ($write_error) {
			warn "Error writing image $filename: $write_error";
		}
		undef $page_image;  # Free the object
	}
	# Final cleanup
	undef $im;
	
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
	my $outPDF = shift;
	my @files = glob("$self->{tempDIR}/$self->{filePattern}*.png");
#	if ($self->{OCR} == 1) {
#		Forks::Super::pmap { $self->OCR($_) } {timeout => 120}, @files;
#	}
#	Forks::Super::waitall();

	if ($self->{outFormat} =~ m/PDF/i) {
		my @txtFiles = glob("$self->{tempDIR}/$self->{filePattern}*.txt");

		# We read in and concatinate all the text files for PDF
		my $text = "";
		foreach(@txtFiles) {
			$text .= read_file($_);
		}

		return $self->mergePDF(\@files, $text, $outPDF);
	} else {
		Forks::Super::pmap { 
			my $text = read_file("$_.txt");
			print "Writing exif for $_ (from $_.txt)\n" if ($ENV{DEBUG} == 1);
			$self->_writeExif($_, $text);
		} {timeout => 120}, @files;
		Forks::Super::waitall();

		foreach(@files) {
			my ($filename, $dirs, $suffix) = fileparse($_);
			my $outPath = "$self->{outDIR}/$filename";
			print "move $_ to $outPath\n";
			File::Copy::move($_,$outPath);
		}
		return 1;
	}
}

sub mergePDF {

	my $self = shift;
	my $files = shift;
	my $text = shift;
	my $outPDF = shift or die("No output filename given!");

	# Check if we have the pdf extension already,and add it if not
	chomp $outPDF;
	if ($outPDF !~ m/\.pdf$/) {
		$outPDF .= ".pdf";
	}
	if ($self->{OCR} == 1) {
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
		"-compress", "lossless",
		"-density", $self->{resolution},
		$outPDF);

#	"$self->{outDIR}/$self->{filePattern}.pdf");

	$self->addPDFcomment($outPDF, $text);
	return $outPDF;
}

sub addPDFcomment {
	# Unlike images, where each image has its OCR'd text in its EXIF header,
	# PDFs are multipage and we can't set a comment per page, so what we have
	# to do is load up all the OCR text files for each page, concatenate them
	# and set the entire thing as a comment. I guess I will find out if the
	# PDF spec sets a limit on comment size...

	my $self = shift;
	my $outPDF = shift;
	my $text = shift;

	# Update the keywords
	#my $keywords = $text;
	#$keywords =~ s/\n/ /g;	#can't have newlines in keywords
	#die("Failed to update keywords on PDF\n") if system(
	#		"magick",
	#		$outPDF, "-set", "pdf:keywords", $keyword
	#unlink($outPDF);
	#rename("$outPDF.new", $outPDF);

	# From what I can see, PDF does not have the ability to set a comment field,
	# however the PDF standard does support comments, you just have to prefix '%'
	# Ideally done at the start of the PDF, but before the '%PDF-1.3' definition
	my $pdfData;
	print "Opening PDF file $outPDF to read in data\n" if ($ENV{DEBUG} == 1);
	open(FD, $outPDF) or die("Failed to open PDF for reading: $!");
	$pdfData = <FD>; # First line is our PDF definition
	while(<FD>) {
		$pdfData .= $_; #Load the rest as is

		# Until we reach the "%%EOF" line, anything after that line
		# is a previous comment to be ignored
		if (m/%%EOF/) {
			last;
		}
	}
	print "Added PDF comment with our OCR'd data.\n" if ($ENV{DEBUG} == 1);;
	$pdfData .= "%$text\n"; # We add our text as a PDF comment after EOF
	close(FD);
	# Now write the data back
	open(FD, ">$outPDF") or die("Failed to open PDF for write: $!");
	print(FD $pdfData);
	close(FD);
	return 1;
}

sub OCR {
	# This will OCR a given image file and return the text. 
	# Only image files supported
	my $self = shift;
	my $inputImage = shift;
	# Optional file to write output to, would return text otherwise. 
	# Will skip OCR if file exists already
	my $outfile = shift;  

	if ($self->{OCRtype} =~ m/tesseract/) {
		use SDAT::tessOCR;
		my $inst = SDAT::tessOCR->new({
			tessOpts => $self->{tessOpts}
		});
		if ($outfile) {
			return 1 if (-f $outfile);
			my $text = $inst->OCR($inputImage);
			write_file($outfile, $text);
			return 1;
		} 
		return $inst->OCR($inputImage);
	} elsif ($self->{OCRtype} =~ m/ollama/) {
		use SDAT::ollamaOCR;
		my $inst = SDAT::ollamaOCR->new({
			endpoint => $self->{ollamaEndpoint}
		});
		if ($outfile) {
			return 1 if (-f $outfile);
			my $text = $inst->OCR($inputImage);
			write_file($outfile, $text);
			return 1;
		} 

		return $inst->OCR($inputImage);

	} else {
		die("OCR type '$self->{OCRtype}' not recognised.\n");
	}
}

sub _writeExif {
	my $self = shift;
	my $file = shift;
	my $text = shift;

	if ($self->{OCR} == 1) {
		# If despite OCR, we have no data, we update the text to indicate this
		if ($text eq "") {
			$text = "[NO OCR DATA captured]";
		}
	} else {
		print "OCR disabled, skipping.\n";
		$text = "[OCR disabled]";
	}
	die("EXIF write failed: $!") if system(
		"exiv2", "-M",
		qq/set Exif.Photo.UserComment charset=Unicode $text/,
		$file
	);
}

sub deleteTempDir {
	my $self = shift;
	if ($ENV{DEBUG} == 1) {
		print "Preserving $self->{tempDIR} for debugging.\n";
	} else {
		File::Path::rmtree($self->{tempDIR});
	}
}

# Destructor
sub DESTROY {
	# N.B. We cannot delete the temp directory here because when we fork and
	# and the children end, the destructor is called and it deletes the tempDIR
	# before the rest of the program has finished executing, breaking everything.
}



1; # End of file

