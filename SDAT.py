#!/usr/bin/env python2
# vim: ts=4 ai
# SDAT - Scanned document archival tool
#
# Copyright 2017 Ziva-Vatra, Belgrade
# (www.ziva-vatra.com, mail: info@ziva_vatra.com)
#
# Project URL: http://www.ziva-vatra.com/index.php?aid=71&id=U29mdHdhcmU=
# Project REPO: https://github.com/ZivaVatra/SDAT
#
# Licensed under the GNU GPL. Do not remove any information from this header
# (or the header itself). If you have modified this code, feel free to add your
# details below this (and by all means, mail me, I like to see what other
# people have done)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License (version 2)
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
# USA.
#
#
# This is a script for archival of Documents/Bills/Invoices/etc...
# It scans the page, runs OCR on the text, and saves the text to the comment
# field in the metadata
# This allows indexing engines (e.g. Desktop search) to know what text the
# document contains, allowing
# for easier searching, while keeping the original text+format as an image
# scan.
# It saves a PNG file into the $FINALDST folder

# Requirements:
#  tesseract (OCR)
#  sane-tools (SCANNING)
#  Exiv2 image metadata library (for adding text to comment field)
#  imageMagick tools (FORMAT CONVERSION)
#

import os
import subprocess
import sys
import uuid


def get_device():
	if os.path.exists("./devicename") is True:
		with open("./devicename", 'r') as fd:
			return fd.read()

	data = subprocess.check_output(['scanimage', '-L'])
	data = data.split(' ')[1]
	data = data.replace('`', '')
	data = data.replace('\'', '')
	with open("./devicename", "w") as fd:
		fd.write(data)
	return data


def exe(cmd):
	return subprocess.check_call(cmd)


def bgexe(cmd):
	return os.spawnl(os.P_NOWAIT, cmd)


def scanit(mode, resolution, output, fail=False):

	print "Waiting for scanning to finish"
	try:
		data = subprocess.check_output([
			"scanimage",
			"-v",
			"-p",
			"--format=tiff",
			"--mode", mode,
			"-d", get_device(),
			"--resolution",
			str(resolution)
		])
	except subprocess.CalledProcessError as e:
		if fail is False:
			print "Got Error %s. Attempting to re-detect scanner" % e
			os.unlink("./devicename")
			get_device()
			return scanit(mode, resolution, output, True)
		else:
			print "Still unable to scan. Aborting execution."
			raise(e)

	with open(output, 'w') as fd:
		fd.write(data)


def s600dpi_col(output):
	scanit("color", 600, output)

def s1200dpi_col(output):
	scanit("color", 1200, output)

def s600dpi_gr(output):
	scanit("gray", 600, output)


def s1200dpi_gr(output):
	scanit("gray", 1200, output)


def ocrit(input_image, output_text_file, lang="eng"):
	return exe([
		"tesseract",
		input_image,
		output_text_file.replace('.txt', ''),
		"--tessdata-dir",
		"/usr/share/tesseract-ocr/",
		"-l",
		lang
	])


def topng(input, output):
	exe([
		"convert",
		"-compress",
		"Zip",
		input,
		output
	])


def addComment(input_file, output_image):
	with open(input_file, 'r') as fd:
		input_text = fd.read()

	exe([
		"exiv2",
		"-M set Exif.Photo.UserComment charset=Ascii %s" % input_text,
		output_image
	])


def waituntildone(pid):
	return os.waitpid(pid, 0)

if __name__ == "__main__":
	TPATH = "/tmp/scanning/"
	NAME = sys.argv[1]  # filename, first argument given to script
	device = get_device()
	print "Using Device: ", device

	RANDSTR = str(uuid.uuid4())
	FINALDST = sys.argv[2]
	if not os.path.exists(FINALDST):
		os.mkdir(FINALDST)

	print("Scanning filename: %s (Final destination: %s), CTRL-C to cancel" % (
		NAME, FINALDST
	))

	if not os.path.exists(TPATH):
		os.mkdir(TPATH)

	# 1. Scan the image (gray for OCR)
	grayfile = os.path.join(TPATH, "scan_gr", RANDSTR + ".tif")

	if not os.path.exists(os.path.join(TPATH, "scan_gr")):
		os.mkdir(os.path.join(os.path.join(TPATH, "scan_gr")))

	if not os.path.exists(os.path.join(TPATH, "scan_col")):
		os.mkdir(os.path.join(TPATH, "scan_col"))

	s1200dpi_gr(grayfile)

	# 2. Scan the colour image we will store
	colfile = os.path.join(TPATH, "scan_col", RANDSTR + ".tif")
	s1200dpi_col(colfile)

	textfile = os.path.join(TPATH, "scan_txt" + RANDSTR + ".txt")
	ocrpid = ocrit(grayfile, textfile)

	# Right, the below needs no user input, so we can just fork and exit the
	# program.
	# this way we can go to the next scan while this does work in the background

	pid = os.fork()
	if (pid == 0):
		# ok, all done! Now convert to png and add text
		topng(colfile, os.path.join(TPATH, NAME + ".png"))
		outfile = os.path.join(TPATH, NAME + ".png")
		addComment(textfile, outfile)
		exe(["mv", "-v", outfile, FINALDST])
		subprocess.check_call("rm -v " + TPATH + "/*%s*" % RANDSTR, shell=True)
	else:
		bgexe([
			"display",
			"-sample",
			750,
			FINALDST,
			NAME + ".png"
		])
		exit(0)
