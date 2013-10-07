#!/bin/sh

# Roughly, for each key, for each other key, until you get to (m-1) you encrypt the payload to the rest of the keys.
# Then you encypt that to the higher key, and bundle all of those together with tar, and encrypt that to the higher, etc.
# At the top level you end up with a bunch of files, one for each user, that they can decrypt to get a tarball.
# That tarball contains a similar encrypted file for each other key.
# When given to that person, they can decrypt it to get another tarball to give to any of the others (not including the first)
# The second last person gets a single file that can be decrypted by any of the people who weren't in the path leading to that file.

KEYS=""
INPUTS=""
NUM=""

usage() {
	(
	printf "Encrypts given payloads to given keys, such that any N of them could decrypt the payload, but not less.\n"
	printf "  -n NUM   Number of keys required to decrypt the payloads\n"
	printf "  -r ID    Key ID of one of the recipients. Can be anything gpg understands\n"
	printf "  -f FILE  File to encrypt. If multiple files are given, each of them are encrypted as separate blobs\n"
	printf "  There must be more than NUM IDs given\n"
	) >&2
}

while getopts "hn:r:f:" flag; do
	case "$flag" in
		n) NUM="$OPTARG";;
		h)
			usage
			exit 0;;
		r)
			if echo "meow" | gpg --encrypt -r "$OPTARG" 2> /dev/null > /dev/null; then
				KEYS="$(printf '%s\n%s\n' "$KEYS" "$OPTARG")"
			else
				echo "\"$OPTARG\" is not a valid keyid" >&2
				exit 1
			fi;;
		f) 
			if [ -r "$OPTARG" ]; then
				FILES="$(printf '%s\n%s\n' "$FILES" "$OPTARG")"
			else
				echo "\"$OPTARG\" is not a valid file" >&2
				exit 1
			fi;;
	esac
done

# Remove first item, which will always be a blank line, and dedupe
KEYS="$(printf "%s" "$KEYS" | sed 1d | sort | uniq)"
FILES="$(printf "%s" "$FILES" | sed 1d | sort | uniq)"

if [ -z "$FILES" ]; then
	echo "No input files given." >&2
	exit 1
fi

if ! [ "$NUM" -gt 0 ]; then
	echo "Must be given an integer greater than 0" >&2
	exit 1
fi

if [ -z "$KEYS" -o "$(printf "%s\n" "$KEYS" | wc -l)" -le "$NUM" ]; then
	echo "Must be given more than "$NUM" keys." >&2
	exit 1
fi

# $1 is the file to encrypt, $2 is the list of users to encrypt to, $3 is the number of keys required to decrypt it, $4 is the tempdir that will be cleaned up later
encrypt_file() {
	file="$1"
	keys="$2"
	num="$3"
	tempdir="$4"
	filename="$file.$(printf '%s' "$keys" | tr '\n' '.').gpg"
	if [ "$num" -eq 1 ]; then
		# This is the bottom of the tree, here we just encrypt the payload to all of the remaining keys
		(
		printf "%s\n" "$keys" | sed 'i-r'
		printf -- "-o\n%s\n--encrypt\n%s\n" "$filename" "$file"
		) | xargs gpg
	else
		# Pull each of the keys out, and get recurse on the rest
		#   It returns the list of files
		#     If that list has more than one item, tar them up and only deal with the tar'd one
		#   Encrypt that file to the current key
		#   Return the name of the tar'd files for each key
		seq 1 "$(printf '%s\n' "$keys" | wc -l)" | while read i; do
			this_key="$(printf '%s\n' "$keys" | sed -n "${i}p")"
			other_keys="$(printf '%s\n' "$keys" | sed "${i}d")"
			sub_files="$(encrypt_file "$file" "$other_keys" "$(expr "$num" - 1)" "$tempdir")"
		done
	fi
	printf "%s\n" "$filename"
}

tempdir="$(mktemp -d)"
# I have to do it this way to preserve stdin
printf '%s\n' "$FILES" | while read this_file; do
	encrypt_file "$this_file" "$KEYS" "$NUM" "$tempdir" > /dev/null
done
rm -rf "$tempdir"
