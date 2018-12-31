SDAT
====

This is a script for archival of Documents/Bills/Invoices/etc...
It scans the page, runs OCR on the text, and saves the text to the comment field in the metadata

This allows indexing engines (e.g. Desktop search) to know what text the document contains, allowing
for easier searching, while keeping the original text+format as an image scan.
It saves a PNG file into the $FINALDST folder

For full information, see the original web page:
	http://www.ziva-vatra.com/index.php?aid=71&id=U29mdHdhcmU=

----

Requirements:
    tesseract (OCR)
    sane-tools (SCANNING)
    Exiv2 image metadata library (for adding text to comment field)
	imageMagick tools (FORMAT CONVERSION)

<pre>
Usage:
	* There must be a "./scans" folder in the CWD. This is where the results are saved
	* The script will attempt to scan and use the first found scanning device. It will then save this in a file in CWD called "devicename". You can delete this to force re-detection, or put your own (valid) ID in there to override the autodetection.
	* You may need to set TESS_DATADIR variable to something other than the default, as this varies
	by tesseract version (and distro package)

	* Run the script as follows:
		./SDAT.sh $Name_of_scan_file

	On success the script will display the scanned file. You don't have to do anything to confirm, you can just close the display. The file is saved no matter what.

</pre>
