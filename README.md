# SDAT - Scanned document archival tool

## Introduction:

SDAT started off as a Bash script sometime before 2006 to handle archival of my growing collection of documents/bills/invoices/etc... It was publicly released as Open Source around 2013 by explicit request, as it turned out there was no similar software available at the time and other people didn't want to have to "reinvent the wheel". Since then I've kept using it for archiving my paperwork in a searchable way, while also making improvements as and when needed.

Over the years the software has evolved to the current state, where it is Perl based and support both tesseract and machine learning (via ollama RPC) OCR backends.

The problem that I had with archiving documents is that I could either archive the scans as images (which are not text searchable) or as OCRed text, which is searchable but could contain OCR errors (plus you lose the formatting and style of the original document).

 What I wanted was the ability to do both, and from that came the idea of storing the OCR text in the container metadata (either PNG image or PDF). So that is what SDAT does. It is an automated system that scans pages, runs OCR on the text, and saves the text in the metadata of the container.

This allows indexing engines (e.g. Desktop search) to know what text the document contains, allowing for easier searching, while keeping the original text+format as an image scan in case you ever need to reproduce a pixel-original copy.


### Requirements:

The stuff in "Core" is required for the system to run. Beyond that you can choose one or both of the OCR backends, each has its own requirements.

#### Core

- perl
- sane
- exiv2  # image metadata library
- imagemagick
- The following CPAN modules
    - Data::GUID
    - Forks::Super
    - Image::Magick
    - File::Slurp

#### To use tesseract OCR

- tesseract

#### To use ollama RPC backend (ML Based OCR)

- ollama instance configured with your ML model of choice (I use glm-ocr:latest) and RPC running
- The following CPAN modules
    - MIME::Base64
    - LWP::UserAgent
    - JSON

## Usage:

There two entry points in this software package.  For scanning the main entry point is the "SDAT.pl" program. If you want to process an existing image or PDF you would use the "reprocess.pl" program.

### Settings

In version4 there is a "settings.pm" file, that is used for global settings. If this file is blank or non existant than hard coded defaults will be used.

Here is an example which overrides the default scan DPI, ollama RPC endpoint as well as the temporary directory (so you can use something other than "/tmp/SDAT" if you wanted to).:
`
our $SCAN_DPI=150;
our $OLLAMA_ENDPOINT="http://localhost:11434/api/generate";
our $TEMP_DIR="/tmp/SDAT/";

1; # Required 
`


Any settings in later configuration files will override the settings file. So for example if a config file has a higher $SCAN_DPI defined, it will override the above setting.



### Debug mode

if you ever want to run any of the below in debug mode (i.e. very verbose output), just set the "DEBUG" environment variable to "1" before running.


### Reprocess (OCR-ing exsting files)

If run without arguments you will see the following:

`
$#: ./reprocess.pl
    Usage: ./reprocess.pl $OCR_backend ( "tesseract" or "ollama" ) $target_file 
`

Its a rather simple program. You give it the $target_file and which of the two OCR backends you want to use. It will then re-OCR the file and update the original with new OCR data. It accepts either PNG or PDF files.  You don't necessarily have to use files that were scanned by SDAT for this. If tags don't exist it will create them, if they do exist it will overwrite them with the new OCR data.

Note: This script works "in-place", meaning your original target file is overwritten. It also just updates the metadata, it does not re-process the image/PDF. If you are converting important files best to make a back-up first.



### SDAT (scanning)
If run without arguments you will see the following:

`
$#: ./SDAT.pl 
    Usage: ./SDAT.pl $configuration_file $scanner_file $target_folder $target_scan_filename
`

The `$scanner_file` is what holds your device ID, as well as any extra options you want to add to your scanner. Each scanner has variations in behaviour and features, which can be defined here.

The `$configuration_file` is a configuration file for your job. For more information for the kind of things you can define in your job.

Please see "Configuration" section for more details of the above.

`$output_folder` is the target where your files will be saved, while `$target_scan_filename` is the name of the file. If you only scan one file without ADF, this will just end up being `$target_scan_filename.png`. If you are using an ADF scanner with multiple scanned pages, then each scan will be separate file, with the format `$target_scan_filename_$02d`. For example, running:

```
./SDAT_ADF.pl ./scanners/fujitsu_snapscan.scanner ./configs/archive.conf /storage/backups/scanned_documents/2020/ energy_bill
```
Will use my Fujistu ADF scanner to scan all the pages in the tray, following the "archive" configuration, which is a high quality archival PNG store, with OCR metadata. When done, the output should look like this:
```
  /storage/backups/scanned_documents/2020/energy_bill_01.png
  /storage/backups/scanned_documents/2020/energy_bill_02.png
  /storage/backups/scanned_documents/2020/energy_bill_03.png
  /storage/backups/scanned_documents/2020/energy_bill_04.png
```
In this case, it is a two page document, double sided, so we end up with 4 numbered pages in total. 
If however you select to have PDF output, then single and multi-page is treated the same, and you get a single `$target_scan_filename.pdf` in your output directory with all the pages within it (and all the OCRed text from the pages concatenated in the metadata).

