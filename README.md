SDAT - Scanned document archival tool
====

This is a collection of programs that handle archival of Documents/Bills/Invoices/etc...
The basic idea is of an automated system that scans the page, runs OCR on the text, and saves the text to the comment field in the metadata 

This allows indexing engines (e.g. Desktop search) to know what text the document contains, allowing for easier searching, while keeping the original text+format as an image scan. It saves a PNG file into the "./scans" output folder in CWD (configurable)

Requirements:
* tesseract (OCR)
* sane-tools (SCANNING)
* Exiv2 image metadata library (for adding text to comment field)
* imageMagick tools (FORMAT CONVERSION)

Overview:
----
There are two main perl programs, "SDAT.pl", and "SDAT_ADF.pl". They differ in the scanners they support. SDAT is for your normal flatbed scanner as most people have. The SDAT_ADF, as the name implies, is for "Auto document feeder" scanners, where you give the machine a stack of papers, and it scans the entire thing automatically.

These programs are primarily written for my scanners, as those are the only ones I have access to, so I can confim SDAT\* works on the following:
- SDAT: Epson V330 Perfection Photo scanner
- SDAT_ADF: Fujitsu ScanSnap 500 (S500)

For flatbed scanners, SDAT should work fine. However different ADF scanners have different settings, so the defaults in SDAF_ADF may not work. Best to try and make note of any differences. If there is demand I can see about adding a configuration file that allows you to modify parameters for specific scanners.

Usage:
----

Common to both:

* You may need to set TESS_DATADIR variable to something other than the default, as this varies by tesseract version (and distro package)
* There are other options you can change by editing the script. A common one is $SCAN_DPI, the higher the DPI the more accurate the OCR (and the higher quality archive copy you keep), but it takes longer to scan and uses more space. The default is set to 600dpi, as this is the best archive quality vs space I found for my needs.

SDAT:
-----
* Run the script as follows:
<code> ./SDAT.pl $target_folder $Name_of_output_file </code> (You don't have to put the extension, it is done automatically). A real world example I use is <code>./SDAT.pl /storage/backups/scanned_documents/2020/ energy_bill_page_1</code> as that way I can grep documents by year, which is good enough for me.

On success the script will display the scanned file. You don't have to do anything to confirm, you can just close the display. The file is saved no matter what.

SDAT_ADF:
* Run the script as follows:
<code> ./SDAT_ADF.pl $target_folder $output_file_suffix </code> 
A real world example I use is <code>./SDAT_ADF.pl /storage/backups/scanned_documents/2020/ energy_bill</code>.

When started with the suffix, SDAT_ADF will scan each page until the tray is empty. While doing this, in the background it will start the process of OCR and conversion. Once the scanning is done, the executable will wait until all processing child process are done. 

During this time, you can start the executable again in another window to scan another batch. As mentioned above, this version uses a suffix. So if our theoretical energy bill has 2 pages, double sided. Upon running <code> ./SDAT_ADF.pl /storage/backups/scanned_documents/2020/ energy_bill  </code>, the output should look like this:

*  /storage/backups/scanned_documents/2020/energy_bill_01
*  /storage/backups/scanned_documents/2020/energy_bill_02
*  /storage/backups/scanned_documents/2020/energy_bill_03
*  /storage/backups/scanned_documents/2020/energy_bill_04

An underscore and two digit number is appended to indicate the page number (as scanned from tray). My scanner can only fit 40 pages in the tray, for a max of 80 scanned sheets per batch, so decided on 2 digit zero led numbering.

Unlike SDAT, this executable will not display the scanned file. You can monitor the results using another program, I use "geeqie" as it monitors the dir and auto updates the preview, however you can use what you like (even if its just the preview on your file manager).


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
* Consolidating the logic into a core library, at the moment SDAT and SDAT_ADF have duplicated logic
* Create a third executable, probably called "reprocess", which will re-do the OCR stage on existing files. This is useful as when OCR technology improves, we can redo the OCR on our pre-scanned archives to improve them without needing the originals.

