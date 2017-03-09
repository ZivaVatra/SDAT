SDAT
====

This is a script for archival of Documents/Bills/Invoices/etc...
It scans the page, runs OCR on the text, and saves the text to the comment field in the metadata

This allows indexing engines (e.g. Desktop search) to know what text the document contains, allowing
for easier searching, while keeping the original text+format as an image scan.
It saves a PNG file into the output folder

----

Requirements:
    tesseract (OCR)
    sane-tools (SCANNING)
    Exiv2 image metadata library (for adding text to comment field)
	imageMagick tools (FORMAT CONVERSION)

<pre>
Usage:
	* Run the script as follows:
		./SDAT.py $filename $final_output_dir
	* The script will auto-detect rotation of text, so you don't have to worry about it
	* The script will also create the target folder if necessary
	* By default the script writes tmpfiles to /tmp/scanning
	* However each job has its own Unique ID, so you can run multiple scripts in parallel, they use the same folder, but will not interfere with each other
	
</pre>