When ADF is supported, SDAT will scan each page until the tray is empty. While doing this, in the background it will start the process of OCR and conversion. Once the scanning is done, the executable will wait until all processing child process are done before the final write to the output directory.

## Configuration

### Scanner configuration file ##

Each scanner is different so to support multiple scanners, including a computer with multiple scanners attached, the concept of "scanner definition" files were created. These allow you to pass a specific scanner configuration to SDAT, along with the scanner ID. I have included the definition files for my two scanners, but feel free to submit your own.
The configuration looks like this:
```
push @EXTRAOPTS, qw/--ald=no --df-action Stop --swdeskew=no --swcrop=no/;
$DEVICE="fujitsu:ScanSnap S500:14658";
$HAS_ADF=1;
1; # This is always needed at the end
```

`EXTRAOPTS` are options understood by the `scanimage` command, and any options can be passed. In this case we disabled SW deskew and cropping in the driver, and made the default action in case of error for the scanner to stop. "ald" is page "leading edge" detection, which I felt was not needed as we want a full scan, even if we overscan a bit, rather than risk cutting off bits of the document.

The $DEVICE variable is the ID used by SANE to know which scanner to use. You can find out what your scanner(s) are by running `listDevices`, like so:

```
~ $./listDevices
Detected devices:
	epkowa:interpreter:001:012
```

In this case only my Epson is powered on, the "epkowa" line would be placed in $DEVICE. 

$HAS_ADF is the final option, and it defines whether this specific scanner supports "ADF" (Auto document feeding). This is when you stick a stack of papers in a tray and it scans them all automatically. 

### Job configuration file ##

The job configuration file allows you to define certain scan jobs, if you have more than one type of scan job. For example, I have two types of job scans. My "Archive", which is for long term high quality storage of OCRed files, usually for documents that I have since shredded but may need a copy in future and my "Email" config, which uses a low resolution (and greyscale) scanning with no OCR for the smallest output suitable for attachment to e-mails.

There are example configurations in the "config" directory, but a minimal configuration would look like this:
```
$SCAN_DPI=450;
$OCR_ENABLED=1; # If you want to OCR the text and store it in the metadata
$OUTFORMAT="pdf"; #"pdf" or "png" supported only
$ADF_ENABLED=1;
$ENABLE_DUPLEX=1; # If your scanner supports it, automatically scan both sides, ADF scanners usually do
push @EXTRAOPTS, qw/--page-height 320 --page-width 211 -x 211 -y 320 --mode color/;
1; # This is always needed at the end

```

Most of the above is pretty self explanatory. I set 450 DPI as the scan size as I find this is a good balance between file size, scanning speed, quality of OCR accuracy while being able to look similar to the original in print quality if there is a need to print it out.

In this case we use `EXTRAOPTS` to specify the paper size and whether we want colour scanning. These options are added to the ones in the scanner configuration file.

#### Extra option: callback_last

As each job configuration file is in fact valid Perl code, this gives us a lot of flexibility. One thing I added is the "callback_last" option. If you define this subroutine in your config file, it will be executed just before the scanned images and OCRed text are merged to PDF (or EXIF tagged for images) and sent to their destination.

Here is a simple example with comments:
```
# "callback_last" is an optional routine which lets you define a final subroutine to act upon 
# the scanned documents before they reach their final destination (either as PNGs or
# a merged PDF).
#
# Variables available:
#	$FINALDST (final destination, this is where your scanned documents end up)
#	$TEMPDIR (where our temporary files are prior to being merged to PDF
#	and/or copied to $FINALDST).
#	$NAME (the prefix defined as your argument)
#
# The file structure in $TEMPDIR is as follows:
#	$NAME_%0d.png		# The scanned image as received from SANE
#	$NAME_%0d.png.txt 	# The OCR'd text (if enabled and OCR successful)
sub callback_last {
	print "Hello World!\n";
}

```

The example above just prints "hello world" but as noted in the comments, you have access to the temporary directory, the final destination folder and the name as defined when you called the function. The file structure shows you how the layout looks, each page is suffixed 01/02/03/etc... There really is no limit to what you can do here, whatever is possible in Perl on your machine can be written here.


## Known methods of searching

