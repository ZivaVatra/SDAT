SDAT - Scanned document archival tool
====

News:
----
- April 2025: Updates to version to take into account changes since 2021, specifically:
* Tweaks for cross-compatibility and SDAT tested on FreeBSD
* Updates to support newer tesseract and ImageMagick commands
* Added some of the configs I use most often (e.g. PDF archiving)

- April 2021: New version 2 released, this has some new features, including configurable jobs and scanner definitions. Look at documentation below for more info. The old version (now renamed version1) will live in the version1 branch, if anyone needs it.


Overview:
----

This is a collection of programs that handle archival of Documents/Bills/Invoices/etc...

The basic idea is of an automated system that scans the page, runs OCR on the text, and saves the text to the comment field in the metadata as an image. 

This allows indexing engines (e.g. Desktop search) to know what text the document contains, allowing for easier searching, while keeping the original text+format as an image scan. It saves a PNG file into the "./scans" output folder in CWD (configurable).


However as my needs have grown, so has the flexibility of the program. Its core purpose is the above, but it also allows you to configure it for more advanced processing.

Requirements:
* tesseract (OCR)
* sane-tools (SCANNING)
* Exiv2 image metadata library (for adding text to comment field)
* imageMagick tools (FORMAT CONVERSION)

Usage:
----

The main entry point is the "SDAT.pl" program. Usage is as follows:

`SDAT.pl $scanner_definition $config_file $output_folder $prefix`

The $scanner_definition is what holds your device ID, as we all as any extra options you want to add to your scanner. Each scanner has variations in behviour and features, which can be defined here.

If you don't know what your scanner ID is, the `get_device_names` program will list all the scanners SANE knows about, along with their ID's.

The $config_file is a configuration file for your job. For more information for the kind of things you can define in your job, please see "Configuratinon" section.

"$output_folder" is the target where your files will be saved, while "$prefix" is the name of the file. If you only scan one file without ADF, this will just end up being "$prefix.png". If you are using an ADF scanner with multiple scanned pages, then each scan will be separate file, with the format $prefix\_$02d. For example, running:

`./SDAT_ADF.pl ./scanners/fujitsu_snapscan.scanner ./configs/archive.conf /storage/backups/scanned_documents/2020/ energy_bill` Will use my Fujistu ADF scanner to scan all the pages in the tray, following the "archive" configuration, which is a high quality archival PNG store, with OCR metadata. When done, the output should look like this:
```
  /storage/backups/scanned_documents/2020/energy_bill_01
  /storage/backups/scanned_documents/2020/energy_bill_02
  /storage/backups/scanned_documents/2020/energy_bill_03
  /storage/backups/scanned_documents/2020/energy_bill_04
```
In this case, it is a two page document, double sided, so we end up with 4 numbered pages in total.

When ADF is supported, SDAT will scan each page until the tray is empty. While doing this, in the background it will start the process of OCR and conversion. Once the scanning is done, the executable will wait until all processing child process are done.

Configuration
----

## Scanner definition file ##

Each scanner is different, so to support multiple scanners, including a computer with multiple scanners attached, the concept of "scanner definion" files have been added in this version. This allows you to pass specific scanner configuration to SDAT, along with the scanner ID. I have included the definition files for my two scanners, but feel free to submit your own.
The configuration looks like this:
```
$EXTRAOPTS .= " --ald=no --df-action Stop --swdeskew=no --swcrop=no";
$DEVICE="fujitsu:ScanSnap S500:14658";
$HAS_ADF=1;
1; # This is always needed at the end
```

$EXTRAOPTS are options understood by the `scanimage` command, and any options can be passed. In this case we disabled SW deskew and cropping in the driver, and made the default action in case of error for the scanner to stop. "ald" is page "leading edge" detection, which I felt was not needed as we want a full scan, even if we overscan a bit, rather than risk cutting off bits of the document.

the $DEVICE variable is the ID used by SANE to know which scanner to use. You can find out what your scanner(s) are by running `get_device_names`, like so:

```
~ $./get_device_names
Detected devices:
	epkowa:interpreter:001:012

```

In this case only my Epson is powered on, the "epkowa" line would be placed in $DEVICE. 

$HAS_ADF is the final option, and it defines whether the specific scanner support "ADF" (Auto document feeding). This is when you stick a stack of papers in a tray and it scans them all automatically. Depending on whether this is set or not, different logic paths in SDAT will be executed.

## Job configuration file ##

The job configuration file allows you to define certain scan jobs, if you have more than one type of scan job. For example, I have two types of job scans. My "Archive", which is for long term high quality storage of OCR'ed files, usually for documents that I have since shredded, but may need a copy in future.

Both configs are provided in the "configs" directory, but here is how they look like:

```
$SCAN_DPI=600;
# Extra options for scanimage, for specific scanners
# These extra opts are for A4 paper size (defined as 210x297mm, and colour mode
$EXTRAOPTS .= " --page-height 320 --page-width 211 -x 211 -y 300 --mode color";
#And these for A5 (defined as 148 x 210mm)
#$EXTRAOPTS .= " --page-height 211 --page-width 150 -x 150 -y 211 ";
```

