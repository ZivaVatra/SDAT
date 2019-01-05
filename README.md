SDAT - Scanned document archival tool
====

This is a script for archival of Documents/Bills/Invoices/etc...
It scans the page, runs OCR on the text, and saves the text to the comment field in the metadata 

This allows indexing engines (e.g. Desktop search) to know what text the document contains, allowing for easier searching, while keeping the original text+format as an image scan. It saves a PNG file into the "./scans" output folder in CWD (configurable)

Requirements:
* tesseract (OCR)
* sane-tools (SCANNING)
* Exiv2 image metadata library (for adding text to comment field)
* imageMagick tools (FORMAT CONVERSION)

Usage:
----


* There must be a "./scans" folder in the CWD. This is where the results are saved
* The script will attempt to scan and use the first found scanning device. It will then save this in a file in CWD called "devicename". You can delete this to force re-detection, or put your own (valid) ID in there to override the autodetection.
* You may need to set TESS_DATADIR variable to something other than the default, as this varies by tesseract version (and distro package)
* There are other options you can change by editing the script. A common one is $SCAN_DPI, the higher the DPI the more accurate the OCR (and the higher quality archive copy you keep), but it takes longer to scan and uses more space. The default is set to 600dpi, as this is the best archive quality vs space I found for my needs.
* Run the script as follows:
<code> ./SDAT.sh $Name_of_output_file </code> (You don't have to put the extension, it is done automatically).

On success the script will display the scanned file. You don't have to do anything to confirm, you can just close the display. The file is saved no matter what.

Known methods of searching
----

1. "grep" (the one I use most often). A simple "grep -ir $search_term $scan_dir" works well enough to narrow down which scanned documents I am interested in
2. GNOME used to have a desktop search tool called "Beagle" (http://beagle-project.org/) which would search image EXIF data. This was the original inspiration for writing this tool, as the ability to just type in text and get scanned images back really helped with archival. Indeed Beagle is what I used to originally use with SDAT. However it seems to be dead (last release was 2006), which I guess dates both me and this script quite a bit XD

There is an entire article on wikipedia about it (https://en.wikipedia.org/wiki/Desktop_search) however i have not used anything apart from the above. I don't know what software supports indexing EXIF comments on images. If you have sucessfully used another piece of software, feel free to let me know and I can post it here :-) 

Gotchas
----

Here are some gotchas I have come across when using this system:

* Don't invert the text half way through the scan. This isn't a problem if you are scanning a single document. However if you are scanning lots of little receipts as part of an expenses document, you can get it wrong. I did this (one of the receipts was 180 degrees off), and while nothing broke, tesseract did sit there and consume 100% CPU trying to decode the upside-down text until I got sick of waiting, killed it and then re-scanned with the text correctly up

* Make sure you have enough space in "/tmp". This software makes use of /tmp to store both the "final scan" copy, and the "OCR scan" copy, plus any temporarily files for the OCR. On a 600dpi scan this means you could use a good 500MB of data in temp files. If you run out of space half way through a scan it can get messy (you get errors that indicate failure, but not that the reason may be lack of free space). 

* Leading from above, the software will delete its temporarily files from /tmp in the case of a successful scan and OCR. However if you cancel the program, or something raises an error, it does not delete the tmpfiles (this is useful for debugging). As such be aware you may have leftover datafiles using up space in /tmp that you may want to clear out. 