1. "grep" (the one I use most often). A simple "grep -ir $search_term $scan_dir" works well enough to narrow down which scanned documents I am interested in. 
2. GNOME used to have a desktop search tool called "Beagle" (http://beagle-project.org/) which would search image EXIF data. This was the original inspiration for writing this tool, as the ability to just type in text and get scanned images back really helped with archival. Indeed Beagle is what I used to originally use with SDAT. However it seems to be dead (last release was 2006), which I guess dates both me and this script quite a bit XD

There is an entire article on Wikipedia about it (https://en.wikipedia.org/wiki/Desktop_search) however i have not used anything apart from the above. I don't know what software supports indexing EXIF comments on images. If you have successfully used another piece of software, feel free to let me know and I can post it here :-) 

## Gotchas

Here are some gotchas I have come across when using this system:

* Don't invert the text half way through the scan. This is not a problem with SDAT as such, but the underlying OCR software. Generally this isn't a problem if you are scanning a single document. However if you are scanning lots of little receipts as part of an expenses document you can put one upside down. I did this once and while nothing broke, tesseract did sit there and consume 100% CPU trying to decode the upside-down text until I got sick of waiting, killed it and then re-scanned with the receipt the right way up.

* Make sure you have enough space in "/tmp". This software makes use of /tmp to store both the final copy and any intermediate stages. On a 600dpi scan this means you could use a good 500MB of data in temp files. If you run out of space half way through a scan it can get messy (you get errors that indicate failure, but not necessarily that the reason may be lack of free space). 

* Leading from above, the software will delete its temporarily files from /tmp/SDAT in the case of a successful scan and OCR. However if you cancel the program, or something raises an error, it does not delete the tmpfiles (this is useful for debugging). As such be aware you may have leftover data files using up space in /tmp/SDAT that you may want to clear out. For many distros tmps is a ramdisk (tmpfs) so should be cleared on reboot, but for those where it isn't, you can accumulate a lot of wasted space.

## Development

If you want to help develop SDAT, even if it just to define more configs, please follow these procedures:

1. Branch off the "version4" branch in git
2. make your changes in your own branch, test etc..
3. When ready, then issue a merge request to version4 branch, which I can review and merge if all is well.
4. Once tested and ready for release, I will merge to master, which should always be a stable working and bug free branch.


## News:

### April 2026
 Version 4 in development, changes:
* Removal of deprecated environment variable "SDAT_NO_OCR"
* re-writing OCR logic to split it from scanning logic.
* Work on implementing alternative OCR software (ML powered OCR using Ollama RPC)
* Code refactoring
* Completed "Future Plans" by creating "reprocess" script, to re-OCR existing PDF and PNG files and update the metadata
* Refactored readme structure, biggest change is News section is now at the bottom

Currently version 4 supports both the original tesseract OCR as well as using ollama RPC calls to a OCR machine learning model (I am using glm-ocr). So now you can choose between using tesserect or a ollama support ML model.

As far as tesserect vs glm-ocr, glm-ocr is much better at correctly recognising text. Not only does it capture more text than tesserect does, that which it captures is more correct. I hardly notice any mistakes in the OCR'd text vs the original.

However glm-ocr is much slower, more resource hungry (needs a beefy GPU and CPU, plus lots of RAM) and in some cases can be counter productive. During one test it could not OCR the text, so instead it decided to pontificate on whether the page I was scanning (an instruction manual) was in fact the cover of a Jane Austin novel or not. I made some tweaks to the prompt to get the model to just respond with "Cannot OCR Text" if it can't OCR the text, but still need to see if that does the trick reliably.

Tesseract however will either OCR the text (to varying accuracy), or give up and return nothing.


#### Current status
At the moment only the "reprocess.pl" script is working, and it has been tested with both OCR methods on updating the comments in PDF and PNG files. The rest of SDAT has not been tested yet, so version4 is still in development and not recommended for use unless you want to experiment and contribute.



### May 2025
* Code refactoring into newer Perl design, utilising Classes and strict mode.
* General cleanup of logic
* Restricted output to two modes: PNG or PDF, with tagging for each
	* The text is added as an Exif comment on PNGs
	* The text is added using the "keywords" field on PDFs, it is also added as a comment in the PDF source code as an extra (this is valid according to what I've read about the PDF standard).
* Updates to the configuration files to work with the new logic.


### April 2025
* Updates to version to take into account changes since 2021, specifically:
	* Tweaks for cross-compatibility and SDAT tested on FreeBSD
	* Updates to support newer tesseract and ImageMagick commands
	* Added some of the configs I use most often (e.g. PDF archiving)

### April 2021

New version 2 released, this has some new features, including configurable jobs and scanner configurations. Look at documentation below for more info. The old version (now renamed version 1) will live in the version 1 branch, if anyone needs it.


