#!/bin/bash


OOBIN="/Applications/LibreOffice.app/Contents/MacOS/soffice"
# stat size for MacOS
STATSIZE='stat -f%z'
# stat size on GNU linux
# STATSIZE='stat --printf="%s"'



rm -rf extraction
rm -rf resized

rm -rf toshrink
rm -rf toshrinkemf


mkdir -p extraction toshrink toshrinkemf resized

# extract pptx to directory
unzip -q "${1}" -d extraction/
ORIG_FILE="$(basename ${1})"

# find big media >250k in size and copy to resizing dir
find extraction/ppt/media -type f -size +250k -exec file  {} \;| while IFS=' :' read file mime; do
	type=$(echo $mime|cut -d ' ' -f1)
	case $type in
		JPEG | PNG | GIF )
			cp "${file}" toshrink/
		;;
		Windows )
			cp "${file}" toshrinkemf/
		;;
		* )
			echo "File type ${type} (mime: ${mime} ) of file ${file} not handled yet"
		;;
	esac
done

# shrink the general imagery
ls -1 toshrink| while read original; do

	opacity=$(convert toshrink/${original} -channel a -separate -scale 1x1! -format "%[fx:mean]" info:)
	is_transparend=$(echo "1-${opacity} > 0.75" |bc)

	format=$(magick toshrink/${original} -format "%[magick]\n" info: | tr 'A-Z' 'a-z')

	if [ "${format}" = "png" -a ${is_transparend} -eq 1 ]; then
		TGT_EXT='png'
		newname="${original%%.*}.png"
	else
		TGT_EXT='jpg'
		newname="${original%%.*}.jpg"
	fi

	convert -strip -quality 80 toshrink/${original} resized/${newname}
	filenames=$(grep -ril --include '*.rels' --include '*.xml' "${original}" extraction/ppt )
	if [ ! "${filenames}" = "" ]; then
		echo ${filenames} |tr ' ' '\n' |while read filename; do
			echo "replace ${original} by ${newname} in ${filename}"
			sed -e "s#${original}#${newname}#g" ${filename} > tmp
			mv tmp ${filename}
		done
		rm extraction/ppt/media/${original}
		cp resized/${newname} extraction/ppt/media/
	else
		echo "${original} not referenced!"
		rm extraction/ppt/media/${original}
	fi
done

# shrink the general imagery
ls -1 toshrinkemf| while read original; do
	# convert to an OpenOffice document
	${OOBIN} --headless --convert-to odg --outdir "toshrinkemf/" "toshrinkemf/${original}"

	# unzip the image an rename it
	ooname="${original%%.*}.odg"
	unzip "toshrinkemf/${ooname}" 'Pictures/*.png'
	imgname="${original%%.*}.png"
	mv Pictures/*.png "toshrinkemf/${imgname}"

	rm -f "toshrinkemf/${ooname}"

	# if the size of the images exceeds 250k, shrink it
	imageSize=$(${STATSIZE} "toshrinkemf/${imgname}")
	if [ ${imageSize} -ge 25000 ]; then
		opacity=$(convert toshrinkemf/${imgname} -channel a -separate -scale 1x1! -format "%[fx:mean]" info:)
		is_transparend=$(echo "1-${opacity} > 0.75" |bc)

		format=$(magick toshrinkemf/${imgname} -format "%[magick]\n" info: | tr 'A-Z' 'a-z')

		if [ "${format}" = "png" -a ${is_transparend} -eq 1 ]; then
			TGT_EXT='png'
			newname="${original%%.*}.png"
		else
			TGT_EXT='jpg'
			newname="${original%%.*}.jpg"
		fi

		convert -strip -quality 80 toshrinkemf/${imgname} resized/${newname}
	else
		newname="${imgname}"
		cp toshrinkemf/${imgname} resized/${newname}
	fi
	filenames=$(grep -ril --include '*.rels' --include '*.xml' "${original}" extraction/ppt )
	if [ ! "${filenames}" = "" ]; then
		echo ${filenames} |tr ' ' '\n' |while read filename; do
			echo "replace ${original} by ${newname} in ${filename}"
			sed -e "s#${original}#${newname}#g" ${filename} > tmp
			mv tmp ${filename}
		done
		rm extraction/ppt/media/${original}
		cp resized/${newname} extraction/ppt/media/
	else
		echo "${original} not referenced!"
		rm extraction/ppt/media/${original}
	fi
done

cd extraction
zip -q -r "../shrinked_${ORIG_FILE}" ./*
cd - >/dev/null 2>&1
