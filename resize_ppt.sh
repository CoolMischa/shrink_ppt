#!/bin/bash
##
# Short bash script to shrink the images inside a PowerPoint presentation (nearly) without loss of quality.
# 
# Author: Mischa Soujon
# E-Mail: mischa@soujon-net.de
#
# Copyright 2020
#
##

OOBIN="/Applications/LibreOffice.app/Contents/MacOS/soffice"
# stat size for MacOS
STATSIZE='stat -f%z'
# stat size on GNU linux
# STATSIZE='stat --printf="%s"'

IMGDIR='img'
EMFDIR='emf'

rm -rf extraction
rm -rf resized
rm -rf "${IMGDIR}"
rm -rf "${EMFDIR}"

mkdir -p extraction "${EMFDIR}" "${IMGDIR}" resized 

function calcNewFileFormat() {
	local path=$1 original=$2 fileformat

	opacity=$(convert ${path}/${original} -channel a -separate -scale 1x1! -format "%[fx:mean]" info:)
	is_transparend=$(echo "1-${opacity} > 0.75" |bc)
	format=$(magick ${path}/${original} -format "%[magick]\n" info: | tr 'A-Z' 'a-z')

	if [ "${format}" = "png" -a ${is_transparend} -eq 1 ]; then
		fileformat="png"
	else
		fileformat="jpg"
	fi

	echo "${fileformat}"
}

function replaceReferences() {
	local original=$1 newname=$2

	filenames=$(grep -ril --include '*.rels' --include '*.xml' "${original}" extraction/ppt )
	if [ ! "${filenames}" = "" ]; then
		echo "replace ${original} by ${newname} in:"
		echo "${filenames}"
		echo ${filenames} |tr ' ' '\n' |while read filename; do
			sed -e "s#${original}#${newname}#g" ${filename} > tmp
			mv tmp ${filename}
		done
		rm extraction/ppt/media/${original}
		cp resized/${newname} extraction/ppt/media/
	else
		echo "${original} not referenced!"
		rm extraction/ppt/media/${original}
	fi
}

# extract pptx to directory
unzip -q "${1}" -d extraction/
ORIG_FILE="$(basename ${1})"

# find big media >250k in size and copy to appropriate working dir
find extraction/ppt/media -type f -size +250k -exec file  {} \;| while IFS=' :' read file mime; do
	type=$(echo $mime|cut -d ' ' -f1)
	case $type in
		JPEG | PNG | GIF )
			cp "${file}" "${IMGDIR}/" 
		;;
		Windows )
			cp "${file}" "${EMFDIR}/"
		;;
		* )
			echo "File type ${type} (mime: ${mime} ) of file ${file} not handled yet"
		;;
	esac
done

# shrink the general imagery
echo "shrink images..."
ls -1 "${IMGDIR}"| while read original; do
	fileformat=$(calcNewFileFormat ${IMGDIR} ${original})
	newname="${original%%.*}.${fileformat}"
	
	# all images are larger than 250k => resize all
	convert -strip -quality 80 "${IMGDIR}/${original}" "resized/${newname}"
	replaceReferences "${original}" "${newname}"
done

if [ -x "${OOBIN}" ]; then
	# processing emf files
	echo "processing emf files..."
	ls -1 "${EMFDIR}"| while read original; do
		# convert to an OpenOffice document
		${OOBIN} --headless --convert-to odg --outdir "odg/" "${EMFDIR}/${original}"

		# unzip the image an rename it
		ooname="${original%%.*}.odg"
		imgname="${original%%.*}.png"
		unzip -q "odg/${ooname}" 'Pictures/*.png' -d "odg/"

		mv odg/Pictures/*.png "${EMFDIR}/${imgname}"
		rm -rf "odg"
		# if the size of the images exceeds 250k, shrink it
		imageSize=$(${STATSIZE} "${EMFDIR}/${imgname}")
		if [ ${imageSize} -ge 250000 ]; then
			fileformat=$(calcNewFileFormat ${EMFDIR} ${imgname})
			newname="${original%%.*}.${fileformat}"
			convert -strip -quality 80 "${EMFDIR}/${imgname}" "resized/${newname}"
		else
			newname="${imgname}"
			cp "${EMFDIR}/${imgname}" "resized/${newname}"
		fi
		replaceReferences "${original}" "${newname}"
	done
else
	echo "WARN: ${OOBIN} not available => emf files not processed"
fi

echo "zip files to shrunk presentation..."
cd extraction
zip -q -r "../shrunk_${ORIG_FILE}" ./*
cd - >/dev/null 2>&1