I set 600 DPI as the scan size, as I find this is a good size to provide decent OCR accuracy, and it is also big enough to clearly see even small legal text. It can also be printed and still look similar to the original in print quality if needed.

The $EXTRAOPTS in this case specify the paper size, and whether we want colour scanning. I found out that different scanners default to different modes (e.g my Epson defaults to colour scanning, but the Fujitsu to Black and White), so in the interests of being explicit, I defined this job config to always scan in colour.


The next config is called "adf_email_pdf.conf", and it does what it says on the tin. I wrote this becauses I needed the ability to scan a bunch of documents, and generate a PDF small enough to be able to send via email. This is the opposite of the "Archive" config in that sense, as the documents were not being shredded I did not need very high quality archival copies.

```
$SCAN_DPI=100;
# Extra options for scanimage, for specific scanners
$EXTRAOPTS .= " --page-height 320 --page-width 211 -x 211 -y 300 --mode color";
#And these for A5 (defined as 148 x 210mm)
#$EXTRAOPTS .= " --page-height 211 --page-width 150 -x 150 -y 211 ";

# This is an optional routine, which lets you define a final subroutine to act upon 
# the scanned documents. In this example, we are:
# 1. converting them from png to highly compressed JPEG (smaller for email)
# 2. merging them into one final pdf
# 3. deleting everything apart from the pdf in that folder
#
# Variables available:
#	$FINALDST (final destiation, this is where your scanned documents end up)
#	$NAME (the prefix defined as your argument)
sub callback_last {
	my @files = glob("$FINALDST/*.png");
	my $arglist = "";
	print "Converting png to compressed JPEG\n";
	foreach(@files) {
		my $outfile = $_;
		$outfile =~ s/\.png/\.jpg/;
		die("Could not convert $_\n") if system("convert -quality 85% $_ $outfile");
		unlink($_); # Delete original if successful
		$arglist .= "$outfile ";
	}
	print "Merging to PDF\n";
	die("Could not merge to pdf $NAME.pdf\n") if system("convert $arglist $FINALDST/$NAME.pdf");
	system("rm $arglist"); # Try to delete the jpeg files
}
1; # This is always needed at the end
```

As you can see, this config is a bit more complex, and it makes use of a powerful new feature of SDAT. The "callback_last" function. You have the ability to execute a custom function at the end of the scan, to do whatever you want to the resultant scanned documents. In this case, I had a small resolution (100DPI), then converted the files to JPEG (As they are smaller for colour scans), then merged them to a pdf file.

If you have not yet noticed, the config files are in fact Perl code, so you have a lot of flexibility in how you configure things. You could even have things like $SCAN_DPI be dynamically generated on the fly, pulled in from another source, etc...

As this is a program that is not designed for internet connectivity, or shared use by untrusted people, the system is designed for maximum flexibility and power.


Known methods of searching
----

1. "grep" (the one I use most often). A simple "grep -ir $search_term $scan_dir" works well enough to narrow down which scanned documents I am interested in
2. GNOME used to have a desktop search tool called "Beagle" (http://beagle-project.org/) which would search image EXIF data. This was the original inspiration for writing this tool, as the ability to just type in text and get scanned images back really helped with archival. Indeed Beagle is what I used to originally use with SDAT. However it seems to be dead (last release was 2006), which I guess dates both me and this script quite a bit XD

There is an entire article on wikipedia about it (https://en.wikipedia.org/wiki/Desktop_search) however i have not used anything apart from the above. I don't know what software supports indexing EXIF comments on images. If you have sucessfully used another piece of software, feel free to let me know and I can post it here :-) 

Gotchas
----

Here are some gotchas I have come across when using this system:

* Don't invert the text half way through the scan. This isn't a problem if you are scanning a single document. However if you are scanning lots of little receipts as part of an expenses document, you can get it wrong. I did this (one of the receipts was 180 degrees off), and while nothing broke, tesseract did sit there and consume 100% CPU trying to decode the upside-down text until I got sick of waiting, killed it and then re-scanned with the text correctly up

* Make sure you have enough space in "/tmp". This software makes use of /tmp to store both the final copy and any intermidiate stages. On a 600dpi scan this means you could use a good 500MB of data in temp files. If you run out of space half way through a scan it can get messy (you get errors that indicate failure, but not that the reason may be lack of free space). 

* Leading from above, the software will delete its temporarily files from /tmp in the case of a successful scan and OCR. However if you cancel the program, or something raises an error, it does not delete the tmpfiles (this is useful for debugging). As such be aware you may have leftover datafiles using up space in /tmp that you may want to clear out. For many distros tmps is a ramdisk (tmpfs) so should be cleared on reboot, but for those where it isn't, you can accumulate a lot of wasted space.


Future plans
----
* Create a third executable, probably called "reprocess", which will re-do the OCR and exif tagging stages on existing files. This is useful as when OCR technology improves, we can redo the OCR on our pre-scanned archives to improve them without needing the originals.


Development
----

If you want to help develop SDAT, even if it just to define more configs, please follow these procedures:

1. Branch off the "version2" branch in git
2. make your changes in your own branch, test etc..
3. When ready, then issue a merge request to version2 branch, which I can review and merge if all is well.
4. Once tested and ready for release, I will merge to master, which should always be a stable working and bug free branch.


